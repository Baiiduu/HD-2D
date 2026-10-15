shader_type spatial;
render_mode cull_disabled, specular_disabled;
#include "res://shaders/visual/atmosphere_common.gdshaderinc"
uniform vec3 box_size = vec3(3.0, 3.0, 2.0);
varying float leaf_seed;

void vertex() {
	leaf_seed = INSTANCE_CUSTOM.r;
	float speed = mix(0.4, 0.7, INSTANCE_CUSTOM.g);
	float life = box_size.y / speed;
	float age = mod(atmosphere_clock + INSTANCE_CUSTOM.b * life, life);
	vec3 center = MODEL_MATRIX[3].xyz + vec3((leaf_seed - 0.5) * box_size.x, box_size.y * 0.5 - age * speed, (INSTANCE_CUSTOM.a - 0.5) * box_size.z);
	center.xz += atmosphere_wind * age * 0.1 + vec2(sin(age * 1.7 + leaf_seed * TAU), cos(age * 1.3 + leaf_seed * TAU)) * 0.22;
	float angle = age * 1.4 + leaf_seed * TAU;
	float size = 0.15;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(INV_VIEW_MATRIX[0].xyz * size, 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz * size, 0.0), vec4(INV_VIEW_MATRIX[2].xyz, 0.0), vec4(center, 1.0));
	VERTEX.xy = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * VERTEX.xy;
	VERTEX.x *= max(abs(cos(age * 2.0)), 0.25);
}

void fragment() {
	vec2 p = (floor(UV * 12.0) + 0.5) / 12.0 - 0.5;
	float shape = length(vec2(p.x * 1.7, p.y + p.x * 0.3));
	ALPHA = step(shape, 0.42);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = mix(vec3(0.25, 0.38, 0.11), vec3(0.52, 0.31, 0.10), leaf_seed);
	ROUGHNESS = 1.0;
}
