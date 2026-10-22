shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

void fragment() {
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * 0.35;
	ALPHA = COLOR.a;
}
