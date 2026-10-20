shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
#include "res://shaders/includes/player_body_mask.gdshaderinc"
#include "res://shaders/combat/ground_fire_surface.gdshaderinc"
#include "res://shaders/combat/fire_flow_pattern.gdshaderinc"

uniform float effect_clock = 0.0;
uniform float fresh_seconds = 0.18;
uniform float burn_seconds = 0.65;
uniform float ember_seconds = 1.35;
uniform float energy = 1.1;
uniform float pixels_per_meter = 40.0;
uniform vec3 subject_position;
varying vec3 world_point;
varying flat vec4 piece; // birth, traversal seconds, centerline length, width
varying flat vec2 ribbon_forward;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	piece = INSTANCE_CUSTOM;
	ribbon_forward = MODEL_MATRIX[0].xz / max(length(MODEL_MATRIX[0].xz), 0.00001);
	if (body_mask_enabled) {
		mat4 body_view = VIEW_MATRIX * character_motion_card(facing_card(body_transform, body_billboard_mode, MAIN_CAM_INV_VIEW_MATRIX), body_motion_pivot, body_motion_lean);
		body_view_origin = (body_view * vec4(body_origin, 1.0)).xyz;
		body_view_u = (body_view * vec4(body_edge_u, 0.0)).xyz;
		body_view_v = (body_view * vec4(body_edge_v, 0.0)).xyz;
	}
}

GroundFireSurface flowing_fire(GroundFireSurface base, float along, float across, float age) {
	float burning_end = fresh_seconds + burn_seconds;
	if (age >= burning_end) { return base; }
	vec2 p = world_point.xz;
	vec2 pixel = floor(p * pixels_per_meter);
	float settle = smoothstep(fresh_seconds + burn_seconds * 0.5, burning_end, age);
	if (fire_hash(pixel) < settle) { return base; }
	vec3 pattern = fire_flow_pattern(p, ribbon_forward, piece.w, across, effect_clock);
	float paint = pattern.x;
	float pulse = pattern.y;
	float tear = pattern.z;
	float cap = along - clamp(along, -piece.z * 0.5, piece.z * 0.5);
	float radius = length(vec2(cap, across)) / max(piece.w * 0.5, 0.001);
	float erosion = smoothstep(fresh_seconds * 0.5, burning_end, age);
	float threshold = 0.08 + erosion * 0.45 + tear * (0.10 + pulse * 0.16);
	GroundFireSurface surface;
	surface.coverage = step(threshold, paint) * step(radius, 0.96);
	float hot = smoothstep(0.55, 0.95, tear + pulse * 0.25) * (1.0 - erosion * 0.8);
	vec3 tint = mix(vec3(0.95, 0.075, 0.008), vec3(1.0, 0.4, 0.035), paint * 0.6);
	tint = mix(tint, vec3(1.0, 0.72, 0.16), hot);
	float short_tail = 1.0 - smoothstep(0.025, max(0.05, fresh_seconds * 0.5), age);
	surface.albedo = tint * mix(0.65, 0.4, erosion);
	surface.emission = tint * energy * (0.55 + short_tail * 0.85 + pulse * 0.35) * (1.0 - erosion * 0.45);
	return surface;
}

void fragment() {
	float along = (UV.x - 0.5) * (piece.z + piece.w);
	float fraction = clamp(along / max(piece.z, 0.00001) + 0.5, 0.0, 1.0);
	float raw_age = effect_clock - piece.x - fraction * piece.y;
	if (flow_strength > 0.0 && raw_age < 0.0) { discard; }
	float age = max(0.0, raw_age);
	float across = (UV.y - 0.5) * piece.w;
	GroundFireSurface surface = ground_fire_surface(world_point.xz, vec2(along, across),
		piece.z, piece.w, age, effect_clock, vec3(fresh_seconds, burn_seconds, ember_seconds), energy, pixels_per_meter);
	if (flow_strength > 0.0) { surface = flowing_fire(surface, along, across, age); }
	if (surface.coverage < 0.5) { discard; }
	if (body_mask_enabled && body_coverage(VERTEX, PROJECTION_MATRIX[3][3] > 0.5) > 0.0) { discard; }
	ALBEDO = surface.albedo;
	EMISSION = surface.emission;
	ROUGHNESS = 1.0;
}
