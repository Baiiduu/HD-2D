shader_type canvas_item;
render_mode unshaded;

uniform bool blend_edges = false;
uniform vec2 display_size = vec2(1.0);
// 左、右、上、下：下缘留更长的过渡，与文字区上方的卡纸衔接。
uniform vec4 edge_fade = vec4(0.07, 0.07, 0.06, 0.18);
varying vec2 page_uv;
varying vec4 canvas_tint;

void vertex() {
	// 填满插画区时纹理 UV 会裁切；以控件边界计算羽化。
	page_uv = VERTEX / max(display_size, vec2(1.0));
	canvas_tint = COLOR;
}

void fragment() {
	vec4 artwork = texture(TEXTURE, UV) * canvas_tint;
	if (blend_edges) {
		vec4 distance_to_edge = vec4(page_uv.x, 1.0 - page_uv.x, page_uv.y, 1.0 - page_uv.y);
		vec4 fade = smoothstep(vec4(0.0), edge_fade, distance_to_edge);
		// 仅改变透明度，露出原有卡纸；不添加黑色晕影或改变主体颜色。
		artwork.a *= fade.x * fade.y * fade.z * fade.w;
	}
	COLOR = artwork;
}
