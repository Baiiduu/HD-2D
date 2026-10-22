shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
#include "res://shaders/includes/player_body_mask.gdshaderinc"
#include "res://shaders/combat/ground_fire_surface.gdshaderinc"
#include "res://shaders/combat/fire_flow_pattern.gdshaderinc"

uniform float effect_clock = 0.0;
uniform float energy = 1.1;
uniform float spark_amount = 0.2;
uniform float pixels_per_meter = 40.0;
uniform vec3 subject_position;
varying flat vec4 spark_data;
varying vec3 world_point;

float spark_hash(float value) {
	return fract(sin(value * 127.1 + 311.7) * 43758.5453);
}

void vertex() {
	spark_data = INSTANCE_CUSTOM;
	float age = effect_clock - spark_data.x - 0.035;
	float life = max(spark_data.y - 0.035, 0.001);
	float choice = spark_hash(spark_data.z * 31.0 + 3.0);
	float width = length(MODEL_MATRIX[0].xyz);
	if (width < 0.00001 || age < 0.0 || age >= life || choice >= spark_amount) {
		VERTEX = vec3(0.0);
	} else {
		vec2 origin = MODEL_MATRIX[3].xz;
		vec2 forward = normalize(MODEL_MATRIX[2].xz);
		float launch_clock = spark_data.x + 0.035;
		vec3 before = fire_flow_pattern(origin, forward, spark_data.w, 0.0, spark_data.x);
		vec3 after = fire_flow_pattern(origin, forward, spark_data.w, 0.0, launch_clock);
		float breaking = max(0.0, before.x - after.x);
		float flying = age / life;
		float angle = spark_hash(spark_data.z * 17.0) * 6.283185;
		float spread = flying * (0.25 + spark_hash(spark_data.z * 23.0) * 0.45);
		vec3 center = vec3(sin(angle) * spread, 0.10 + flying * 2.8 - flying * flying * 2.6, cos(angle) * spread);
		vec3 world_center = (MODEL_MATRIX * vec4(center, 1.0)).xyz;
		float size = (1.0 + step(0.55, choice / max(spark_amount, 0.001))) / pixels_per_meter;
		vec3 corner = (MAIN_CAM_INV_VIEW_MATRIX[0].xyz * (UV.x - 0.5)
			+ MAIN_CAM_INV_VIEW_MATRIX[1].xyz * (UV.y - 0.5)) * size;
		VERTEX = (inverse(MODEL_MATRIX) * vec4(world_center + corner, 1.0)).xyz;
		if (max(before.x, after.x) < 0.15 || (after.y < 0.1 && breaking < 0.18)) { VERTEX = vec3(0.0); }
	}
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (body_mask_enabled) {
		mat4 body_view = VIEW_MATRIX * character_motion_card(facing_card(body_transform, body_billboard_mode, MAIN_CAM_INV_VIEW_MATRIX), body_motion_pivot, body_motion_lean);
		body_view_origin = (body_view * vec4(body_origin, 1.0)).xyz;
		body_view_u = (body_view * vec4(body_edge_u, 0.0)).xyz;
		body_view_v = (body_view * vec4(body_edge_v, 0.0)).xyz;
	}
}

void fragment() {
	float age = effect_clock - spark_data.x - 0.035;
	float life = max(spark_data.y - 0.035, 0.001);
	if (age < 0.0 || age >= life) { discard; }
	if (distance(world_point.xz, subject_position.xz) < 0.30) { discard; }
	if (body_mask_enabled && body_coverage(VERTEX, PROJECTION_MATRIX[3][3] > 0.5) > 0.0) { discard; }
	float progress = age / life;
	if (abs(UV.x - 0.5) + abs(UV.y - 0.5) > 0.65 - progress * 0.2) { discard; }
	float core = (1.0 - progress) * (0.8 + spark_hash(spark_data.z * 29.0) * 0.2);
	vec3 tint = mix(vec3(0.95, 0.10, 0.01), vec3(1.0, 0.76, 0.20), core);
	ALBEDO = tint * 0.65;
	EMISSION = tint * energy * (0.4 + core * 0.9);
	ROUGHNESS = 1.0;
}
