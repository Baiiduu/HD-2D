shader_type canvas_item;
render_mode unshaded;

uniform sampler2D selected_texture : source_color, filter_linear;
uniform float selected_mix : hint_range(0.0, 1.0) = 0.0;
uniform float background_opacity : hint_range(0.0, 1.0) = 0.72;
uniform bool edge_only_selection = false;
uniform vec3 page_color : source_color = vec3(0.035, 0.045, 0.024);
// Meowa 卡片内页范围；外侧青铜框和辉光维持原始透明度。
uniform vec4 inner_rect = vec4(0.118, 0.080, 0.764, 0.843);
varying vec4 canvas_tint;

void vertex() {
	canvas_tint = COLOR;
}

void fragment() {
	vec2 edge = min(UV - inner_rect.xy, inner_rect.xy + inner_rect.zw - UV);
	float interior = smoothstep(0.0, 0.012, edge.x) * smoothstep(0.0, 0.008, edge.y);
	// Keep the picture and text page stable: selection changes only the rim.
	float highlight = selected_mix * (edge_only_selection ? 1.0 - interior : 1.0);
	vec4 artwork = mix(texture(TEXTURE, UV), texture(selected_texture, UV), highlight);
	artwork.a *= mix(1.0, background_opacity, interior);
	// Preserve the original artwork over a dark inner page. Dense ground
	// patterns should not become competing text behind the reward details.
	float backing_alpha = interior * background_opacity;
	float alpha = artwork.a + backing_alpha * (1.0 - artwork.a);
	artwork.rgb = (artwork.rgb * artwork.a + page_color * backing_alpha * (1.0 - artwork.a)) / max(alpha, 0.001);
	artwork.a = alpha;
	COLOR = artwork * canvas_tint;
}
