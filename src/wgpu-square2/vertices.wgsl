@group(0) @binding(0) var<uniform> object_to_clip: mat4x4<f32>;

struct VertexOut {
    @builtin(position) position_clip: vec4<f32>,
    @location(0) color: vec3<f32>,
}

@vertex 
fn main(
    @location(0) position: vec3<f32>,
    @builtin(vertex_index) VertexIndex: u32,
    @location(1) color: vec3<f32>,
) -> VertexOut {
    var output: VertexOut;

    var pos = array<vec3<f32>, 5>(
        vec3<f32>(-0.5, -0.5, 0.0),
        vec3<f32>(0.5, -0.5, 0.0),
        vec3<f32>(0.5, 0.5, 0.0),
        vec3<f32>(-0.5, 0.5, 0.0),
        vec3<f32>(-0.5, -0.5, 0.0),
    );
    output.position_clip = vec4(pos[VertexIndex], 1.0) * object_to_clip;
    output.color = vec3<f32>(0.5, 0.5, 0.5);
    return output;
}
