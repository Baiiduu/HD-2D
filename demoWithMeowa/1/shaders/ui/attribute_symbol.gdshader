shader_type canvas_item;
// Reuse the native Meowa silhouette as a monochrome glyph, retaining its alpha.
varying vec4 symbol_tint;
void vertex() {
	symbol_tint = COLOR;
}
void fragment() {
	COLOR = vec4(symbol_tint.rgb, symbol_tint.a * texture(TEXTURE, UV).a);
}
