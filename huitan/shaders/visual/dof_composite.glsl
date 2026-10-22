#[compute]
#version 450
#include "dof_common.glslinc"
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform image2D scene_color;
layout(set = 0, binding = 1) uniform sampler2D scene_depth;
layout(set = 0, binding = 2) uniform sampler2D color_coc;
layout(set = 0, binding = 3) uniform sampler2D gathered;
layout(set = 0, binding = 4) uniform sampler2D far_bokeh;
layout(set = 0, binding = 5) uniform sampler2D near_bokeh;

void main() {
	ivec2 at = ivec2(gl_GlobalInvocationID.xy);
	if (any(greaterThanEqual(at, ivec2(p.sizes.xy)))) return;
	vec2 uv = (vec2(at) + 0.5) / p.sizes.xy;
	float coc = circle_of_confusion(texelFetch(scene_depth, at, 0).r, uv.y);
	vec4 sharp = imageLoad(scene_color, at);
	vec2 reduced = uv * p.sizes.zw - 0.5;
	ivec2 base = ivec2(floor(reduced));
	vec2 f = fract(reduced);
	vec4 blur = vec4(0.0); float weights = 0.0;
	for (int i = 0; i < 4; i++) {
		ivec2 offset = ivec2(i & 1, i >> 1);
		ivec2 q = clamp(base + offset, ivec2(0), ivec2(p.sizes.zw) - 1);
		vec4 g = texelFetch(gathered, q, 0);
		float layer_coc = texelFetch(color_coc, q, 0).a;
		vec2 bilinear = mix(vec2(1.0) - f, f, vec2(offset));
		float w = bilinear.x * bilinear.y / (1.0 + abs(layer_coc * 2.0 - coc));
		// Sharp samples cannot bleed into a blurry background during reconstruction.
		if (abs(coc) > 1.0 && abs(layer_coc * 2.0) < 1.0 && g.a < 0.001) w = 0.0;
		blur += vec4(g.rgb + texelFetch(far_bokeh, q, 0).rgb, g.a) * w; weights += w;
	}
	blur /= max(weights, 0.0001);
	float blend = 1.0 - (1.0 - smoothstep(1.0, 3.0, abs(coc))) * (1.0 - clamp(blur.a, 0.0, 1.0));
	vec3 result = mix(sharp.rgb, blur.rgb, blend) + texture(near_bokeh, uv).rgb;
	imageStore(scene_color, at, vec4(result, sharp.a));
}
