#include "res://shaders/includes/character_motion.gdshaderinc"
uniform vec3 body_motion_lean = vec3(0.0);
uniform vec3 body_motion_pivot = vec3(0.0);
uniform bool body_mask_enabled = false;
uniform float body_mask_margin_pixels = 1.0;
uniform sampler2D body_texture : filter_nearest, repeat_disable;
uniform mat4 body_transform;
uniform int body_billboard_mode = 2;
uniform vec3 body_origin;
uniform vec3 body_edge_u;
uniform vec3 body_edge_v;
uniform vec2 body_uv_origin;
uniform vec2 body_uv_u;
uniform vec2 body_uv_v;
varying flat vec3 body_view_origin;
varying flat vec3 body_view_u;
varying flat vec3 body_view_v;

mat4 facing_card(mat4 model, int mode, mat4 camera) {
	if (mode != 0) {
		vec3 right = normalize(camera[0].xyz);
		vec3 up = normalize(camera[1].xyz);
		if (mode == 2) {
			right = normalize(vec3(right.x, 0.0, right.z));
			up = vec3(0.0, 1.0, 0.0);
		}
		vec3 facing = normalize(cross(right, up));
		return mat4(vec4(right * length(model[0].xyz), 0.0),
			vec4(up * length(model[1].xyz), 0.0),
			vec4(facing * length(model[2].xyz), 0.0), model[3]);
	}
	return model;
}

float body_alpha(vec2 local_uv) {
	if (any(lessThan(local_uv, vec2(0.0))) || any(greaterThan(local_uv, vec2(1.0)))) { return 0.0; }
	return texture(body_texture, body_uv_origin + local_uv.x * body_uv_u + local_uv.y * body_uv_v).a;
}

float body_coverage(vec3 view_position, bool orthographic) {
	vec3 ray_origin = vec3(0.0);
	vec3 ray_direction = view_position;
	if (orthographic) {
		ray_origin = vec3(view_position.xy, 0.0);
		ray_direction = vec3(0.0, 0.0, -1.0);
	}
	vec3 normal = cross(body_view_u, body_view_v);
	float denominator = dot(ray_direction, normal);
	if (abs(denominator) < 0.0000001) { return 0.0; }
	float distance = dot(body_view_origin - ray_origin, normal) / denominator;
	if (distance <= 0.0) { return 0.0; }
	vec3 offset = ray_origin + ray_direction * distance - body_view_origin;
	float uu = dot(body_view_u, body_view_u);
	float vv = dot(body_view_v, body_view_v);
	float uv = dot(body_view_u, body_view_v);
	float determinant = uu * vv - uv * uv;
	if (determinant < 0.000000001) { return 0.0; }
	vec2 projected = vec2(dot(offset, body_view_u) * vv - dot(offset, body_view_v) * uv,
		dot(offset, body_view_v) * uu - dot(offset, body_view_u) * uv) / determinant;
	// Preserve native subject pixels plus the configured outline clearance.
	vec2 size = vec2(textureSize(body_texture, 0));
	vec2 pixel = body_mask_margin_pixels / max(vec2(length(body_uv_u * size), length(body_uv_v * size)), vec2(1.0));
	if (any(lessThan(projected, -pixel)) || any(greaterThan(projected, vec2(1.0) + pixel))) { return 0.0; }
	float covered = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			covered = max(covered, body_alpha(projected + vec2(float(x), float(y)) * pixel));
		}
	}
	return step(0.01, covered);
}

