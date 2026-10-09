shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// 灯光光晕：始终朝向镜头的加色面片，径向衰减，按像素网格量化保持像素风。
// 颜色用实例参数，同一个材质可以给不同颜色的灯使用。

instance uniform vec4 halo_color : source_color = vec4(1.0, 0.82, 0.58, 1.0);
uniform float energy = 0.35;
// 光晕直径上的像素数
uniform float pixels = 28.0;
uniform float falloff = 2.4;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 uv = (floor(UV * pixels) + 0.5) / pixels;
	float r = length(uv - 0.5) * 2.0;
	float intensity = pow(clamp(1.0 - r, 0.0, 1.0), falloff);
	ALBEDO = halo_color.rgb * energy * intensity;
}
