shader_type canvas_item;

// 全屏后处理：暗角 + 分离色调（暗部偏冷、亮部偏暖）。

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;
uniform float vignette_radius : hint_range(0.2, 1.5) = 0.85;
uniform vec3 shadow_tint : source_color = vec3(0.86, 0.94, 1.12);
uniform vec3 highlight_tint : source_color = vec3(1.08, 1.0, 0.9);
uniform float split_toning : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec3 color = texture(screen_texture, SCREEN_UV).rgb;
	float luma = dot(color, vec3(0.3, 0.59, 0.11));
	vec3 toned = color * mix(shadow_tint, highlight_tint, smoothstep(0.15, 0.7, luma));
	color = mix(color, toned, split_toning);
	vec2 centered = (SCREEN_UV - 0.5) * vec2(1.0, 0.8);
	float vignette = smoothstep(vignette_radius, vignette_radius * 0.35, length(centered) * 1.6);
	color *= mix(1.0 - vignette_strength, 1.0, vignette);
	COLOR = vec4(color, 1.0);
}
