shader_type canvas_item;
render_mode unshaded;

uniform vec4 edge_color : source_color = vec4(0.21, 0.075, 0.035, 1.0);
uniform float amount = 0.0;

void fragment() {
	vec2 p = abs(UV - vec2(0.5)) * 2.0;
	float edge = smoothstep(0.55, 1.12, max(p.x, p.y));
	COLOR = vec4(edge_color.rgb, edge * amount);
}
