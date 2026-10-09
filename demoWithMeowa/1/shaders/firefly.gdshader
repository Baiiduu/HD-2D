shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// 萤火虫粒子：始终朝向镜头的小方块，亮度超过泛光阈值，靠 Glow 晕开。

uniform vec4 glow_color : source_color = vec4(0.75, 1.0, 0.45, 1.0);
uniform float energy = 3.2;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	ALBEDO = glow_color.rgb * energy * COLOR.a;
}
