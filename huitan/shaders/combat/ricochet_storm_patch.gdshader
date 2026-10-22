shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D effect_texture : source_color, filter_nearest, repeat_disable;
uniform float energy = 1.4;
instance uniform vec4 frame_rect = vec4(0.0, 0.0, 64.0, 48.0);
instance uniform float progress = 0.0;
instance uniform float intensity = 0.7;
instance uniform float phase = 0.0;

float noise(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// 四片原生命中帧错位叠成宽电涌，不放大贴图或像素。像素步距与人物一致。
	vec2 pixel = floor(UV * frame_rect.zw * 1.5) - frame_rect.zw * 0.75;
	vec4 sparks = vec4(0.0);
	for (int x = 0; x < 2; x++) {
		for (int y = 0; y < 2; y++) {
			vec2 sample_pixel = pixel - (vec2(float(x), float(y)) - 0.5) * frame_rect.zw * 0.5 + frame_rect.zw * 0.5;
			if (all(greaterThanEqual(sample_pixel, vec2(0.0))) && all(lessThan(sample_pixel, frame_rect.zw))) {
				vec4 stamp = texture(effect_texture, (frame_rect.xy + sample_pixel + 0.5) / vec2(textureSize(effect_texture, 0)));
				sparks.rgb += stamp.rgb * stamp.a;
				sparks.a += stamp.a;
			}
		}
	}
	// 固定世界像素步距的交错电流与 Meowa 电花共用配色，形成横向宽电涌。
	vec2 grid = pixel / 12.0;
	vec2 base = floor(grid);
	vec2 local = fract(grid);
	float nearest = 8.0;
	float next_nearest = 8.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 seed = base + offset + vec2(phase);
			vec2 joint = offset + vec2(noise(seed), noise(seed + vec2(37.0, 19.0))) * 0.8 + 0.1 - local;
			float distance = length(joint);
			if (distance < nearest) {
				next_nearest = nearest;
				nearest = distance;
			} else {
				next_nearest = min(next_nearest, distance);
			}
		}
	}
	float gap = next_nearest - nearest;
	float core = 1.0 - smoothstep(0.025, 0.07, gap);
	float rim = 1.0 - smoothstep(0.07, 0.19, gap);
	vec2 cell = floor(pixel / 4.0) + vec2(phase);
	float grain = noise(cell);
	float radius = length((pixel / (frame_rect.zw * 0.64)) * vec2(0.9, 1.1));
	float front = mix(0.25, 1.0, smoothstep(0.0, 0.22, progress));
	float area = 1.0 - smoothstep(front - 0.2, front + grain * 0.15, radius);
	vec2 border_pixels = min(UV, vec2(1.0) - UV) * frame_rect.zw * 1.5;
	area *= smoothstep(0.0, 4.0, min(border_pixels.x, border_pixels.y));
	float fade = 1.0 - smoothstep(0.36, 1.0, progress);
	// 低亮蓝色电气把电花连成片，保留可见的怪物与地表。
	vec3 color = mix(vec3(0.14, 0.52, 1.0), vec3(0.72, 0.94, 1.0), rim);
	color = mix(color, vec3(0.9, 1.0, 1.0), core);
	color += min(sparks.rgb, vec3(1.0)) * 0.16;
	ALBEDO = color;
	EMISSION = color * energy;
	ALPHA = min(0.85, core * 0.65 + rim * 0.32 + sparks.a * 0.16 + 0.16 + grain * 0.12) * area * fade * intensity;
}
