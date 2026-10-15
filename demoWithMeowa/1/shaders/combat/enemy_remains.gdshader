shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D effect_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 frame_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float opacity = 1.0;
void fragment() {
	vec4 pixel = texture(effect_texture, frame_rect.xy + UV * frame_rect.zw);
	ALBEDO = pixel.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = pixel.a * opacity;
}
