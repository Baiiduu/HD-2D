shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;
#include "res://shaders/includes/character_motion.gdshaderinc"
instance uniform vec3 motion_lean = vec3(0.0);
instance uniform vec3 motion_pivot = vec3(0.0);

// Draw only the hidden silhouette edge; leave the character and scene depth intact.
uniform sampler2D sprite_texture : filter_nearest, repeat_disable;
// Frame bounds in the underlying texture; direct PNG textures use the entire image.
uniform vec4 sprite_region = vec4(0.0, 0.0, 1.0, 1.0);
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec4 outline_color : source_color = vec4(1.0, 0.89, 0.55, 1.0);
uniform float outline_width = 1.0;
uniform float outline_opacity = 0.85;
uniform float depth_bias = 0.03;
uniform float sprite_opacity = 1.0;
uniform bool fixed_y = true;
uniform bool flip_h = false;
uniform bool flip_v = false;

void vertex() {
	vec3 right = normalize(MAIN_CAM_INV_VIEW_MATRIX[0].xyz);
	vec3 up = normalize(MAIN_CAM_INV_VIEW_MATRIX[1].xyz);
	if (fixed_y) {
		right = normalize(vec3(right.x, 0.0, right.z));
		up = vec3(0.0, 1.0, 0.0);
	}
	vec3 facing = normalize(cross(right, up));
	mat4 billboard = mat4(vec4(right * length(MODEL_MATRIX[0].xyz), 0.0),
		vec4(up * length(MODEL_MATRIX[1].xyz), 0.0),
		vec4(facing * length(MODEL_MATRIX[2].xyz), 0.0), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * character_motion_card(billboard, motion_pivot, motion_lean);
}

float coverage(vec2 uv) {
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) { return 0.0; }
	return step(0.5, texture(sprite_texture, sprite_region.xy + uv * sprite_region.zw).a * sprite_opacity);
}

void fragment() {
	float depth = texture(scene_depth, SCREEN_UV).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
	#else
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
	#endif
	vec4 surface = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	float surface_distance = -surface.z / surface.w;
	float character_distance = -VERTEX.z;
	if (character_distance <= surface_distance + depth_bias || outline_width <= 0.0) { discard; }
	vec2 uv = vec2(flip_h ? 1.0 - UV.x : UV.x, flip_v ? 1.0 - UV.y : UV.y);
	float center = coverage(uv);
	if (center < 0.5) { discard; }
	vec2 pixel = outline_width / (vec2(textureSize(sprite_texture, 0)) * sprite_region.zw);
	float inside = 1.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			if (x == 0 && y == 0) { continue; }
			inside = min(inside, coverage(uv + vec2(float(x), float(y)) * pixel));
		}
	}
	if (inside > 0.5) { discard; }
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a * outline_opacity;
}
