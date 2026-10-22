// Map material albedo to five authored colours before real lighting.
// The source pixel grid and alpha are unchanged.
vec3 pixel_palette_map(vec3 color, sampler2D ramp, int row) {
	vec3 result = texelFetch(ramp, ivec2(0, row), 0).rgb;
	vec3 delta = color - result;
	float best = dot(delta * delta, vec3(0.3, 0.59, 0.11));
	for (int index = 1; index < 5; index++) {
		vec3 candidate = texelFetch(ramp, ivec2(index, row), 0).rgb;
		delta = color - candidate;
		float distance = dot(delta * delta, vec3(0.3, 0.59, 0.11));
		if (distance < best) {
			best = distance;
			result = candidate;
		}
	}
	return result;
}
