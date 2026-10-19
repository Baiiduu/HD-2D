shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;

// Meowa 灰度雾絮原图直接作为连续透明度，不做二值抠图或再次像素化。
uniform sampler2D mist_texture : filter_linear, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec4 mist_color : source_color = vec4(0.60, 0.64, 0.69, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.0;
uniform float flow_time = 0.0;
uniform float reveal_progress = 0.0;
uniform float curl_strength = 1.0;
instance uniform vec2 flip = vec2(1.0);
instance uniform float phase = 0.0;

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
	float depth = texture(scene_depth, SCREEN_UV).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
	#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	#endif
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float behind = -view.z / max(view.w, 0.00001);
	float soft_intersection = smoothstep(0.0, 1.5, behind + VERTEX.z);
	float near_fade = smoothstep(0.5, 4.0, -VERTEX.z);
	ALBEDO = mist_color.rgb * mix(0.62, 1.3, mask);
	float facing = smoothstep(0.18, 0.55, abs(dot(NORMAL, VIEW)));
	ALPHA = (1.0 - exp(-mask * 2.6)) * border.x * border.y * opacity * soft_intersection * near_fade * facing * 0.35;
}
