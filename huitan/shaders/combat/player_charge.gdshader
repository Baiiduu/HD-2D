shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec2 size_pixels = vec2(90.0);
uniform float radius_pixels = 42.0;
uniform float charge : hint_range(0.0, 1.0) = 0.0;
uniform float full_flash : hint_range(0.0, 1.0) = 0.0;
uniform float opacity = 0.95;
uniform float energy = 0.35;

void fragment() {
	vec2 point = floor(UV * size_pixels) + vec2(0.5) - size_pixels * 0.5;
	point.y = -point.y;
	vec3 cream = vec3(1.0, 0.65, 0.28);
	vec3 orange = vec3(1.0, 0.06, 0.015);
	float radius = length(point);
	// 留出后方四分之一缺口；十二块圆弧按真实蓄力逐块点亮。
	float angle = mod(atan(point.x, -point.y) - PI * 0.25 + TAU, TAU);
	float section = angle / (PI * 1.5) * 12.0;
	float segment = floor(section);
	float gap = step(0.12, fract(section)) * (1.0 - step(0.88, fract(section)));
	float shape = step(radius_pixels - 6.0, radius) * (1.0 - step(radius_pixels, radius));
	shape *= (1.0 - step(12.0, section)) * gap;
	float filled = step(segment + 1.0, charge * 12.0 + 0.001);
	float accent = 1.0 - step(0.5, mod(segment, 3.0));
	vec3 tint = mix(cream, orange, accent * (0.7 + charge * 0.3));
	tint = mix(tint, vec3(1.0, 0.97, 0.86), full_flash * 0.85);
	float brightness = mix(0.13, 1.0, filled);
	ALBEDO = tint;
	EMISSION = tint * energy * (1.0 + full_flash);
	ALPHA = shape * brightness * opacity;
}
