shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D effect_texture : source_color, filter_nearest, repeat_disable;
uniform float energy : hint_range(0.0, 4.0) = 0.2;

void fragment() {
	vec4 crystal = texture(effect_texture, UV);
	// 晶面保留蓝色与金边，用少量自发光突出亮芯。
	ALBEDO = crystal.rgb;
	EMISSION = crystal.rgb * energy;
	ALPHA = crystal.a;
}
