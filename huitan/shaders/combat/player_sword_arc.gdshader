shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform float opacity = 0.9;
uniform float energy = 0.08;
uniform float attack_radius = 1.52;
uniform float leading_angle = 0.0;
uniform float trail_angle = 1.08;
uniform float band_width = 0.10;
uniform float pixel_size = 0.016;
uniform float fade = 1.0;
uniform vec2 plane_slope = vec2(0.0);
uniform vec4 blade_color : source_color = vec4(1.0, 0.88, 0.64, 1.0);
uniform vec4 tail_color : source_color = vec4(0.82, 0.18, 0.12, 0.65);

void vertex() {
	VERTEX.y += dot(VERTEX.xz, plane_slope);
}

void fragment() {
	// 网格仍使用真实扇区和挡墙裁切；仅在外沿短弧上着色。
	vec2 point = (UV - vec2(0.5)) * (2.0 * attack_radius);
	point = floor(point / pixel_size + vec2(0.5)) * pixel_size;
	float radius = length(point);
	float angle = atan(point.x, -point.y);
	float lag = leading_angle - angle;
	float tail = clamp(lag / trail_angle, 0.0, 1.0);
	float reached = step(0.0, lag) * step(lag, trail_angle);
	float taper = smoothstep(0.0, 0.10, lag) * pow(1.0 - tail, 0.65);
	float width = band_width * taper;
	float outside = attack_radius - pixel_size * 0.5;
	float center = outside - width * 0.5;
	float band = step(abs(radius - center), width * 0.5) * reached;
	float core = step(abs(radius - (outside - width * 0.35)), max(pixel_size * 0.5, width * 0.13)) * band;
	float bright = 1.0 - smoothstep(0.06, 0.38, tail);
	vec3 color = mix(tail_color.rgb, blade_color.rgb, core * bright);
	float alpha = band * mix(tail_color.a, blade_color.a, core * bright) * sqrt(1.0 - tail) * fade;
	ALBEDO = color;
	EMISSION = blade_color.rgb * energy * core * bright;
	ALPHA = alpha * opacity;
}
