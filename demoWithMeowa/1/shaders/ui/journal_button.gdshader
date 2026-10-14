shader_type canvas_item;
render_mode unshaded;

uniform float press_offset = 0.0;
uniform float brightness = 0.0;

void vertex() {
	// Move the painted button without moving its input rectangle.
	VERTEX.y += press_offset;
}

void fragment() {
	COLOR.rgb *= 1.0 + brightness;
}
