shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;
#include "res://shaders/visual/atmosphere_common.gdshaderinc"
uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform float wind_amount = 0.045;
instance uniform vec3 plant_root = vec3(0.0);
instance uniform float plant_height = 3.0;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = dot(plant_root.xz, vec2(0.71, 1.27));
	vec3 bend = atmosphere_bend(world, plant_root, plant_height, phase, wind_amount * plant_height);
	VERTEX += (inverse(MODEL_MATRIX) * vec4(bend, 0.0)).xyz;
}

void fragment() {
	vec4 color = texture(atlas, UV);
	// Some city cards use a magenta cutout key in their native atlas instead of PNG alpha.
	// Discard it in both color and shadow passes without rewriting or resampling the art.
	float key = min(color.r, color.b) - color.g;
	if ((min(color.r, color.b) > 0.6 && color.g < 0.15)
		|| (key > 0.2 && color.g < 0.4 && abs(color.r - color.b) < 0.18)) discard;
	ALBEDO = color.rgb;
	ALPHA = color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
}
