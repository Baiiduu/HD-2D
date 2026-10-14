shader_type canvas_item;
render_mode unshaded;

uniform sampler2D selected_texture : source_color, filter_linear;
uniform float selected_mix : hint_range(0.0, 1.0) = 0.0;
uniform float background_opacity : hint_range(0.0, 1.0) = 0.72;
// Meowa 卡片内页范围；外侧青铜框和辉光维持原始透明度。
uniform vec4 inner_rect = vec4(0.118, 0.080, 0.764, 0.843);
varying vec4 canvas_tint;

void vertex() {
	canvas_tint = COLOR;
}

void fragment() {
	vec4 artwork = mix(texture(TEXTURE, UV), texture(selected_texture, UV), selected_mix);
	vec2 edge = min(UV - inner_rect.xy, inner_rect.xy + inner_rect.zw - UV);
	float interior = smoothstep(0.0, 0.012, edge.x) * smoothstep(0.0, 0.008, edge.y);
	artwork.a *= mix(1.0, background_opacity, interior);
	// Preserve the original artwork over a dark inner page. Dense ground
	// patterns should not become competing text behind the reward details.
	float backing_alpha = interior * background_opacity;
	float alpha = artwork.a + backing_alpha * (1.0 - artwork.a);
	vec3 page = vec3(0.035, 0.045, 0.024);
	artwork.rgb = (artwork.rgb * artwork.a + page * backing_alpha * (1.0 - artwork.a)) / max(alpha, 0.001);
	artwork.a = alpha;
	COLOR = artwork * canvas_tint;
}
