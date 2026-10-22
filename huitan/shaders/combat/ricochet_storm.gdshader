shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D effect_texture : source_color, filter_nearest, repeat_disable;
uniform float energy : hint_range(0.0, 4.0) = 1.4;
uniform bool arc_spine = false;
uniform sampler2D spine_palette : source_color, filter_nearest, repeat_disable;
instance uniform float intensity = 1.0;
instance uniform vec4 source_rect = vec4(0.0, 0.0, 1.0, 1.0);
instance uniform float phase = 0.0;
instance uniform bool show_spine = true;

float turn(float value) {
	return fract(sin(value * 127.1 + 311.7) * 43758.5453) * 2.0 - 1.0;
}

void fragment() {
	vec4 effect = texture(effect_texture, source_rect.xy + UV * source_rect.zw);
	if (arc_spine && show_spine) {
		// 固定 128×16 原生像素步距生成连续主干，Meowa 原纹理提供细枝和配色。
		float x = floor(UV.x * source_rect.z * 128.0);
		float y = floor(UV.y * 16.0);
		float cell = x / 10.0;
		float ends = smoothstep(0.0, 8.0, x) * (1.0 - smoothstep(source_rect.z * 128.0 - 8.0, source_rect.z * 128.0, x));
		float zigzag = mix(turn(floor(cell) + phase), turn(floor(cell) + 1.0 + phase), fract(cell));
		float center = 7.0 + floor(zigzag * 4.0 * ends);
		float core = 1.0 - step(0.6, abs(y - center));
		float rim = (1.0 - step(1.6, abs(y - center))) * 0.3;
		vec3 color = texture(spine_palette, vec2(0.45, 0.5)).rgb;
		effect.rgb = mix(effect.rgb, color * vec3(0.45, 0.9, 1.25), rim);
		effect.rgb = mix(effect.rgb, min(vec3(1.0), color * 1.35 + 0.25), core);
		effect.a = max(effect.a, max(core, rim));
	}
	ALBEDO = effect.rgb;
	EMISSION = effect.rgb * energy;
	ALPHA = effect.a * intensity;
}
