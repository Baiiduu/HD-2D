#[compute]
#version 450
#include "dof_common.glslinc"
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(set = 0, binding = 0) uniform sampler2D color_coc;
layout(rgba16f, set = 0, binding = 1) uniform writeonly image2D gathered;

void main() {
	ivec2 at = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(p.sizes.zw);
	if (any(greaterThanEqual(at, size))) return;
	vec4 center = texelFetch(color_coc, at, 0);
	float max_radius = max(p.shape.x, p.shape.y) * p.focus.z * 0.5;
	float bg_weight = 1.0 / max(center.a * center.a, 1.0);
	vec3 background = center.rgb * bg_weight;
	vec3 foreground = vec3(0.0); float near_weight = 0.0;
	for (int i = 0; i < 64; i++) {
		float angle = float(i) * 2.39996323;
		float radius = sqrt((float(i) + 0.5) / 64.0) * max_radius;
		ivec2 q = clamp(at + ivec2(round(vec2(cos(angle), sin(angle)) * radius)), ivec2(0), size - 1);
		vec4 sample_color = texelFetch(color_coc, q, 0);
		float distance_px = length(vec2(q - at));
		float r = max(abs(sample_color.a), 0.5);
		if (sample_color.a < -0.5) {
			float cover = clamp(r - distance_px + 0.5, 0.0, 1.0);
			float w = cover / max(r * r, 1.0);
			foreground += sample_color.rgb * w; near_weight += w;
		} else if (center.a > 0.5) {
			float cover = clamp(min(max(center.a, 0.5), r) - distance_px + 0.5, 0.0, 1.0);
			float w = cover * max_radius * max_radius / (64.0 * max(r * r, 1.0));
			background += sample_color.rgb * w; bg_weight += w;
		}
	}
	float near_alpha = clamp(near_weight * 3.14159265 * max_radius * max_radius / 64.0, 0.0, 1.0);
	vec3 color = mix(background / bg_weight, foreground / max(near_weight, 0.0001), near_alpha);
	imageStore(gathered, at, vec4(color, near_alpha));
}
