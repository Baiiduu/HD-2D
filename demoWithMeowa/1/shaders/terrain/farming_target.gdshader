shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 target_color : source_color = vec4(0.9, 0.77, 0.47, 0.8);
uniform float border_width = 0.018;

void fragment() {
	float edge = min(min(UV.x, UV.y), min(1.0 - UV.x, 1.0 - UV.y));
	ALBEDO = target_color.rgb;
	ALPHA = (1.0 - step(border_width, edge)) * target_color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.25;
}
