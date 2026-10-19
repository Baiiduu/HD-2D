// One surface model for the player's spatial ribbon and its title-screen projection.
// Inputs stay in ground meters; coals remain fixed to that plane at every camera angle.
struct GroundFireSurface {
	vec3 albedo;
	vec3 emission;
	float coverage;
};

float fire_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float fire_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(fire_hash(cell), fire_hash(cell + vec2(1.0, 0.0)), f.x),
		mix(fire_hash(cell + vec2(0.0, 1.0)), fire_hash(cell + vec2(1.0)), f.x), f.y);
}

GroundFireSurface ground_fire_surface(vec2 ground_point, vec2 ribbon_point,
		float ribbon_length, float ribbon_width, float age, float clock_seconds,
		vec3 durations, float emission_energy, float pixel_density) {
	GroundFireSurface surface;
	surface.albedo = vec3(0.0);
	surface.emission = vec3(0.0);
	surface.coverage = 0.0;
	float fresh_duration = durations.x;
	float burn_duration = durations.y;
	float ember_duration = durations.z;
	float lifetime = fresh_duration + burn_duration + ember_duration;
	if (age < 0.0 || age >= lifetime) return surface;
	float burn = smoothstep(fresh_duration * 0.65, fresh_duration + burn_duration * 0.25, age);
	float ember = smoothstep(fresh_duration + burn_duration * 0.7, fresh_duration + burn_duration + 0.18, age);
	float fading = smoothstep(fresh_duration + burn_duration, lifetime, age);
	vec2 pixel = floor(ground_point * pixel_density);
	vec2 p = (pixel + 0.5) / pixel_density;
	float clock = floor(clock_seconds * 14.0) / 14.0;
	float clumps = fire_noise(p * 10.5 + vec2(0.0, -clock * 2.0));
	float threads = fire_noise(p * 27.0 + vec2(clock * 2.5, -clock * 3.5));
	float grain = fire_hash(pixel);
	float along = ribbon_point.x;
	float across = ribbon_point.y;
	float cap = along - clamp(along, -ribbon_length * 0.5, ribbon_length * 0.5);
	float radius = length(vec2(cap, across)) / max(ribbon_width * 0.5, 0.00001);
	float edge = 1.0 - radius;
	float heat = edge * 0.7 + clumps * 0.42 + threads * 0.2;
	float threshold = mix(0.57, 0.73, burn);
	threshold = mix(threshold, 0.9, ember);
	// Late coals keep a fixed pattern in ground space, with a slow pulse.
	float coal = fire_noise(p * 20.0) * 0.65 + grain * 0.35;
	float coal_heat = edge * 0.55 + coal * 0.6;
	heat = mix(heat, coal_heat, ember);
	float ragged_edge = mix(0.5, 1.0, clumps);
	if (radius > mix(ragged_edge, 0.9, ember) || heat < threshold || grain < burn * 0.08 + fading * 0.8) return surface;
	float core = smoothstep(threshold + 0.06, 1.15, heat);
	vec3 orange = vec3(1.0, 0.16, 0.012);
	vec3 yellow = vec3(1.0, 0.74, 0.16);
	vec3 fresh = mix(orange, yellow, core * (1.0 - burn * 0.6));
	vec3 coals = mix(vec3(0.3, 0.008, 0.002), vec3(0.95, 0.09, 0.012), smoothstep(0.82, 1.12, coal_heat));
	vec3 tint = mix(fresh, coals, ember);
	float pulse = mix(1.0, 0.8 + 0.2 * sin(clock_seconds * 4.0 + grain * 12.0), ember);
	surface.albedo = tint * mix(0.8, 0.35, ember);
	surface.emission = tint * emission_energy * mix(1.65, 0.55, ember) * (1.0 - fading * 0.85) * pulse;
	surface.coverage = 1.0;
	return surface;
}
