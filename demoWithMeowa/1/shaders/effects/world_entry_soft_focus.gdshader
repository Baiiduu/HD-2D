shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled, shadows_disabled;

uniform sampler2D scene_color : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform float blur_radius_pixels = 2.5;
uniform float blur_strength = 0.4;
uniform float fog_weight = 0.0;
uniform vec3 reveal_origin = vec3(0.0);
uniform float clear_radius = 0.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

vec3 view_position(vec2 uv, mat4 inverse_projection) {
	float depth = texture(scene_depth, uv).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, depth) * 2.0 - 1.0;
	#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
	#endif
	vec4 view = inverse_projection * vec4(ndc, 1.0);
	return view.xyz / max(view.w, 0.00001);
}

void fragment() {
	vec3 view = view_position(SCREEN_UV, INV_PROJECTION_MATRIX);
	float depth = -view.z;
	vec2 pixel = blur_radius_pixels / vec2(textureSize(scene_depth, 0));
	float gap = max(abs(-view_position(SCREEN_UV + vec2(pixel.x, 0.0), INV_PROJECTION_MATRIX).z - depth), abs(-view_position(SCREEN_UV - vec2(pixel.x, 0.0), INV_PROJECTION_MATRIX).z - depth));
	gap = max(gap, max(abs(-view_position(SCREEN_UV + vec2(0.0, pixel.y), INV_PROJECTION_MATRIX).z - depth), abs(-view_position(SCREEN_UV - vec2(0.0, pixel.y), INV_PROJECTION_MATRIX).z - depth)));
	float threshold = max(0.3, depth * 0.035);
	float edge = smoothstep(threshold, threshold * 3.0, gap);
	vec3 world = (INV_VIEW_MATRIX * vec4(view, 1.0)).xyz;
	float remaining = clear_radius > 0.0 ? smoothstep(clear_radius - 5.0, clear_radius + 5.0, length(world.xz - reveal_origin.xz)) : 1.0;
	float amount = edge * blur_strength * fog_weight * remaining;
	if (amount <= 0.0001) {
		discard;
	}
	// 只对真实轮廓两侧的画面颜色做归一化 Gaussian 卷积，不叠加轮廓色。
	vec3 soft_scene = textureLod(scene_color, SCREEN_UV, 0.0).rgb * 0.25;
	soft_scene += (textureLod(scene_color, SCREEN_UV + vec2(pixel.x, 0.0), 0.0).rgb
		+ textureLod(scene_color, SCREEN_UV - vec2(pixel.x, 0.0), 0.0).rgb
		+ textureLod(scene_color, SCREEN_UV + vec2(0.0, pixel.y), 0.0).rgb
		+ textureLod(scene_color, SCREEN_UV - vec2(0.0, pixel.y), 0.0).rgb) * 0.125;
	soft_scene += (textureLod(scene_color, SCREEN_UV + pixel, 0.0).rgb
		+ textureLod(scene_color, SCREEN_UV - pixel, 0.0).rgb
		+ textureLod(scene_color, SCREEN_UV + vec2(pixel.x, -pixel.y), 0.0).rgb
		+ textureLod(scene_color, SCREEN_UV + vec2(-pixel.x, pixel.y), 0.0).rgb) * 0.0625;
	ALBEDO = soft_scene;
	ALPHA = amount;
}
