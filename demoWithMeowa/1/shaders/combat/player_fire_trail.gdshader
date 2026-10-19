shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// Opaque pixel cutouts retain real depth, without transparent rectangles or overlays.
// A single shared clock is advanced by the owner, never TIME: upgrades freeze all phases.
uniform float effect_clock = 0.0;
uniform float fresh_seconds = 0.18;
uniform float burn_seconds = 0.65;
uniform float ember_seconds = 1.35;
uniform float energy = 1.1;
uniform float pixels_per_meter = 40.0;
varying vec3 world_point;
varying flat vec4 piece; // birth, traversal seconds, centerline length, width

#include "res://shaders/combat/ground_fire_surface.gdshaderinc"

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	piece = INSTANCE_CUSTOM;
}

void fragment() {
	float along = (UV.x - 0.5) * (piece.z + piece.w);
	float fraction = clamp(along / max(piece.z, 0.00001) + 0.5, 0.0, 1.0);
	float age = max(0.0, effect_clock - piece.x - fraction * piece.y);
	float across = (UV.y - 0.5) * piece.w;
	GroundFireSurface surface = ground_fire_surface(world_point.xz, vec2(along, across),
		piece.z, piece.w, age, effect_clock, vec3(fresh_seconds, burn_seconds, ember_seconds), energy, pixels_per_meter);
	if (surface.coverage < 0.5) discard;
	ALBEDO = surface.albedo;
	EMISSION = surface.emission;
	ROUGHNESS = 1.0;
}
