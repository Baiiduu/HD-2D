#include "res://shaders/includes/aurora_sample.gdshaderinc"

group_uniforms aurora;
uniform float aurora_reflection_strength : hint_range(0.0, 8.0) = 6.0;
// X/Z world centre and two ellipse radii, independent of the camera.
uniform vec4 aurora_reflection_regions[4];
uniform int aurora_reflection_region_count = 0;
group_uniforms;

float aurora_region_mask(vec2 point) {
	float mask = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i >= aurora_reflection_region_count) break;
		vec4 region = aurora_reflection_regions[i];
		vec2 local = (point - region.xy) / max(region.zw, vec2(0.05));
		float edge = length(local) + (wet_film_noise(point * 1.6) - 0.5) * 0.22;
		mask = max(mask, 1.0 - smoothstep(0.48, 1.0, edge));
	}
	return mask;
}

vec3 aurora_ground_reflection(vec3 view, vec3 normal, float mask) {
	vec3 direction = reflect(-view, normal);
	float facing = clamp(dot(normal, view), 0.0, 1.0);
	float fresnel = 0.04 + 0.96 * pow(1.0 - facing, 5.0);
	// Three nearby directions soften the curtains on a thin, rippled film.
	vec3 color = sample_aurora(direction) * 0.5;
	color += sample_aurora(normalize(direction + vec3(0.006, 0.004, 0.0))) * 0.25;
	color += sample_aurora(normalize(direction - vec3(0.006, 0.004, 0.0))) * 0.25;
	return color * aurora_strength * aurora_reflection_strength * fresnel * mask;
}
