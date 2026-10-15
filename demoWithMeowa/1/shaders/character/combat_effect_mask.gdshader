shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;
stencil_mode write, 1;

uniform sampler2D sprite_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform float opacity = 1.0;
uniform bool fixed_y = true;

void vertex() {
	// 与主体使用相同的 Sprite 网格、UV、billboard 和缩放，保留原生透明轮廓。
	mat4 camera = MAIN_CAM_INV_VIEW_MATRIX;
	vec3 right = normalize(camera[0].xyz);
	vec3 up = normalize(camera[1].xyz);
	if (fixed_y) {
		right = normalize(vec3(right.x, 0.0, right.z));
		up = vec3(0.0, 1.0, 0.0);
	}
	vec3 facing = normalize(cross(right, up));
	mat4 billboard = mat4(vec4(right * length(MODEL_MATRIX[0].xyz), 0.0),
		vec4(up * length(MODEL_MATRIX[1].xyz), 0.0),
		vec4(facing * length(MODEL_MATRIX[2].xyz), 0.0), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
}

void fragment() {
	if (texture(sprite_texture, UV).a * opacity < 0.5) { discard; }
	// 只标记当前真正可见的怪物；墙后、另一只怪物后和透明留白不写遮罩。
	float depth = texture(scene_depth, SCREEN_UV).r;
	if (depth > FRAGCOORD.z + 0.0000001) { discard; }
	ALBEDO = vec3(0.0);
	ALPHA = 0.0;
}
