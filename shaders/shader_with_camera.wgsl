struct Uniform {
    pos: vec3<f32>,
    frame: u32,
    resolution: vec2<f32>,
    mouse: vec2<f32>,
    mouse_pressed: u32,
    time: f32,
    time_delta: f32,
};

struct Camera {
	view_pos: vec3<f32>,
	proj_view: mat4x4<f32>,
	inv_proj: mat4x4<f32>,
};

@group(0) @binding(0)
var<uniform> un: Uniform;
@group(1) @binding(0)
var<uniform> cam: Camera;

struct VertexOutput {
    @builtin(position) pos: vec4<f32>,
};

@vertex
fn vs_main(@builtin(vertex_index) vertex_idx: u32) -> VertexOutput {
    let vertex_idx = i32(vertex_idx);
    var res: vec4<f32>;
    if (vertex_idx == 0) {
        res = vec4<f32>(-0.5, -0.5, 0., 1.);
    } else if (vertex_idx == 1) {
        res = vec4<f32>(0.5, -0.5, 0., 1.);
    } else {
        res = vec4<f32>(0., 0.5, 0., 1.);
    }
    res = cam.proj_view * res;
    return VertexOutput(res);
}

@fragment
fn fs_main(vin: VertexOutput) -> @location(0) vec4<f32> {
    var t = fract(un.time);
    return vec4<f32>(t, f32(un.mouse_pressed), 1., 1.);
}
