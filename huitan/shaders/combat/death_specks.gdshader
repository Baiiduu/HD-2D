shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D spark_texture : source_color, filter_nearest, repeat_disable;
uniform bool dust_mode = false;
void fragment() {
	vec4 pixel;
	if (dust_mode) {
		// 小簇烟尘由世界像素格构成，不使用 TIME，冻结时保持原状。
		vec2 p = (floor(UV * 16.0) + 0.5) / 16.0;
		float shape = min(length((p - vec2(0.38, 0.56)) / vec2(0.29, 0.30)), length((p - vec2(0.66, 0.55)) / vec2(0.26, 0.25)));
		shape = min(shape, length((p - vec2(0.52, 0.36)) / vec2(0.25, 0.27)));
		pixel = vec4(vec3(0.68 + step(0.46, p.y) * 0.13), 1.0 - step(1.0, shape));
	} else {
		// 原生 Meowa 碰点中心的 6×6 白金碎屑，直接采样，不重制像素。
		pixel = texture(spark_texture, (vec2(16.0, 21.0) + UV * 6.0) / vec2(168.0, 96.0));
	}
	ALBEDO = pixel.rgb * COLOR.rgb;
	EMISSION = ALBEDO * (dust_mode ? 0.0 : 0.7);
	ALPHA = pixel.a * COLOR.a;
}
