shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D spark_texture : source_color, filter_nearest, repeat_disable;
uniform float debris_clock = 0.0;
uniform bool hurt_pixels = false;
varying float life_progress;

void vertex() {
	float age = max(0.0, debris_clock - INSTANCE_CUSTOM.w);
	life_progress = age / max(COLOR.a, 0.001);
	// 出生时只写一次速度与起点；重力抛物线在 GPU 求值，不逐粒更新节点。
	vec3 flight = INSTANCE_CUSTOM.xyz * age + vec3(0.0, -(hurt_pixels ? 1.4 : 5.5) * age * age, 0.0);
	float angle = dot(INSTANCE_CUSTOM.xyz, vec3(1.7, 0.9, 2.3)) + age * 7.0;
	if (hurt_pixels) angle = 0.0;
	VERTEX.xy = mat2(vec2(cos(angle), sin(angle)), vec2(-sin(angle), cos(angle))) * VERTEX.xy;
	mat4 billboard = MODEL_MATRIX;
	billboard[0].xyz = INV_VIEW_MATRIX[0].xyz * length(MODEL_MATRIX[0].xyz);
	billboard[1].xyz = INV_VIEW_MATRIX[1].xyz * length(MODEL_MATRIX[1].xyz);
	billboard[2].xyz = INV_VIEW_MATRIX[2].xyz * length(MODEL_MATRIX[2].xyz);
	billboard[3].xyz += flight;
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
}

void fragment() {
	if (life_progress >= 1.0) discard;
	// 直接采样已有 Meowa 图集中心的 6×6 原生白金碎屑。
	vec4 pixel = hurt_pixels ? vec4(1.0) : texture(spark_texture, (vec2(16.0, 21.0) + UV * 6.0) / vec2(168.0, 96.0));
	ALBEDO = pixel.rgb * COLOR.rgb;
	EMISSION = ALBEDO * (hurt_pixels ? 0.0 : 0.6);
	ALPHA = pixel.a * (1.0 - smoothstep(0.5, 1.0, life_progress));
}
