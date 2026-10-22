shader_type canvas_item;
render_mode unshaded;

uniform float glow_strength : hint_range(0.0, 2.0) = 1.0;
uniform float background_opacity : hint_range(0.0, 1.0) = 0.65;

void fragment() {
	// Adjust the extracted dark well and luminous rim without redrawing the artwork.
	float bright = max(COLOR.r, max(COLOR.g, COLOR.b));
	float rim = smoothstep(0.09, 0.22, bright);
	COLOR.a *= mix(background_opacity, glow_strength, rim);
}
