// Shared clock and wind: changing weather never resets an emitter's random phase.
uniform float atmosphere_clock = 0.0;
uniform vec2 atmosphere_wind = vec2(0.7, 0.2);

float atmosphere_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float atmosphere_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 w = f * f * (3.0 - 2.0 * f);
	return mix(mix(atmosphere_hash(i), atmosphere_hash(i + vec2(1.0, 0.0)), w.x),
		mix(atmosphere_hash(i + vec2(0.0, 1.0)), atmosphere_hash(i + vec2(1.0)), w.x), w.y);
}

vec3 atmosphere_bend(vec3 world, vec3 root, float height, float phase, float flexibility) {
	vec2 direction = normalize(atmosphere_wind + vec2(0.0001, 0.0));
	float weight = pow(clamp((world.y - root.y) / max(height, 0.1), 0.0, 1.0), 1.4);
	float gust = 0.6 + 0.4 * sin(atmosphere_clock * 0.46 - dot(root.xz, direction) * 0.12);
	float wave = sin(atmosphere_clock * 1.23 + phase) * 0.7
		+ sin(atmosphere_clock * 2.31 + phase * 1.6) * 0.3;
	float flutter = sin(atmosphere_clock * 4.1 + dot(world, vec3(2.7, 1.8, 1.6)) + phase) * 0.14;
	float amount = length(atmosphere_wind) * flexibility * weight;
	vec2 offset = (direction * (wave + gust * 0.5) + vec2(-direction.y, direction.x) * flutter) * amount;
	return vec3(offset.x, -dot(offset, offset) / max(height, 0.1), offset.y);
}
