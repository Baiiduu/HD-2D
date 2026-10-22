shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D effect_texture : source_color, filter_nearest, repeat_disable;
instance uniform vec4 frame_rect = vec4(0.0, 0.0, 1.0, 1.0);
instance uniform float opacity = 1.0;
instance uniform float energy = 0.65;

void fragment() {
	vec4 effect = texture(effect_texture, frame_rect.xy + UV * frame_rect.zw);
	ALBEDO = effect.rgb;
	EMISSION = effect.rgb * energy;
	ALPHA = effect.a * opacity;
}
