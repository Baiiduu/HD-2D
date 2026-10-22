// A thin wet film on the existing opaque terrain. Native lights and SSR shade it.
group_uniforms wet_surface;
uniform bool wet_surface_enabled = false;
uniform float wet_surface_minimum : hint_range(0.0, 1.0) = 0.65;
uniform float wet_surface_coverage : hint_range(0.0, 1.0) = 0.68;
uniform float wet_surface_patch_size : hint_range(0.5, 8.0) = 2.4;
uniform float wet_surface_roughness : hint_range(0.02, 0.4) = 0.1;
uniform float wet_surface_reflectivity : hint_range(0.0, 1.5) = 0.85;
uniform float wet_surface_ripple_strength : hint_range(0.0, 0.2) = 0.045;
uniform float wet_surface_ripple_speed : hint_range(0.0, 2.0) = 0.65;
uniform float wet_surface_grass_response : hint_range(0.0, 0.3) = 0.04;
group_uniforms;

float wet_film_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float wet_film_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(wet_film_hash(cell), wet_film_hash(cell + vec2(1.0, 0.0)), f.x),
		mix(wet_film_hash(cell + vec2(0.0, 1.0)), wet_film_hash(cell + vec2(1.0)), f.x), f.y);
}

// X is the film mask; Y/Z are world-space wave slopes. Coverage stays fixed in world space.
vec3 wet_film(vec2 point, float response, float grass, float moisture, float clock, vec2 rain_slope) {
	if (!wet_surface_enabled) return vec3(0.0);
	float wet = max(moisture, wet_surface_minimum);
	float water = smoothstep(0.15, 0.6, wet * mix(response, 1.0, grass));
	float coverage = wet_surface_coverage * water;
	if (coverage <= 0.0) return vec3(0.0);
	vec2 p = point / max(wet_surface_patch_size, 0.01);
	float patch = wet_film_noise(p + vec2(13.7, 27.1)) * 0.8 + wet_film_noise(p * 3.1) * 0.2;
	float mask = smoothstep(1.0 - coverage - 0.1, 1.0 - coverage + 0.1, patch);
	mask *= water * mix(1.0, wet_surface_grass_response, grass);
	if (mask <= 0.0) return vec3(0.0);
	float phase = clock * wet_surface_ripple_speed;
	vec2 wave_uv = point * vec2(7.0, 19.0);
	vec2 slope = vec2(wet_film_noise(wave_uv + vec2(-phase, 1.7)),
		wet_film_noise(wave_uv + vec2(13.7, phase * 0.7))) * 2.0 - 1.0;
	slope += vec2(sin(point.y * 3.7 - phase), cos(point.x * 4.1 + phase * 0.8)) * 0.2;
	slope = (slope + rain_slope * 4.4) * wet_surface_ripple_strength;
	return vec3(mask, slope);
}
