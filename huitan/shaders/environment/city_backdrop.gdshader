shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

// 固定世界布景，不参与场景照明，也不随人物或镜头转向。
uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform float panorama_offset : hint_range(0.0, 1.0) = 0.0;
uniform float brightness : hint_range(0.1, 2.0) = 0.85;

// 北侧保留完整城市与机甲，其余方向复用街区部分，避免四面出现相同机甲。
vec2 district_span(float sector) {
	if (sector < 0.5) return vec2(0.75, 1.0);
	if (sector < 1.5) return vec2(0.0, 0.50);
	if (sector < 2.5) return vec2(0.0, 1.0);
	return vec2(0.50, 0.02);
}

void fragment() {
	float around = fract(UV.x + panorama_offset + 0.125) * 4.0;
	float sector = floor(around);
	float local_u = fract(around);
	vec2 span = district_span(sector);
	// CylinderMesh 侧面的 V 只占 0～0.5，先还原完整高度，再压缩远景建筑高度。
	float height_uv = UV.y * 2.0;
	vec2 uv = vec2(mix(span.x, span.y, local_u), clamp(height_uv * 2.5, 0.0, 1.0));
	vec3 city = texture(panorama, uv).rgb;
	// 街区接缝两侧淡化到同一颜色，Q/E 跨越拼缝时连续。
	float seam = min(local_u, 1.0 - local_u);
	if (seam < 0.03) {
		bool start = local_u < 0.5;
		vec2 neighbor = district_span(mod(sector + (start ? 3.0 : 1.0), 4.0));
		vec3 a = texture(panorama, vec2(start ? span.x : span.y, uv.y)).rgb;
		vec3 b = texture(panorama, vec2(start ? neighbor.y : neighbor.x, uv.y)).rgb;
		city = mix((a + b) * 0.5, city, smoothstep(0.0, 0.03, seam));
	}
	ALBEDO = city * brightness;
	ALPHA = smoothstep(0.0, 0.035, uv.y) * (1.0 - smoothstep(0.94, 1.0, height_uv));
}
