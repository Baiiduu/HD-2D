shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D slash_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 frame_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 art_scale = vec2(0.424107);
uniform float art_angle = 0.0;
uniform float attack_radius = 1.52;
uniform float leading_angle = 0.0;
uniform float trail_angle = 1.08;
uniform float band_width = 0.25;
uniform float body_opacity = 0.08;
uniform float tail_spread = 2.5;
uniform float tail_inner_ratio = 0.3;
uniform float opacity = 0.9;
uniform float energy = 0.08;
uniform vec2 plane_slope = vec2(0.0);

void vertex() {
	VERTEX.y += dot(VERTEX.xz, plane_slope);
}

vec4 original_band(float radial, float tail, float span) {
	float source_angle = art_angle - (tail - 0.20) * span;
	float source_radius = mix(0.45, 1.12, clamp(radial, 0.0, 1.0));
	vec2 source_uv = vec2(0.5) + vec2(sin(source_angle), -cos(source_angle)) * source_radius * art_scale;
	float in_canvas = step(0.0, source_uv.x) * step(source_uv.x, 1.0) * step(0.0, source_uv.y) * step(source_uv.y, 1.0);
	vec2 half_texel = vec2(0.5) / vec2(textureSize(slash_texture, 0));
	vec2 atlas_uv = clamp(frame_rect.xy + source_uv * frame_rect.zw, frame_rect.xy + half_texel, frame_rect.xy + frame_rect.zw - half_texel);
	float radial_mask = smoothstep(0.0, 0.06, radial) * (1.0 - smoothstep(0.97, 1.0, radial));
	vec4 result = texture(slash_texture, atlas_uv);
	result.a *= radial_mask * in_canvas;
	return result;
}

float colored_tail(vec3 color) {
	float highest = max(color.r, max(color.g, color.b));
	float lowest = min(color.r, min(color.g, color.b));
	return smoothstep(0.25, 0.50, (highest - lowest) / max(highest, 0.001));
}

void fragment() {
	vec2 point = (UV - vec2(0.5)) * (2.0 * attack_radius);
	float lag = leading_angle - atan(point.x, -point.y);
	float tail = clamp(lag / trail_angle, 0.0, 1.0);
	float angular_mask = step(0.0, lag) * step(lag, trail_angle);
	float taper = smoothstep(0.0, 0.08, tail) * sqrt(1.0 - tail);
	// 外端对应真实刀锋，后缘沿曲线收回腰侧，不绘制人物至刀锋的直线。
	float curve_radius = attack_radius * mix(tail_inner_ratio, 1.0, pow(1.0 - tail, 1.5));
	float width = max(min(band_width, curve_radius * 0.65) * taper, 0.0001);
	float trail_width = max(min(band_width * tail_spread, curve_radius * 0.65) * taper, 0.0001);
	float radial = length(point) - curve_radius;
	vec4 body = original_band((radial + width) / width, tail, 1.70);
	vec4 trail = original_band((radial + trail_width) / trail_width, tail, 2.80);
	// 白刃只留少量提示；有色笔触及碎屑在更宽的区域直接取自原帧。
	body.a *= (1.0 - colored_tail(body.rgb)) * body_opacity;
	trail.a *= colored_tail(trail.rgb);
	float combined_alpha = body.a + trail.a * (1.0 - body.a);
	vec3 color = (body.rgb * body.a + trail.rgb * trail.a * (1.0 - body.a)) / max(combined_alpha, 0.0001);
	ALBEDO = color;
	EMISSION = color * energy;
	ALPHA = combined_alpha * opacity * angular_mask;
}
