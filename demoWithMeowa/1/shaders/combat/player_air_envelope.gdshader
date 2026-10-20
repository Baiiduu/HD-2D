shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
#include "res://shaders/includes/player_body_mask.gdshaderinc"

uniform sampler2D flow_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D flow_brush : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 brush_region = vec4(0.0208333, 0.4074074, 0.9583333, 0.1481481);
uniform float flow_phase = 0.0;
uniform float flow_amount = 0.0;
uniform float opacity = 0.55;
uniform float flow_radius = 0.42;
uniform float flow_length = 1.4;

vec3 wind_center(float t, float side) {
	float bow = sin(clamp(t, 0.0, 1.0) * 3.141593);
	float bend = sin(t * 3.0 - flow_phase * 0.8 + side) * 0.12;
	return vec3(side * flow_radius * (0.6 + bow * 0.45), flow_radius * (side * 0.10 + bend * bow), flow_length * (0.18 - t));
}

void vertex() {
	vec3 center = wind_center(UV.x, UV2.x);
	vec3 tangent = wind_center(UV.x + 0.002, UV2.x) - wind_center(UV.x - 0.002, UV2.x);
	vec3 view_tangent = (MODELVIEW_MATRIX * vec4(tangent, 0.0)).xyz;
	vec3 view_across = vec3(-view_tangent.y, view_tangent.x, 0.0);
	vec3 across = transpose(mat3(MODELVIEW_MATRIX)) * view_across / max(length(view_across), 0.00001);
	VERTEX = center + across * (UV.y - 0.5) * flow_radius * 0.75;
	if (body_mask_enabled) {
		mat4 body_view = VIEW_MATRIX * character_motion_card(facing_card(body_transform, body_billboard_mode, MAIN_CAM_INV_VIEW_MATRIX), body_motion_pivot, body_motion_lean);
		body_view_origin = (body_view * vec4(body_origin, 1.0)).xyz;
		body_view_u = (body_view * vec4(body_edge_u, 0.0)).xyz;
		body_view_v = (body_view * vec4(body_edge_v, 0.0)).xyz;
	}
}

void fragment() {
	if (flow_amount <= 0.0) { discard; }
	float seed = UV2.x * 0.23;
	float travel = fract(UV.x - flow_phase * 0.9 + seed);
	float n = texture(flow_noise, vec2(UV.x * 0.8 - flow_phase * 0.35, UV.y * 3.0 + seed)).r;
	vec2 brush_uv = vec2(travel, clamp(UV.y + (n - 0.5) * 0.06, 0.0, 1.0));
	vec3 ink = texture(flow_brush, brush_region.xy + brush_uv * brush_region.zw).rgb;
	float mask = smoothstep(0.015, 0.62, max(ink.r, max(ink.g, ink.b)));
	float ends = smoothstep(0.0, 0.12, UV.x) * (1.0 - smoothstep(0.6, 1.0, UV.x));
	float passing = smoothstep(0.0, 0.06, travel) * (1.0 - smoothstep(0.86, 1.0, travel));
	float feather = pow(max(sin(UV.y * 3.141593), 0.0), 0.7);
	float dissolve = smoothstep(0.14 + UV.x * 0.17, 0.52 + UV.x * 0.17, n);
	// Keep mipmapped samples above per-pixel exits; only exact zero skips the body mask.
	if (opacity == 0.0 || mask == 0.0 || ends == 0.0 || passing == 0.0 || feather == 0.0 || dissolve == 0.0) { discard; }
	float body_clear = body_mask_enabled ? 1.0 - body_coverage(VERTEX, PROJECTION_MATRIX[3][3] > 0.5) : 1.0;
	if (body_clear <= 0.0) { discard; }
	ALBEDO = vec3(0.91, 0.96, 1.0);
	EMISSION = ALBEDO * 0.06;
	ALPHA = opacity * flow_amount * body_clear * mask * ends * passing * feather * dissolve;
}
