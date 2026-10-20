// 地面与火星采样同一笔触、空间相位和爆发，避免火星从空白地面冒出。
uniform float flow_strength = 0.0;
uniform float flow_speed = 2.2;
uniform sampler2D fire_brush : filter_nearest_mipmap, repeat_disable;
uniform vec4 brush_region = vec4(0.0201823, 0.3506944, 0.9544271, 0.2986111);

float fire_brush_mask(vec2 uv) {
	if (uv.y < 0.0 || uv.y > 1.0) { return 0.0; }
	return texture(fire_brush, brush_region.xy + vec2(fract(uv.x), uv.y) * brush_region.zw).r;
}

// x 笔触覆盖，y 短促爆发，z 侵蚀噪声；全部使用调用者提供的战斗时间。
vec3 fire_flow_pattern(vec2 p, vec2 forward, float width, float across, float visual_clock) {
	float clock = visual_clock * flow_speed / 2.2;
	float local_seed = fire_noise(p * 2.3 + vec2(3.7, 11.3));
	float period = 0.26 + local_seed * 0.4;
	float cycle = floor(clock / period + local_seed * 7.0);
	float phase = fract(clock / period + local_seed * 7.0);
	float pulse = smoothstep(0.0, 0.08, phase) * (1.0 - smoothstep(0.18, 0.40, phase));
	float snap = fire_hash(floor(p * 2.3) + vec2(cycle, cycle * 0.37));
	pulse *= 0.45 + snap * 0.55;
	float longitudinal = dot(p, forward);
	float lane = across / max(width, 0.001) + 0.5;
	vec2 field = vec2(longitudinal * 3.0, lane * 3.2);
	float curl = fire_noise(field + vec2(clock * 2.1, -clock * 1.4)) - 0.5;
	float tear = fire_noise(field * 1.7 + vec2(-clock * 3.7, local_seed * 5.0));
	float u = longitudinal / max(width * 3.5, 0.2);
	u += (curl * 0.16 + pulse * 0.15) * flow_strength;
	float v = lane + curl * (0.08 + pulse * 0.18) * flow_strength;
	float main_stroke = fire_brush_mask(vec2(u - clock * 0.16, v));
	float split_stroke = fire_brush_mask(vec2(u * 1.13 + 0.43 + clock * 0.09, 1.0 - v + curl * 0.12));
	return vec3(max(main_stroke, split_stroke * (0.3 + pulse * 0.25)), pulse, tear);
}
