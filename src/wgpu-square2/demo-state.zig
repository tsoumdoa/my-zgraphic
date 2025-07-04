const std = @import("std");
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

pub const DemoState = struct {
    allocator: std.mem.Allocator,
    gctx: *zgpu.GraphicsContext,
    pipeline: zgpu.RenderPipelineHandle,
    bind_group: zgpu.BindGroupHandle,
    vertex_buffer: zgpu.BufferHandle,
    index_buffer: zgpu.BufferHandle,
    depth_texture: zgpu.TextureHandle,
    depth_texture_view: zgpu.TextureViewHandle,

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

        // Create a vertex buffer.
        const vertex_buffer = gctx.createBuffer(.{
            .usage = .{ .copy_dst = true, .vertex = true },
            .size = 4 * @sizeOf(Vertex),
        });
        const vertex_data = [_]Vertex{
            .{ .position = [3]f32{ -0.5, -0.5, 0.0 }, .color = [3]f32{ 0.0, 1.0, 1.0 } }, // 0: Bottom-Left (Cyan)
            .{ .position = [3]f32{ 0.5, -0.5, 0.0 }, .color = [3]f32{ 1.0, 0.0, 1.0 } }, // 1: Bottom-Right (Magenta)
            .{ .position = [3]f32{ 0.5, 0.5, 0.0 }, .color = [3]f32{ 1.0, 1.0, 0.0 } }, // 2: Top-Right (Yellow)
            .{ .position = [3]f32{ -0.5, 0.5, 0.0 }, .color = [3]f32{ 1.0, 1.0, 1.0 } }, // 3: Top-Left (Black)
        };
        const index_data = [_]u32{ 0, 1, 2, 0, 2, 3 };
        gctx.queue.writeBuffer(gctx.lookupResource(vertex_buffer).?, 0, Vertex, vertex_data[0..]);

        // Create an index buffer.
        const vertexLength = vertex_data.len;
        const indexLength = index_data.len;
        const index_buffer = gctx.createBuffer(.{
            .usage = .{ .copy_dst = true, .index = true },
            .size = vertexLength * indexLength * @sizeOf(u32),
        });
        gctx.queue.writeBuffer(gctx.lookupResource(index_buffer).?, 0, u32, index_data[0..]);

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
                .topology = .triangle_strip,
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

        const cam_world_to_view = zm.lookAtLh(
            zm.f32x4(0.0, 0.0, -2.0, 1.0),
            zm.f32x4(0.0, 0.0, 0.0, 0.0),
            zm.f32x4(0.0, 1.0, 0.0, 0.0),
        );
        const cam_view_to_clip = zm.perspectiveFovLh(
            0.25 * math.pi,
            @as(f32, @floatFromInt(fb_width)) / @as(f32, @floatFromInt(fb_height)),
            0.01,
            200.0,
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

                //draw triangle
                {
                    const object_to_clip = cam_world_to_clip;
                    const mem = gctx.uniformsAllocate(zm.Mat, 1);
                    mem.slice[0] = zm.transpose(object_to_clip);
                    pass.setBindGroup(0, bind_group, &.{mem.offset});
                    // index count is 6 because we have 6 indices = 2 triangles
                    // pass.drawIndexed(6, 1, 0, 0, 0);
                    pass.draw(3, 1, 0, 0);
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
