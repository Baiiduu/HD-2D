shader_type canvas_item;

// 全屏后处理：椭圆虚化 + 暗角 + 分离色调（暗部偏冷、亮部偏暖）。

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform sampler2D blurred_screen : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform bool ellipse_enabled = false;
uniform vec2 ellipse_center = vec2(0.5);
uniform vec2 ellipse_radius = vec2(0.34, 0.27);
uniform float ellipse_transition : hint_range(0.05, 2.0) = 0.7;
uniform float ellipse_blur_amount : hint_range(0.0, 1.0) = 0.03;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.35;
uniform float vignette_radius : hint_range(0.2, 1.5) = 0.85;
uniform vec3 shadow_tint : source_color = vec3(0.86, 0.94, 1.12);
uniform vec3 highlight_tint : source_color = vec3(1.08, 1.0, 0.9);
uniform float split_toning : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	vec3 color = texture(screen_texture, SCREEN_UV).rgb;
	if (ellipse_enabled && ellipse_blur_amount > 0.0) {
		float radius = length((SCREEN_UV - ellipse_center) / max(ellipse_radius, vec2(0.01)));
		float mask = smoothstep(1.0, 1.0 + max(ellipse_transition, 0.01), radius);
		float lod = log2(1.0 + ellipse_blur_amount * 64.0 * mask);
		vec3 blurred = textureLod(blurred_screen, SCREEN_UV, lod).rgb;
		color = mix(color, blurred, mask);
	}
	float luma = dot(color, vec3(0.3, 0.59, 0.11));
	vec3 toned = color * mix(shadow_tint, highlight_tint, smoothstep(0.15, 0.7, luma));
	color = mix(color, toned, split_toning);
	vec2 centered = (SCREEN_UV - 0.5) * vec2(1.0, 0.8);
	float vignette = smoothstep(vignette_radius, vignette_radius * 0.35, length(centered) * 1.6);
	color *= mix(1.0 - vignette_strength, 1.0, vignette);
	COLOR = vec4(color, 1.0);
}
