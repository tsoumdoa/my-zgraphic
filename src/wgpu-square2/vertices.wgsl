
@group(0) @binding(0) var<uniform> object_to_clip: mat4x4<f32>;
@group(0) @binding(1) var<storage, read> randomValues: array<mat3x3<f32>>;

struct VertexOut {
    @builtin(position) position_clip: vec4<f32>,
    @location(0) color: vec3<f32>,
}

@vertex 
fn main(
    @builtin(vertex_index) VertexIndex: u32,
    @builtin(instance_index) InstanceIndex: u32,
) -> VertexOut {
    var output: VertexOut;

    var pos = array<vec3<f32>, 5>(
        vec3<f32>(-1.0, -1.0, 0.0),
        vec3<f32>(1.0, -1.0, 0.0),
        vec3<f32>(1.0, 1.0, 0.0),
        vec3<f32>(-1.0, 1.0, 0.0),
        vec3<f32>(-1.0, -1.0, 0.0),
    );

    var randomScales = randomValues[InstanceIndex][0] / 10.0;
    var offsets = randomValues[InstanceIndex][1] * 2.0;
    var color = abs(randomValues[InstanceIndex][2]);

    output.position_clip = (vec4<f32>((pos[VertexIndex]) * randomScales[0] + offsets, 1.0)) * object_to_clip ;
    output.color = color;
    return output;
}
