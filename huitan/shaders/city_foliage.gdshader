shader_type spatial;
render_mode cull_disabled;

uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform float wind_amount = 0.045;

void vertex() {
	float anchor_weight = max(VERTEX.y - 0.45, 0.0);
	float phase = NODE_POSITION_WORLD.x * 0.71 + NODE_POSITION_WORLD.z * 0.39;
	VERTEX.x += sin(TIME * 0.85 + phase + VERTEX.y * 0.6) * wind_amount * anchor_weight;
	VERTEX.z += cos(TIME * 0.65 + phase) * wind_amount * anchor_weight * 0.35;
}

void fragment() {
	vec4 color = texture(atlas, UV);
	// 去背景留下的品红边缘只影响透明裁切，不改变叶片的原生 RGB。
	if (color.r > color.g * 1.6 && color.b > color.g * 1.6 && color.r > 0.25) {
		discard;
	}
	ALBEDO = color.rgb;
	ALPHA = color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
}
