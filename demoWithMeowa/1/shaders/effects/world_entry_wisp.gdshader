shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;

// Meowa 灰度雾絮原图直接作为连续透明度，不做二值抠图或再次像素化。
uniform sampler2D mist_texture : filter_linear, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D scene_light : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec4 mist_color : source_color = vec4(0.60, 0.64, 0.69, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.0;
uniform float flow_time = 0.0;
uniform float reveal_progress = 0.0;
uniform float curl_strength = 1.0;
uniform float light_response = 0.0;
uniform float light_threshold = 0.55;
uniform float depth_bulge = 0.0;
instance uniform vec2 flip = vec2(1.0);
instance uniform float phase = 0.0;

void vertex() {
	vec2 centered = (UV - vec2(0.5)) * 2.0;
	VERTEX.z += (1.0 - dot(centered, centered) * 0.5) * depth_bulge;
	NORMAL = normalize(vec3(centered * depth_bulge / 8.0, 1.0));
}

float view_depth(vec2 uv, mat4 inverse_projection) {
	float depth = texture(scene_depth, uv).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;
	#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
	#endif
	vec4 view = inverse_projection * vec4(ndc, 1.0);
	return -view.z / max(view.w, 0.00001);
}

void fragment() {
	vec2 uv = (UV - vec2(0.5)) * flip + vec2(0.5);
	vec2 centered = uv - vec2(0.5);
	float turn = (sin(length(centered) * 12.0 - flow_time * 1.2 + phase) * 0.18
		+ reveal_progress * 0.65) * curl_strength;
	uv = mat2(vec2(cos(turn), sin(turn)), vec2(-sin(turn), cos(turn))) * centered + vec2(0.5);
	uv += vec2(sin(uv.y * 10.0 + flow_time * 0.9 + phase), cos(uv.x * 9.0 - flow_time * 0.7 + phase)) * 0.045 * curl_strength;
	float mask = texture(mist_texture, uv).r;
	vec2 border = smoothstep(vec2(0.0), vec2(0.08), UV)
		* (vec2(1.0) - smoothstep(vec2(0.92), vec2(1.0), UV));
	float behind = view_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float soft_intersection = smoothstep(0.0, 1.5, behind + VERTEX.z);
	float near_fade = smoothstep(0.5, 4.0, -VERTEX.z);
	ALBEDO = mist_color.rgb * mix(0.62, 1.3, mask);
	float light_mask = 0.0;
	if (light_response > 0.0 && behind < 96.0) {
		// 只借用已通过遮挡与雾积分的可见亮部及其原色；不生成灯点或透墙光源。
		vec3 light = textureLod(scene_light, SCREEN_UV, 1.0).rgb * 0.75
			+ textureLod(scene_light, SCREEN_UV, 3.0).rgb * 0.25;
		light_mask = smoothstep(light_threshold, light_threshold * 2.0, max(light.r, max(light.g, light.b)));
		ALBEDO += light * light_mask * light_response;
	}
	float facing = smoothstep(0.18, 0.55, abs(dot(NORMAL, VIEW)));
	ALPHA = (1.0 - exp(-mask * 2.6)) * border.x * border.y * opacity * soft_intersection * near_fade * facing * 0.35
		* (1.0 - light_mask * light_response * 0.45);
}
