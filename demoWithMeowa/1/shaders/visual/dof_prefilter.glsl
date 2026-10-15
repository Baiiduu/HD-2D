#[compute]
#version 450
#include "dof_common.glslinc"
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform readonly image2D scene_color;
layout(set = 0, binding = 1) uniform sampler2D scene_depth;
layout(rgba16f, set = 0, binding = 2) uniform writeonly image2D color_coc;
layout(rgba16f, set = 0, binding = 3) uniform writeonly image2D highlights;

void main() {
	ivec2 target = ivec2(gl_GlobalInvocationID.xy);
	ivec2 full_size = ivec2(p.sizes.xy);
	if (any(greaterThanEqual(target, ivec2(p.sizes.zw)))) return;
	ivec2 origin = target * 2;
	vec3 colors[4]; vec3 energy[4]; float coc[4]; float isolation[4];
	float nearest = 0.0; float largest = 0.0;
	for (int i = 0; i < 4; i++) {
		ivec2 at = min(origin + ivec2(i & 1, i >> 1), full_size - 1);
		vec3 color = max(imageLoad(scene_color, at).rgb, vec3(0.0));
		coc[i] = circle_of_confusion(texelFetch(scene_depth, at, 0).r, (float(at.y) + 0.5) / p.sizes.y);
		nearest = min(nearest, coc[i]);
		if (abs(coc[i]) > abs(largest)) largest = coc[i];
		float neighborhood = 0.0;
		for (int j = 0; j < 4; j++) {
			ivec2 offset = j == 0 ? ivec2(-4, 0) : j == 1 ? ivec2(4, 0) : j == 2 ? ivec2(0, -4) : ivec2(0, 4);
			neighborhood += luminance(imageLoad(scene_color, clamp(at + offset, ivec2(0), full_size - 1)).rgb) * 0.25;
		}
		float luma = luminance(color);
		isolation[i] = smoothstep(1.3, 3.0, luma / max(neighborhood, 0.04));
		float extraction = smoothstep(p.focus.w, p.focus.w * 2.0, luma) * isolation[i]
			* smoothstep(2.0, 4.0, abs(coc[i]));
		energy[i] = color * extraction;
		colors[i] = color - energy[i];
	}
	float chosen = nearest < -1.0 ? nearest : largest;
	vec3 filtered = vec3(0.0); vec3 extracted = vec3(0.0);
	float weights = 0.0; float isolated = 0.0; float light_weight = 0.0;
	for (int i = 0; i < 4; i++) {
		float w = 1.0 / (1.0 + abs(coc[i] - chosen) * 2.0);
		// Mixed 2x2 footprints must not turn a sharp speck into background blur.
		if (chosen > 1.0 && coc[i] < 1.0) w = 0.0;
		if (chosen < -1.0 && coc[i] > -0.5) w = 0.0;
		filtered += colors[i] * w; weights += w;
		extracted += energy[i] * 0.25;
		float light = luminance(energy[i]); isolated += isolation[i] * light; light_weight += light;
	}
	imageStore(color_coc, target, vec4(filtered / weights, chosen * 0.5));
	imageStore(highlights, target, vec4(extracted, isolated / max(light_weight, 0.0001)));
}
