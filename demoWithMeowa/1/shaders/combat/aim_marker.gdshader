shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.9, 0.82, 0.66, 1.0);
uniform float opacity = 0.45;
uniform vec2 size_pixels = vec2(6.0);
uniform bool brackets = false;

void fragment() {
	vec2 point = floor(UV * size_pixels) + vec2(0.5);
	float shape;
	if (brackets) {
		vec2 edge = min(point, size_pixels - point);
		float arm = min(6.0, min(size_pixels.x, size_pixels.y) * 0.2);
		shape = max((1.0 - step(1.0, edge.x)) * (1.0 - step(arm, edge.y)),
			(1.0 - step(1.0, edge.y)) * (1.0 - step(arm, edge.x)));
	} else {
		float radius = length(point - size_pixels * 0.5);
		shape = step(1.8, radius) * (1.0 - step(3.0, radius));
	}
	ALBEDO = tint.rgb;
	ALPHA = shape * opacity * tint.a;
}
