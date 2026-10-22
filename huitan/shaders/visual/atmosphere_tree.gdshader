shader_type spatial;
render_mode diffuse_lambert_wrap, specular_disabled;
#include "res://shaders/visual/atmosphere_common.gdshaderinc"
uniform vec4 surface_color : source_color = vec4(0.19, 0.3, 0.2, 1.0);
uniform float flexibility = 0.10;
instance uniform vec3 plant_root = vec3(0.0);
instance uniform float plant_height = 3.5;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float phase = dot(plant_root.xz, vec2(0.71, 1.27));
	vec3 bend = atmosphere_bend(world, plant_root, plant_height, phase, flexibility);
	VERTEX += (inverse(MODEL_MATRIX) * vec4(bend, 0.0)).xyz;
}

void fragment() {
	ALBEDO = surface_color.rgb;
	ROUGHNESS = 1.0;
}
