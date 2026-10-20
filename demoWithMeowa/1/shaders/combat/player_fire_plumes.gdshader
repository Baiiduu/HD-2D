shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
#include "res://shaders/includes/player_body_mask.gdshaderinc"
#include "res://shaders/combat/ground_fire_surface.gdshaderinc"

uniform float effect_clock = 0.0;
uniform float energy = 1.1;
uniform float spark_amount = 0.2;
uniform float pixels_per_meter = 40.0;
uniform vec3 subject_position;
varying flat vec4 flame_data;
varying flat float card;
varying flat vec2 flame_size;
varying vec3 world_point;

void vertex() {
	flame_data = INSTANCE_CUSTOM;
	card = UV2.x;
	flame_size = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz));
	float age = max(0.0, effect_clock - flame_data.x);
	float progress = clamp(age / max(flame_data.y, 0.001), 0.0, 1.0);
	float clock = floor(effect_clock * 18.0) / 18.0;
	float seed = flame_data.z * 17.0;
	if (flame_size.x < 0.00001) {
		// 池内闲置实例使用零矩阵；避免飞火分支对零矩阵求逆。
		VERTEX = vec3(0.0);
	} else if (card < 1.5) {
		float v = UV.y;
		float swell = smoothstep(0.0, 0.06, age) * (1.0 - smoothstep(0.55, 1.0, progress));
		float flicker = 0.88 + 0.12 * sin(clock * 8.0 + seed);
		vec3 center = vec3(sin(v * 3.2 - clock * 5.0 + seed) * v * 0.16,
			v * (1.0 - smoothstep(0.55, 1.0, v) * 0.28) * flicker,
			-pow(v, 1.4) * (0.58 + sin(clock * 4.0 + seed) * 0.12));
		float angle = card * 1.570796;
		vec3 across = vec3(cos(angle), 0.0, sin(angle));
		VERTEX = (center + across * (UV.x - 0.5) * (1.0 - v * 0.65)) * swell;
	} else {
		float flying = clamp((age - 0.08 - flame_data.z * 0.1) / max(flame_data.y * 0.65, 0.01), 0.0, 1.0);
		float side = sin(seed * 2.7 + card * 3.0);
		vec3 center = vec3(side * flying * 0.5, 0.12 + flying * 1.1 - flying * flying * 0.35, -0.15 - flying * 0.9);
		vec3 world_center = (MODEL_MATRIX * vec4(center, 1.0)).xyz;
		float size = (1.0 + step(0.5, flame_data.z)) / pixels_per_meter;
		vec3 corner = (MAIN_CAM_INV_VIEW_MATRIX[0].xyz * (UV.x - 0.5)
			+ MAIN_CAM_INV_VIEW_MATRIX[1].xyz * (UV.y - 0.5) * 1.6) * size;
		VERTEX = (inverse(MODEL_MATRIX) * vec4(world_center + corner, 1.0)).xyz;
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
	float age = effect_clock - flame_data.x;
	float life = max(flame_data.y, 0.001);
	if (age < 0.0 || age >= life) { discard; }
	// 留出人物脚边空间，再按真实帧投影剔除前景火舌与飞火。
	if (distance(world_point.xz, subject_position.xz) < 0.30) { discard; }
	if (body_mask_enabled && body_coverage(VERTEX, PROJECTION_MATRIX[3][3] > 0.5) > 0.0) { discard; }
	float progress = age / life;
	vec3 tint;
	float core;
	if (card < 1.5) {
		vec2 cells = max(flame_size * pixels_per_meter, vec2(1.0));
		vec2 p = (floor(UV * cells) + 0.5) / cells;
		float clock = floor(effect_clock * 18.0) / 18.0;
		float seed = flame_data.z * 17.0 + card * 0.7;
		float flow = fire_noise(vec2(p.x * 4.5 + seed, p.y * 3.8 - clock * 4.0));
		float bend = sin(p.y * 6.0 - clock * 5.0 + seed) * p.y * 0.12;
		float width = mix(0.48, 0.08, pow(p.y, 0.9));
		float trunk = 1.0 - abs(p.x - 0.5 - bend) / max(width, 0.001);
		float split = smoothstep(0.25, 0.65, p.y);
		float fork = 1.0 - abs(abs(p.x - 0.5 - bend) - split * 0.19) / 0.095;
		float shape = max(trunk, fork * split * 0.85) + (flow - 0.5) * 0.65;
		float erosion = smoothstep(0.6, 1.0, progress);
		if (shape < 0.28 + erosion * 0.5 || p.y > 0.78 + flow * 0.22) { discard; }
		core = clamp(shape * (1.0 - p.y) * (1.0 - progress * 0.65), 0.0, 1.0);
		tint = mix(vec3(0.87, 0.045, 0.006), vec3(1.0, 0.36, 0.025), smoothstep(0.2, 0.65, core));
		tint = mix(tint, vec3(1.0, 0.76, 0.18), smoothstep(0.62, 0.9, core));
	} else {
		float seed = fire_hash(vec2(flame_data.z * 31.0, card));
		float flying = (age - 0.08 - flame_data.z * 0.1) / max(life * 0.65, 0.01);
		if (seed >= spark_amount || flying <= 0.0 || flying >= 1.0) { discard; }
		if (abs(UV.x - 0.5) + abs(UV.y - 0.5) > 0.65 - flying * 0.2) { discard; }
		core = 1.0 - flying;
		tint = mix(vec3(0.95, 0.12, 0.01), vec3(1.0, 0.78, 0.22), core);
	}
	ALBEDO = tint * 0.65;
	EMISSION = tint * energy * (0.55 + core * 0.9) * (1.0 - progress * 0.35);
	ROUGHNESS = 1.0;
}
