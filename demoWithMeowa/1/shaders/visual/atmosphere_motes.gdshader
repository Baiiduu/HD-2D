shader_type spatial;
render_mode cull_disabled, unshaded, depth_draw_opaque;
#include "res://shaders/visual/atmosphere_common.gdshaderinc"
uniform vec3 box_size = vec3(12.0, 4.0, 10.0);
uniform bool embers = false;
uniform float particle_size = 0.04;
uniform float energy = 4.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.78, 0.43, 1.0);
varying float pulse;

void vertex() {
	float seed = INSTANCE_CUSTOM.r;
	float phase = seed * TAU;
	vec3 center = MODEL_MATRIX[3].xyz;
	if (embers) {
		float life = mix(1.1, 2.4, INSTANCE_CUSTOM.g);
		float age = mod(atmosphere_clock + INSTANCE_CUSTOM.b * life, life);
		float t = age / life;
		center += vec3((seed - 0.5) * 0.4, age * 0.95, (INSTANCE_CUSTOM.a - 0.5) * 0.4);
		center.xz += atmosphere_wind * t * 0.3 + vec2(sin(age * 3.0 + phase), cos(age * 2.5 + phase)) * t * 0.12;
		pulse = smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.5, 1.0, t));
	} else {
		center += (vec3(seed, INSTANCE_CUSTOM.g, INSTANCE_CUSTOM.b) - 0.5) * box_size;
		center += vec3(sin(atmosphere_clock * 0.3 + phase), sin(atmosphere_clock * 0.2 + phase * 2.0) * 0.4,
			cos(atmosphere_clock * 0.27 + phase)) * 0.35;
		pulse = pow(max(0.5 + 0.5 * sin(atmosphere_clock * (0.6 + seed * 0.4) + phase), 0.0), 3.0);
	}
	float size = particle_size * mix(0.7, 1.3, INSTANCE_CUSTOM.a);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(INV_VIEW_MATRIX[0].xyz * size, 0.0),
		vec4(INV_VIEW_MATRIX[1].xyz * size, 0.0), vec4(INV_VIEW_MATRIX[2].xyz, 0.0), vec4(center, 1.0));
}

void fragment() {
	// Only the tiny bright core writes depth. HDR DOF therefore uses the mote's own distance.
	float core = 1.0 - smoothstep(0.2, 0.5, length(UV - 0.5));
	// A hard cutout stays in the opaque pass; using ALPHA here can leave tiny points on sky depth.
	if (core < 0.5 || pulse < 0.05) discard;
	// Unshaded materials output albedo directly; keep the HDR energy in that channel.
	ALBEDO = glow_color.rgb * energy * pulse;
}
