shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
#include "res://shaders/includes/player_body_mask.gdshaderinc"

uniform sampler2D scene_color : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D flow_noise : filter_linear_mipmap, repeat_enable;
uniform float flow_phase = 0.0;
uniform float flow_amount = 0.0;
uniform float opacity = 0.55;
uniform float flow_radius = 0.42;
uniform float flow_length = 1.4;
uniform float distortion_pixels = 0.9;
varying vec3 air_normal_view;

void vertex() {
	float v = clamp(UV.y, 0.005, 0.995);
	float a = UV.x * 6.283185;
	float s = max(sin(v * 3.141593), 0.001);
	float base = pow(s, 0.65);
	float profile = base * (1.0 - v * 0.18);
	float derivative = 0.65 * 3.141593 * cos(v * 3.141593) * pow(s, -0.35) * (1.0 - v * 0.18) - base * 0.18;
	float ripple = textureLod(flow_noise, vec2(UV.x * 3.0, v - flow_phase * 0.45), 0.0).r - 0.5;
	float r = flow_radius * profile * (1.0 + ripple * 0.07);
	VERTEX = vec3(cos(a) * r, sin(a) * r * 1.5, flow_length * (0.24 - v));
	NORMAL = normalize(vec3(cos(a) / max(flow_radius, 0.01), sin(a) / max(flow_radius * 1.5, 0.01), derivative / max(flow_length, 0.01)));
	air_normal_view = MODELVIEW_NORMAL_MATRIX * NORMAL;
	if (body_mask_enabled) {
		mat4 body_view = VIEW_MATRIX * character_motion_card(facing_card(body_transform, body_billboard_mode, MAIN_CAM_INV_VIEW_MATRIX), body_motion_pivot, body_motion_lean);
		body_view_origin = (body_view * vec4(body_origin, 1.0)).xyz;
		body_view_u = (body_view * vec4(body_edge_u, 0.0)).xyz;
		body_view_v = (body_view * vec4(body_edge_v, 0.0)).xyz;
	}
}

void fragment() {
	float facing = dot(normalize(air_normal_view), normalize(VIEW));
	if (facing <= 0.0 || flow_amount <= 0.0) { discard; }
	float body_clear = body_mask_enabled ? 1.0 - body_coverage(VERTEX, PROJECTION_MATRIX[3][3] > 0.5) : 1.0;
	if (body_clear <= 0.0) { discard; }
	vec2 flow_uv = vec2(UV.x * 3.0, UV.y * 0.7 - flow_phase);
	float warp = texture(flow_noise, flow_uv * vec2(1.0, 0.65) + vec2(0.21, 0.37)).r;
	float n = texture(flow_noise, flow_uv + vec2(warp * 0.14, warp * 0.05)).r;
	float cross_noise = texture(flow_noise, flow_uv * vec2(2.0, 1.1) + vec2(0.37, 0.19)).r;
	float shear = 1.0 - smoothstep(0.04, 0.18, abs(n - 0.52));
	shear *= smoothstep(0.25, 0.65, cross_noise);
	float rim = pow(1.0 - facing, 1.7);
	float ends = smoothstep(0.025, 0.16, UV.y) * (1.0 - smoothstep(0.6, 0.99, UV.y));
	float density = smoothstep(0.32, 0.7, n);
	float visibility = ends * body_clear * flow_amount;
	vec2 distortion = (vec2(n, cross_noise) - 0.5) * min(distortion_pixels, 1.5) / VIEWPORT_SIZE;
	vec3 background = textureLod(scene_color, clamp(SCREEN_UV + distortion * visibility, vec2(0.0), vec2(1.0)), 0.0).rgb;
	float highlight = shear * (0.2 + rim * 0.8);
	vec3 air_color = vec3(0.88, 0.95, 1.0);
	ALBEDO = mix(background, air_color, highlight * 0.35);
	EMISSION = air_color * highlight * 0.08;
	ALPHA = opacity * visibility * (density * 0.10 + highlight * 0.62);
}
