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
	view_pos: vec4<f32>,
	proj_view: mat4x4<f32>,
	inv_proj: mat4x4<f32>,
};

struct Offset {
	x: f32,
	y: f32
}

@group(0) @binding(0)
var<uniform> un: Uniform;
@group(1) @binding(0)
var<uniform> cam: Camera;
@group(2) @binding(0)
var volume: texture_storage_3d<rgba16float, read>;
@group(2) @binding(1)
var volume_normal: texture_storage_3d<rgba16float, read>;
@group(3) @binding(0)
var out_tex: texture_storage_2d<rgba16float, write>;
@group(4) @binding(0)
var<storage> dyn_offset: Offset;

var<private> tmin: f32 = 0.;
var<private> tmax: f32 = 0.;

let NUM_STEPS: i32 = 100;
let MIN_DIST: f32 = 0.0;
let MAX_DIST: f32 = 5.0;

fn intersect_box(orig: vec3<f32>, dir: vec3<f32>) -> vec2<f32> {
    let box_min = vec3(-1.0);
    let box_max = vec3(1.0);
    let inv_dir = 1.0 / dir;
    let tmin_tmp = (box_min - orig) * inv_dir;
    let tmax_tmp = (box_max - orig) * inv_dir;
    let tmin = min(tmin_tmp, tmax_tmp);
    let tmax = max(tmin_tmp, tmax_tmp);
    let t0 = max(tmin.x, max(tmin.y, tmin.z));
    let t1 = min(tmax.x, min(tmax.y, tmax.z));
    return vec2<f32>(t0, t1);
}

fn get_cam(eye: vec3<f32>, tar: vec3<f32>) -> mat3x3<f32> {
    let zaxis = normalize(tar - eye);
    let xaxis = normalize(cross(zaxis, vec3(0., 1., 0.)));
    let yaxis = cross(xaxis, zaxis);
    return mat3x3(xaxis, yaxis, zaxis);
}

fn get_col2(eye: vec3<f32>, dir: vec3<f32>, tmin: f32, tmax: f32, clear_color: vec4<f32>) -> vec4<f32> {
    var color = vec4(clear_color.rgb, 0.1);
    let light = vec3(0., -1., 0.);
    let block_size = vec3<f32>(textureDimensions(volume));
    let dt_vec = 1.0 / (block_size * abs(dir));
    let dt_scale = 1.0;
    let dt = dt_scale * max(min(dt_vec.x, min(dt_vec.y, dt_vec.z)), 0.01);
    for (var t = tmin; t < tmax; t = t + dt) {
        var p = eye + t * dir;
        let samp = vec3<i32>((p + 1.) * (block_size / 2.));
        let vol_content = textureLoad(volume, samp);
        let normal = textureLoad(volume_normal, samp);
        var shade = vec3(max(0., dot(light, normal.rgb)));

        var vol_color = vol_content.rgb;

        var vol_alpha = pow(vol_content.a, 3.0);
        vol_alpha = smoothstep(0.0, 0.7, vol_alpha);

        var directional = 3.0 * vec3(1., .1, .13) * max(dot(normal.xyz, normalize(vec3(-2., -2., -1.))), .0);
        directional *= smoothstep(.3, 1.5, dot(p, normalize(vec3(1., 1., -1.))));
        vol_color += directional;

        let bottom_light = 0.9 * clamp(0.5 - 0.5 * normal.y, 0., 1.);
        shade = mix(shade, bottom_light * vec3(0., 0., 0.6), 0.2);

        let tmp = color.rgb + (1.0 - color.a) * vol_alpha * vol_color * shade;
        let tmp = tmp + clear_color.rgb * clear_color.a * (1.0 - vol_alpha);
        color = vec4(tmp, color.a);
        color.a = color.a + (1.0 - color.a) * vol_alpha * (1. - clear_color.a);
        if (color.a >= 0.95) {
			break;
        }
    }
    return color;
}

fn render(global_id: vec2<u32>, offset_x: f32, offset_y: f32) -> vec4<f32> {
    let time = un.time * 0.5;

    let coord = vec2<f32>(global_id) + vec2(offset_x, offset_y);
    let dims = vec2<f32>(textureDimensions(out_tex));
    let aspect_ratio = dims.y / dims.x;

    var screen_coord = 2. * vec2(coord.x, coord.y) / dims - 1.;
    screen_coord.y *= -aspect_ratio;

    let screen_point = vec4(screen_coord, 0., 1.);
    let screen_tangent = screen_point + vec4(0., 0., 1., 0.);

    var view_pos = cam.inv_proj * screen_point;
    var view_tang = cam.inv_proj * screen_tangent;

    let eye = view_pos.xyz / view_pos.w;
    let dir = normalize(view_tang.xyz / view_tang.w - eye);

    let clear_color = vec4<f32>(0.023, 0.02, 0.02, 0.0);

    var color = vec4(0.);
    if (any(vec2<f32>(global_id.xy) < dims)) {
        var t_hit = intersect_box(eye, dir);
        if (t_hit.x < t_hit.y) {
            t_hit.x = max(t_hit.x, 0.0);
            color = vec4(get_col2(eye, dir, t_hit.x, t_hit.y, clear_color).rgb, 1.);
        } else {
            color = vec4(clear_color.rgb, 1.);
        }
    }
    return color;
}

@compute @workgroup_size(8, 8, 1)
fn single(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let color = render(global_id.xy, 0., 0.);
    textureStore(out_tex, global_id.xy, color);
}

@compute @workgroup_size(16, 16, 1)
fn tile(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let color = render(global_id.xy, dyn_offset.x, dyn_offset.y);
    let offset = vec2<u32>(vec2(dyn_offset.x, dyn_offset.y));
    textureStore(out_tex, global_id.xy + offset, color);
}
