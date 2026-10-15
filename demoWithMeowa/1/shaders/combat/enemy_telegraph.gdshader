shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec2 display_size = vec2(1.0);
uniform float pixel_size = 0.016;
uniform bool circle = false;
uniform float opacity = 0.5;
uniform vec4 tint : source_color = vec4(1.0, 0.29, 0.08, 1.0);

void fragment() {
	vec2 point = (floor(UV * display_size / pixel_size) + 0.5) * pixel_size;
	float shape;
	if (circle) {
		float distance = length(point - display_size * 0.5);
		float radius = display_size.x * 0.5 - pixel_size * 2.0;
		shape = 1.0 - step(pixel_size * 2.0, abs(distance - radius));
	} else {
		vec2 uv = point / display_size;
		float repeat_x = fract(uv.x * max(1.0, display_size.x / 0.55));
		float arrow = abs(repeat_x - 0.65 + abs(uv.y - 0.5));
		shape = 1.0 - step(0.1, arrow);
	}
	ALBEDO = tint.rgb;
	EMISSION = tint.rgb * 0.15;
	ALPHA = shape * opacity * tint.a;
}
