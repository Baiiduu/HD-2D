shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D ring_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 texture_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 tint : source_color = vec4(1.0);
uniform float opacity = 0.0;

void fragment() {
	vec4 art = texture(ring_texture, texture_region.xy + UV * texture_region.zw);
	ALBEDO = art.rgb * tint.rgb;
	EMISSION = art.rgb * tint.rgb * 0.35;
	ALPHA = art.a * opacity;
}
