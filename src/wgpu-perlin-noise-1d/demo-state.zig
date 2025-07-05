const std = @import("std");
const Random = std.Random;
const math = std.math;
const zglfw = @import("zglfw");
const zgpu = @import("zgpu");
const zgui = @import("zgui");
const wgpu = zgpu.wgpu;
const zm = @import("zmath");
const utils = @import("utils");
const createDepthTexture = utils.createDepthTexture;
const wgsl_vs = @embedFile("./vertices.wgsl");
const wgsl_fs = @embedFile("./fragment.wgsl");

const Vertex = struct {
    position: [3]f32,
    color: [3]f32,
};
const size = 400;

pub fn smoothstep(x: f32) f32 {
    const clamped_t = zm.clamp(x, 0.0, 1.0);
    return clamped_t * clamped_t * (3.0 - 2.0 * clamped_t);
}

pub const DemoState = struct {
    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
    pipeline: zgpu.RenderPipelineHandle,
    bind_group: zgpu.BindGroupHandle,
    vertex_buffer: zgpu.BufferHandle,
    index_buffer: zgpu.BufferHandle,
    depth_texture: zgpu.TextureHandle,
    depth_texture_view: zgpu.TextureViewHandle,
    vertex_data: [size]Vertex = [_]Vertex{undefined} ** size,
    prng: *Random.DefaultPrng,

    pub fn init(allocator: std.mem.Allocator, window: *zglfw.Window) !DemoState {
        const gctx = try zgpu.GraphicsContext.create(
            allocator,
            .{
                .window = window,
                .fn_getTime = @ptrCast(&zglfw.getTime),
                .fn_getFramebufferSize = @ptrCast(&zglfw.Window.getFramebufferSize),
                .fn_getWin32Window = @ptrCast(&zglfw.getWin32Window),
                .fn_getX11Display = @ptrCast(&zglfw.getX11Display),
                .fn_getX11Window = @ptrCast(&zglfw.getX11Window),
                .fn_getWaylandDisplay = @ptrCast(&zglfw.getWaylandDisplay),
                .fn_getWaylandSurface = @ptrCast(&zglfw.getWaylandWindow),
                .fn_getCocoaWindow = @ptrCast(&zglfw.getCocoaWindow),
            },
            .{},
        );
        errdefer gctx.destroy(allocator);

        // Create a bind group layout needed for our render pipeline.
        const bind_group_layout = gctx.createBindGroupLayout(&.{
            zgpu.bufferEntry(0, .{ .vertex = true }, .uniform, true, 0),
        });
        defer gctx.releaseResource(bind_group_layout);

        const pipeline_layout = gctx.createPipelineLayout(&.{bind_group_layout});
        defer gctx.releaseResource(pipeline_layout);

        const bind_group = gctx.createBindGroup(bind_group_layout, &.{
            .{ .binding = 0, .buffer_handle = gctx.uniforms.buffer, .offset = 0, .size = @sizeOf(zm.Mat) },
        });

        const pipeline = createPipeline(gctx, pipeline_layout);

        var prng = Random.DefaultPrng.init(blk: {
            var seed: u64 = undefined;
            try std.posix.getrandom(std.mem.asBytes(&seed));
            break :blk seed;
        });

        // Create a vertex buffer.
        const vertex_buffer = gctx.createBuffer(.{
            .usage = .{ .copy_dst = true, .vertex = true },
            .size = size * @sizeOf(Vertex),
        });

        var vertex_data: [size]Vertex = [_]Vertex{undefined} ** size;

        gctx.queue.writeBuffer(gctx.lookupResource(vertex_buffer).?, 0, Vertex, vertex_data[0..]);

        const vertexLength = vertex_data.len;
        const index_buffer = gctx.createBuffer(.{
            .usage = .{ .copy_dst = true, .index = true },
            .size = vertexLength * @sizeOf(u32),
        });

        // Create a depth texture and its 'view'.
        const depth = createDepthTexture(gctx);

        return DemoState{
            .allocator = allocator,
            .gctx = gctx,
            .pipeline = pipeline,
            .bind_group = bind_group,
            .vertex_buffer = vertex_buffer,
            .index_buffer = index_buffer,
            .depth_texture = depth.texture,
            .depth_texture_view = depth.view,
            .prng = &prng,
        };
    }

    pub fn deinit(self: *DemoState) void {
        self.gctx.destroy(self.allocator);
        self.* = undefined;
    }

    pub fn update(demo: *DemoState) void {
        zgui.backend.newFrame(
            demo.gctx.swapchain_descriptor.width,
            demo.gctx.swapchain_descriptor.height,
        );
    }

    pub fn draw(demo: *DemoState) void {
        demo.runCommands();
        const gctx = demo.gctx;

        if (gctx.present() == .swap_chain_resized) {
            // Release old depth texture.
            gctx.releaseResource(demo.depth_texture_view);
            gctx.destroyResource(demo.depth_texture);

            // Create a new depth texture to match the new window size.
            const depth = createDepthTexture(gctx);
            demo.depth_texture = depth.texture;
            demo.depth_texture_view = depth.view;
        }
    }

    pub inline fn createPipeline(gctx: *zgpu.GraphicsContext, pipeline_layout: zgpu.PipelineLayoutHandle) zgpu.RenderPipelineHandle {
        const vs_module = zgpu.createWgslShaderModule(gctx.device, wgsl_vs, "vs");
        defer vs_module.release();

        const fs_module = zgpu.createWgslShaderModule(gctx.device, wgsl_fs, "fs");
        defer fs_module.release();

        const color_targets = [_]wgpu.ColorTargetState{.{
            .format = zgpu.GraphicsContext.swapchain_format,
        }};

        const vertex_attributes = [_]wgpu.VertexAttribute{
            .{ .format = .float32x3, .offset = 0, .shader_location = 0 },
            .{ .format = .float32x3, .offset = @offsetOf(Vertex, "color"), .shader_location = 1 },
        };
        const vertex_buffers = [_]wgpu.VertexBufferLayout{.{
            .array_stride = @sizeOf(Vertex),
            .attribute_count = vertex_attributes.len,
            .step_mode = .vertex,
            .attributes = &vertex_attributes,
        }};

        const pipeline_descriptor = wgpu.RenderPipelineDescriptor{
            .vertex = wgpu.VertexState{
                .module = vs_module,
                .entry_point = "main",
                .buffer_count = vertex_buffers.len,
                .buffers = &vertex_buffers,
            },
            .primitive = wgpu.PrimitiveState{
                .front_face = .ccw,
                .cull_mode = .none,
                .topology = .line_strip,
            },
            .depth_stencil = &wgpu.DepthStencilState{
                .format = .depth32_float,
                .depth_write_enabled = true,
                .depth_compare = .less,
            },
            .fragment = &wgpu.FragmentState{
                .module = fs_module,
                .entry_point = "main",
                .target_count = color_targets.len,
                .targets = &color_targets,
            },
        };
        return gctx.createRenderPipeline(pipeline_layout, pipeline_descriptor);
    }

    pub inline fn runCommands(demo: *DemoState) void {
        const gctx = demo.gctx;
        const fb_width = gctx.swapchain_descriptor.width;
        const fb_height = gctx.swapchain_descriptor.height;

        const width_f32 = @as(f32, @floatFromInt(fb_width));
        const height_f32 = @as(f32, @floatFromInt(fb_height));
        const aspect_ratio = width_f32 / height_f32;

        const cam_world_to_view = zm.lookAtLh(
            zm.f32x4(0.0, 0.0, -1.0, 0.0),
            zm.f32x4(0.0, 0.0, 0.0, 0.0),
            zm.f32x4(0.0, 1.0, 0.0, 0.0),
        );

        const targetSpaceUnit = 2.0;

        const cam_view_to_clip = zm.orthographicLh(
            if (aspect_ratio > 1) targetSpaceUnit * aspect_ratio else targetSpaceUnit,
            if (aspect_ratio > 1) targetSpaceUnit else targetSpaceUnit / aspect_ratio,
            0.01,
            100.0,
        );
        const cam_world_to_clip = zm.mul(cam_world_to_view, cam_view_to_clip);

        const back_buffer_view = gctx.swapchain.getCurrentTextureView();
        defer back_buffer_view.release();
        const commands = commands: {
            const encoder = gctx.device.createCommandEncoder(null);
            defer encoder.release();

            pass: {
                const vb_info = gctx.lookupResourceInfo(demo.vertex_buffer) orelse break :pass;
                const ib_info = gctx.lookupResourceInfo(demo.index_buffer) orelse break :pass;
                const pipeline = gctx.lookupResource(demo.pipeline) orelse break :pass;
                const bind_group = gctx.lookupResource(demo.bind_group) orelse break :pass;
                const depth_view = gctx.lookupResource(demo.depth_texture_view) orelse break :pass;

                const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
                    .view = back_buffer_view,
                    .load_op = .clear,
                    .store_op = .store,
                }};
                const depth_attachment = wgpu.RenderPassDepthStencilAttachment{
                    .view = depth_view,
                    .depth_load_op = .clear,
                    .depth_store_op = .store,
                    .depth_clear_value = 1.0,
                };
                const render_pass_info = wgpu.RenderPassDescriptor{
                    .color_attachment_count = color_attachments.len,
                    .color_attachments = &color_attachments,
                    .depth_stencil_attachment = &depth_attachment,
                };
                const pass = encoder.beginRenderPass(render_pass_info);
                defer {
                    pass.end();
                    pass.release();
                }

                pass.setVertexBuffer(0, vb_info.gpuobj.?, 0, vb_info.size);
                pass.setIndexBuffer(ib_info.gpuobj.?, .uint32, 0, ib_info.size);

                pass.setPipeline(pipeline);

                const time = demo.gctx.stats.time;
                const time_u64 = @as(u64, @intFromFloat(time * 0.8));

                //draw 1D perlin noise
                const step = 4.0 / @as(f32, @floatFromInt(size - 1));
                for (demo.vertex_data, 0..) |_, i| {
                    const i_f32 = @as(f32, @floatFromInt(i));
                    const rand = demo.prng.random();
                    demo.prng.seed((i / 50) * 100 * time_u64);
                    const y_current = zm.mapLinearV(rand.float(f32), 0, 1, -0.9, 0.9);
                    demo.prng.seed(((i / 50) + 1) * 100 * time_u64);
                    const y_next = zm.mapLinearV(rand.float(f32), 0, 1, -0.9, 0.9);

                    const t = @as(f32, @floatFromInt(@mod(i, 50))) / (50 - 1);
                    const y = zm.lerpV(y_current, y_next, smoothstep(t));
                    demo.vertex_data[i] = .{
                        .position = [3]f32{ i_f32 * step - 2, y, 0.0 },
                        .color = [3]f32{ 1.0, 1.0, 0.0 },
                    };
                }

                gctx.queue.writeBuffer(gctx.lookupResource(demo.vertex_buffer).?, 0, Vertex, demo.vertex_data[0..]);

                {
                    const object_to_clip = cam_world_to_clip;
                    const mem = gctx.uniformsAllocate(zm.Mat, 1);
                    mem.slice[0] = zm.transpose(object_to_clip);
                    pass.setBindGroup(0, bind_group, &.{mem.offset});
                    pass.draw(size, 1, 0, 0);
                }
            }
            {
                const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
                    .view = back_buffer_view,
                    .load_op = .load,
                    .store_op = .store,
                }};
                const render_pass_info = wgpu.RenderPassDescriptor{
                    .color_attachment_count = color_attachments.len,
                    .color_attachments = &color_attachments,
                };
                const pass = encoder.beginRenderPass(render_pass_info);
                defer {
                    pass.end();
                    pass.release();
                }

                zgui.backend.draw(pass);
            }

            break :commands encoder.finish(null);
        };

        defer commands.release();
        gctx.submit(&.{commands});
    }
};
