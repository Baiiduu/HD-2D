// Optional surface response derived from the existing Meowa colour texture.
// No geometry displacement or texture resampling: the same painted texels remain visible.
group_uniforms lumina_surface;
uniform bool lumina_relief_enabled = false;
uniform float lumina_relief_strength : hint_range(0.0, 1.5, 0.05) = 0.8;
uniform float lumina_tone_strength : hint_range(0.0, 0.25, 0.01) = 0.08;
uniform float lumina_matte_floor : hint_range(0.0, 1.0, 0.01) = 0.48;
group_uniforms;

float lumina_height(vec3 color) {
	// Compress bright painted highlights so the material stays shallow.
	return sqrt(max(dot(color, vec3(0.2126, 0.7152, 0.0722)), 0.0));
}

vec3 lumina_tone(vec3 color) {
	float value = dot(color, vec3(0.2126, 0.7152, 0.0722));
	vec3 cool = color * vec3(0.9, 0.98, 1.12);
	vec3 warm = color * vec3(1.08, 1.03, 0.92);
	return mix(color, mix(cool, warm, smoothstep(0.1, 0.58, value)), lumina_tone_strength);
}

vec3 lumina_bump(vec3 normal, vec3 position, vec2 mapping, vec2 gradient) {
	vec3 dx = dFdx(position);
	vec3 dy = dFdy(position);
	vec3 r1 = cross(dy, normal);
	vec3 r2 = cross(normal, dx);
	float determinant = dot(dx, r1);
	if (abs(determinant) < 0.000001) return normal;
	vec3 slope = (r1 * dot(gradient, dFdx(mapping)) + r2 * dot(gradient, dFdy(mapping))) / determinant;
	// Prevent small distant texels from becoming sharp specular sparkles.
	slope /= max(1.0, length(slope) / 0.38);
	return normalize(normal - slope);
}
