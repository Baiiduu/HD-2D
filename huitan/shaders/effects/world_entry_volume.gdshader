shader_type fog;

uniform vec4 fog_color : source_color = vec4(0.60, 0.64, 0.69, 1.0);
// 32³ 连续噪声切片，带一像素护边；两次采样完成三维插值，不在每个体素反复计算 FBM。
uniform sampler2D noise_atlas : filter_linear, repeat_disable;
uniform float density = 0.16;
uniform float flow_time = 0.0;
uniform bool box_volume = false;
uniform float coverage_floor = 0.0;
uniform vec3 reveal_origin = vec3(0.0);
uniform float reveal_progress = 0.0;
uniform float retreat_distance = 42.0;
uniform float curl_strength = 1.0;
uniform float self_emission = 2.0;
uniform vec3 noise_offset = vec3(0.0);

float noise_slice(vec2 p, float slice) {
	vec2 tile = vec2(mod(slice, 8.0), floor(slice / 8.0));
	return textureLod(noise_atlas, (tile * 34.0 + vec2(1.5) + p * 31.0) / vec2(272.0, 136.0), 0.0).r;
}

float cloud_noise(vec3 p) {
	vec3 uv = fract(p);
	float slice = uv.z * 31.0;
	float low = floor(slice);
	return mix(noise_slice(uv.xy, low), noise_slice(uv.xy, min(low + 1.0, 31.0)), fract(slice));
}

void fog() {
	vec3 relative = WORLD_POSITION - reveal_origin;
	float radial = length(relative.xz);
	vec2 outward = relative.xz / max(radial, 0.01);
	float retreat = reveal_progress * retreat_distance;
	// 回溯向外输运的密度场，滚轴在开口前沿形成翻卷，而非统一减淡。
	vec2 roll = vec2(radial - retreat, relative.y - 5.0);
	float vortex = curl_strength * (sin(radial * 0.32 - flow_time * 1.2) * 0.22
		+ reveal_progress * 2.4 * exp(-abs(radial - retreat) * 0.08));
	roll = mat2(vec2(cos(vortex), sin(vortex)), vec2(-sin(vortex), cos(vortex))) * roll;
	vec3 transported = vec3(outward.x * roll.x, roll.y + 5.0, outward.y * roll.x) + reveal_origin;
	vec3 p = transported * 0.14 + noise_offset + vec3(flow_time * 0.11, -flow_time * 0.05, -flow_time * 0.08);
	float billows = cloud_noise(p);
	float detail = cloud_noise(p * 2.1 + vec3(0.23, 0.51, 0.17));
	float cloud = smoothstep(0.34, 0.66, billows * 0.7 + detail * 0.3);
	vec3 local_edge = abs((UVW - vec3(0.5)) * 2.0);
	float edge = box_volume ? max(max(local_edge.x, local_edge.y), local_edge.z) : length(local_edge);
	float envelope = 1.0 - smoothstep(box_volume ? 0.72 : 0.35, 1.0, edge);
	// 从人物附近逐步向外散开；移动阶段保持完整云层，不提前挖空地图。
	float opening = retreat + (billows - 0.5) * 9.0;
	float remaining = mix(1.0, smoothstep(opening - 5.0, opening + 5.0, radial), smoothstep(0.0, 0.12, reveal_progress));
	float billow_density = mix(coverage_floor, 1.0, cloud) * envelope * remaining;
	DENSITY = density * billow_density;
	ALBEDO = fog_color.rgb * mix(0.76, 1.05, billows);
	// 引擎会将 EMISSION 乘入本体密度；此处只给云体颜色，避免重复衰减后只剩蓝黑背景。
	EMISSION = fog_color.rgb * mix(0.65, 1.0, billows) * self_emission * (box_volume ? 0.45 : 1.0);
}
