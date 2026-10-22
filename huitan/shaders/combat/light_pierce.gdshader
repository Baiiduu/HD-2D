shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D effect_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 frame_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 tint : source_color = vec4(1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.8;
uniform float energy : hint_range(0.0, 4.0) = 1.0;
uniform float edge_fade : hint_range(0.0, 0.25) = 0.06;
uniform float clip_start : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 effect = texture(effect_texture, frame_rect.xy + UV * frame_rect.zw);
	float ends = smoothstep(0.0, max(edge_fade, 0.001), UV.x)
		* (1.0 - smoothstep(1.0 - max(edge_fade, 0.001), 1.0, UV.x));
	ALBEDO = effect.rgb * tint.rgb;
	EMISSION = effect.rgb * tint.rgb * energy;
	ALPHA = effect.a * opacity * tint.a * ends * step(clip_start, UV.x);
}
