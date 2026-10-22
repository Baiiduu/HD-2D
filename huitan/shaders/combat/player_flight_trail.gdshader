shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;
#include "res://shaders/includes/player_body_mask.gdshaderinc"
uniform vec3 echo_lean = vec3(0.0);
uniform vec3 echo_pivot = vec3(0.0);

uniform sampler2D sprite_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 source_tint : source_color = vec4(1.0);
uniform vec4 echo_color : source_color = vec4(1.0);
uniform float opacity = 0.16;
uniform float saturation = 0.25;
uniform float brightness = 0.65;
uniform float energy = 0.0;
uniform int billboard_mode = 2;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * character_motion_card(facing_card(MODEL_MATRIX, billboard_mode, MAIN_CAM_INV_VIEW_MATRIX), echo_pivot, echo_lean);
	mat4 body_view = VIEW_MATRIX * character_motion_card(facing_card(body_transform, body_billboard_mode, MAIN_CAM_INV_VIEW_MATRIX), body_motion_pivot, body_motion_lean);
	body_view_origin = (body_view * vec4(body_origin, 1.0)).xyz;
	body_view_u = (body_view * vec4(body_edge_u, 0.0)).xyz;
	body_view_v = (body_view * vec4(body_edge_v, 0.0)).xyz;
}

void fragment() {
	vec4 source = texture(sprite_texture, UV) * source_tint * echo_color;
	float luminance = dot(source.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 subdued = mix(vec3(luminance), source.rgb, saturation) * brightness;
	ALBEDO = subdued;
	EMISSION = subdued * energy;
	ALPHA = source.a * opacity;
	if (body_mask_enabled && ALPHA > 0.0) { ALPHA *= 1.0 - body_coverage(VERTEX, PROJECTION_MATRIX[3][3] > 0.5); }
}
