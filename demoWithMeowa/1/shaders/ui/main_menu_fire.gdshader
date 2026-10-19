shader_type canvas_item;
render_mode unshaded;

uniform float effect_clock = 0.0;
uniform float birth = 0.0;
uniform float traversal_seconds = 0.0;
uniform float segment_length = 1.0;
uniform float width = 0.36;
uniform float fresh_seconds = 0.18;
uniform float burn_seconds = 0.65;
uniform float ember_seconds = 1.35;
uniform float energy = 1.1;
uniform float pixels_per_meter = 40.0;
uniform float strength = 1.0;
uniform vec2 ground_projection = vec2(60.0, 30.0);
varying vec2 menu_ground_point;

#include "res://shaders/combat/ground_fire_surface.gdshaderinc"

void vertex() {
	menu_ground_point = VERTEX / ground_projection;
}

void fragment() {
	float along = (UV.x - 0.5) * (segment_length + width);
	float fraction = clamp(along / max(segment_length, 0.00001) + 0.5, 0.0, 1.0);
	float age = effect_clock - birth - fraction * traversal_seconds;
	// Menu ribbons are cached in full: hide the ground the hero has not reached yet.
	if (age < 0.0) discard;
	float across = (UV.y - 0.5) * width;
	GroundFireSurface surface = ground_fire_surface(menu_ground_point, vec2(along, across),
		segment_length, width, age, effect_clock, vec3(fresh_seconds, burn_seconds, ember_seconds), energy, pixels_per_meter);
	if (surface.coverage < 0.5) discard;
	// The 2D illustration has no 3D exposure pass. Compress emitted light locally,
	// retaining the shared orange/yellow palette and dark-coal contrast.
	vec3 lit = surface.albedo + surface.emission * 0.55;
	COLOR = vec4(lit / (vec3(1.0) + lit * 0.45), strength);
}
