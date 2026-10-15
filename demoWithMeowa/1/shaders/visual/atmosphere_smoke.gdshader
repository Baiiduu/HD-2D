shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled;
#include "res://shaders/visual/atmosphere_common.gdshaderinc"
uniform float opacity = 0.2;
uniform float particle_life = 5.0;
uniform float rise_speed = 0.8;
uniform float initial_size = 0.38;
uniform float expansion = 3.4;
uniform float wind_influence = 0.22;
uniform vec4 smoke_color : source_color = vec4(0.70, 0.67, 0.65, 1.0);
varying float particle_age;
varying float particle_seed;

void vertex() {
	particle_seed = INSTANCE_CUSTOM.r * 37.0;
	float life = particle_life * mix(0.8, 1.2, INSTANCE_CUSTOM.g);
	float age = mod(atmosphere_clock + INSTANCE_CUSTOM.b * life, life);
	particle_age = age / life;
	float drag = 0.3;
	float displacement = (1.0 - exp(-drag * age)) / drag;
	vec3 center = MODEL_MATRIX[3].xyz;
	center += vec3(atmosphere_wind.x, 0.06, atmosphere_wind.y) * wind_influence * (age - displacement) / drag;
	center.y += rise_speed * displacement;
	center.xz += vec2(sin(age * 1.2 + particle_seed), cos(age * 1.5 + particle_seed)) * 0.25 * particle_age;
	float size = initial_size * mix(1.0, expansion, particle_age);
	float angle = particle_seed + age * mix(0.1, 0.4, INSTANCE_CUSTOM.a);
	vec2 corner = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * VERTEX.xy;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(INV_VIEW_MATRIX[0].xyz * size, 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz * size, 0.0), vec4(INV_VIEW_MATRIX[2].xyz, 0.0), vec4(center, 1.0));
	VERTEX = vec3(corner, 0.0);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float noise = atmosphere_noise(p * 3.1 + vec2(particle_seed, particle_seed * 0.4));
	float density = 1.0 - smoothstep(0.28, 0.92, length(p) + (noise - 0.5) * 0.45);
	float envelope = smoothstep(0.0, 0.12, particle_age) * (1.0 - smoothstep(0.45, 1.0, particle_age));
	float shade = 0.82 + (1.0 - UV.y) * 0.16 + noise * 0.08;
	ALBEDO = mix(smoke_color.rgb, vec3(0.48, 0.49, 0.55), particle_age) * shade;
	ROUGHNESS = 1.0;
	ALPHA = density * opacity * envelope;
}
