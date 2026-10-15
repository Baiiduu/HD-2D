shader_type canvas_item;

void fragment() {
	vec4 paper = texture(TEXTURE, UV) * COLOR;
	vec2 edge = min(UV, vec2(1.0) - UV);
	float blend = smoothstep(0.0, 0.025, min(edge.x, edge.y));
	COLOR = vec4(paper.rgb, paper.a * blend);
}
