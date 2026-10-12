shader_type spatial;
render_mode unshaded, cull_disabled;

// An invisible, shadow-only cloud layer. Native sun shadows reach every material.
uniform float cloud_size = 9.0;
uniform float coverage = 0.45;
uniform vec2 drift = vec2(0.0);
varying vec2 world_xz;

float cloud_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float cloud_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(cloud_hash(cell), cloud_hash(cell + vec2(1.0, 0.0)), f.x),
		mix(cloud_hash(cell + vec2(0.0, 1.0)), cloud_hash(cell + vec2(1.0)), f.x), f.y);
}

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 p = (world_xz - drift) / max(cloud_size, 1.0);
	float clouds = cloud_noise(p + 3.7) * 0.75 + cloud_noise(p * 2.3 + 19.2) * 0.25;
	float threshold = 1.0 - coverage;
	// Opaque silhouettes let native soft shadows filter cloud edges without alpha-hash grain.
	ALPHA = step(threshold, clouds);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
