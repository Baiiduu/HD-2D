shader_type canvas_item;
render_mode unshaded;

uniform float glow_strength : hint_range(0.0, 2.0) = 1.0;
uniform float background_opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// Preserve the extracted artwork while adjusting its dark well and luminous edge.
	float luminance = dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	float rim = smoothstep(0.13, 0.4, luminance);
	COLOR.a *= mix(background_opacity, glow_strength, rim);
}
