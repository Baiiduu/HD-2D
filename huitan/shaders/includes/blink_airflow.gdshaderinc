// World-space paths remain fixed after the character moves on. Start.w is age in seconds.
uniform int blink_path_count = 0;
uniform vec4 blink_path_starts[8];
uniform vec4 blink_path_ends[8];

float blink_path_weight(vec3 point, int index, float radius, float height, float height_offset) {
	vec3 start = blink_path_starts[index].xyz;
	vec3 end = blink_path_ends[index].xyz;
	vec2 segment = end.xz - start.xz;
	float along = clamp(dot(point.xz - start.xz, segment) / max(dot(segment, segment), 0.0001), 0.0, 1.0);
	vec3 closest = mix(start, end, along);
	float horizontal = 1.0 - smoothstep(0.0, max(radius, 0.001), distance(point.xz, closest.xz));
	float vertical = 1.0 - smoothstep(0.0, max(height, 0.001), abs(point.y - closest.y - height_offset));
	return horizontal * vertical;
}

vec3 blink_path_direction(int index) {
	vec2 direction = normalize(blink_path_ends[index].xz - blink_path_starts[index].xz);
	return vec3(direction.x, 0.0, direction.y);
}
