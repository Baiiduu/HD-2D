shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
#include "res://shaders/includes/player_body_mask.gdshaderinc"

uniform sampler2D airflow_texture : source_color, filter_nearest, repeat_disable;
uniform float phase = 0.0;
uniform float charge = 0.0;
uniform bool funnel_enabled = false;
uniform float radius = 1.3;
uniform float bottom_radius = 0.096;
uniform float height = 1.2;
uniform float width = 0.25;
uniform float turns = 2.25;
uniform float trail_span = 0.14;
uniform float opacity = 0.7;
varying float visibility;

vec3 spiral(float travel, float seed, vec2 layer) {
	if (funnel_enabled) {
		// Shared helix: all wisps follow the same widening cone from shoes upward.
		float t = clamp(travel, 0.0, 1.0);
		float angle = (t * turns + layer.x) * 6.283185;
		float r = mix(bottom_radius, radius, t) * layer.y;
		return vec3(cos(angle) * r, height * t, sin(angle) * r);
	}
	float angle = seed * 6.283185 + travel * 7.853982;
	float r = mix(radius * mix(1.0, 0.78, charge), radius * 0.20, travel);
	return vec3(cos(angle) * r, height * (0.08 + travel * 0.72), sin(angle) * r);
}

void vertex() {
	float seed = INSTANCE_CUSTOM.x;
	vec2 layer = INSTANCE_CUSTOM.yz;
	float life = fract(phase + seed + (funnel_enabled ? layer.x * 0.37 : 0.0));
	float travel = max(0.0, life - (1.0 - UV.x) * (funnel_enabled ? trail_span : 0.19));
	vec3 center = spiral(travel, seed, layer);
	vec3 tangent = spiral(travel + 0.002, seed, layer) - (funnel_enabled ? spiral(travel - 0.002, seed, layer) : center);
	vec3 view_tangent = (MODELVIEW_MATRIX * vec4(tangent, 0.0)).xyz;
	vec3 view_across = vec3(-view_tangent.y, view_tangent.x, 0.0);
	vec3 across = transpose(mat3(MODELVIEW_MATRIX)) * view_across / max(length(view_across), 0.00001);
	VERTEX = center + across * VERTEX.y * width;
	visibility = smoothstep(0.0, 0.16, life) * (1.0 - smoothstep(0.78, 1.0, life));
	if (funnel_enabled) visibility *= smoothstep(0.0, 0.04, travel) * INSTANCE_CUSTOM.a;
	if (body_mask_enabled) {
		mat4 body_view = VIEW_MATRIX * character_motion_card(facing_card(body_transform, body_billboard_mode, MAIN_CAM_INV_VIEW_MATRIX), body_motion_pivot, body_motion_lean);
		body_view_origin = (body_view * vec4(body_origin, 1.0)).xyz;
		body_view_u = (body_view * vec4(body_edge_u, 0.0)).xyz;
		body_view_v = (body_view * vec4(body_edge_v, 0.0)).xyz;
	}
}

void fragment() {
	vec4 ink = texture(airflow_texture, UV);
	if (funnel_enabled) {
		float luminance = dot(ink.rgb, vec3(0.2126, 0.7152, 0.0722));
		ALBEDO = vec3(0.94, 0.97, 1.0) * luminance;
	} else {
		ALBEDO = mix(ink.rgb, vec3(1.0, 0.92, 0.74), 0.20);
	}
	EMISSION = ALBEDO * (funnel_enabled ? 0.08 : 0.3);
	ALPHA = ink.a * opacity * visibility * mix(0.30, 1.0, charge);
	if (body_mask_enabled && ALPHA > 0.0) { ALPHA *= 1.0 - body_coverage(VERTEX, PROJECTION_MATRIX[3][3] > 0.5); }
}
