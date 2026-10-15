#[vertex]
#version 450
#include "dof_common.glslinc"
layout(set = 0, binding = 0) uniform sampler2D color_coc;
layout(set = 0, binding = 1) uniform sampler2D highlights;
layout(set = 0, binding = 2) uniform sampler2D gathered;
layout(location = 0) out vec2 disc_uv;
layout(location = 1) flat out vec3 disc_color;
layout(location = 2) flat out float disc_radius;

void main() {
	int id = gl_InstanceIndex;
	int columns = int(p.camera.z);
	ivec2 origin = ivec2(id % columns, id / columns) * 2;
	vec3 energy = vec3(0.0); vec2 center = vec2(0.0);
	float coc = 0.0; float isolation = 0.0; float weights = 0.0;
	for (int i = 0; i < 4; i++) {
		ivec2 q = origin + ivec2(i & 1, i >> 1);
		if (any(greaterThanEqual(q, ivec2(p.sizes.zw)))) continue;
		vec4 h = texelFetch(highlights, q, 0);
		float w = luminance(h.rgb);
		energy += h.rgb; center += (vec2(q) + 0.5) * w;
		coc += texelFetch(color_coc, q, 0).a * w;
		isolation += h.a * w; weights += w;
	}
	if (weights < 0.0001) { gl_Position = vec4(2.0, 2.0, 0.0, 1.0); return; }
	center /= weights; coc /= weights; isolation /= weights;
	bool near_disc = coc < -0.75;
	if (near_disc != (p.band.w > 0.5) || abs(coc) < 0.75) { gl_Position = vec4(2.0, 2.0, 0.0, 1.0); return; }
	float radius = clamp(abs(coc), 0.75, max(p.shape.x, p.shape.y) * p.focus.z * 0.5);
	const vec2 corners[6] = vec2[6](vec2(-1,-1), vec2(1,-1), vec2(-1,1), vec2(-1,1), vec2(1,-1), vec2(1,1));
	vec2 corner = corners[gl_VertexIndex];
	disc_uv = corner * (radius + 1.0);
	disc_radius = radius;
	float gain = 1.0 + p.band.z * isolation * smoothstep(0.75, 3.0, radius) * (3.0 + radius * 0.4);
	disc_color = energy * gain / max(3.14159265 * radius * radius, 1.0);
	gl_Position = vec4((center + disc_uv) / p.sizes.zw * 2.0 - 1.0, 0.0, 1.0);
}

#[fragment]
#version 450
#include "dof_common.glslinc"
layout(set = 0, binding = 0) uniform sampler2D color_coc;
layout(set = 0, binding = 1) uniform sampler2D highlights;
layout(set = 0, binding = 2) uniform sampler2D gathered;
layout(location = 0) in vec2 disc_uv;
layout(location = 1) flat in vec3 disc_color;
layout(location = 2) flat in float disc_radius;
layout(location = 0) out vec4 result;

void main() {
	float distance_px = length(disc_uv);
	float cover = clamp(disc_radius - distance_px + 0.5, 0.0, 1.0);
	if (p.band.w < 0.5) {
		ivec2 q = clamp(ivec2(gl_FragCoord.xy), ivec2(0), ivec2(p.sizes.zw) - 1);
		float limit = max(min(abs(texelFetch(color_coc, q, 0).a), disc_radius), 0.5);
		cover = clamp(limit - distance_px + 0.5, 0.0, 1.0) * (1.0 - texelFetch(gathered, q, 0).a);
	}
	float rim = 0.94 + 0.2 * smoothstep(disc_radius * 0.6, disc_radius, distance_px);
	result = vec4(disc_color * cover * rim, 0.0);
}
