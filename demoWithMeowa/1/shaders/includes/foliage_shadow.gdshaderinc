// Rounded, feathered casting volumes. Only the light's view selects their pose.
// The displayed sprite and its native alpha remain unchanged.
vec3 foliage_shadow_forward(mat4 light_view) {
	vec3 direction = vec3(light_view[2].x, 0.0, light_view[2].z);
	return length(direction) > 0.001 ? normalize(direction) : vec3(0.0, 0.0, 1.0);
}

float foliage_shadow_coverage(vec2 uv, vec2 center, vec2 radius) {
	float distance = length((uv - center) / max(radius, vec2(0.001)));
	return 1.0 - smoothstep(0.5, 1.0, distance);
}

float foliage_shadow_sample(vec2 uv) {
	// Fixed in the casting card, never in screen coordinates or animated time.
	vec2 cell = floor(uv * 512.0);
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}
