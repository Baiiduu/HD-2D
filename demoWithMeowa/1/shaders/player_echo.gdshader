shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform sampler2D sprite_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 echo_color : source_color = vec4(0.38, 0.85, 0.95, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.45;
uniform bool fixed_y = true;
uniform float energy : hint_range(0.0, 1.0) = 0.35;

void vertex() {
	vec3 right = normalize(MAIN_CAM_INV_VIEW_MATRIX[0].xyz);
	vec3 up = normalize(MAIN_CAM_INV_VIEW_MATRIX[1].xyz);
	if (fixed_y) {
		right = normalize(vec3(right.x, 0.0, right.z));
		up = vec3(0.0, 1.0, 0.0);
	}
	vec3 facing = normalize(cross(right, up));
	mat4 card = mat4(vec4(right * length(MODEL_MATRIX[0].xyz), 0.0),
		vec4(up * length(MODEL_MATRIX[1].xyz), 0.0),
		vec4(facing * length(MODEL_MATRIX[2].xyz), 0.0), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * card;
}

void fragment() {
	vec4 source = texture(sprite_texture, UV);
	ALBEDO = mix(source.rgb, echo_color.rgb, 0.7);
	vec2 pixel = 1.0 / vec2(textureSize(sprite_texture, 0));
	float inner = min(min(texture(sprite_texture, UV + vec2(pixel.x, 0.0)).a,
		texture(sprite_texture, UV - vec2(pixel.x, 0.0)).a),
		min(texture(sprite_texture, UV + vec2(0.0, pixel.y)).a, texture(sprite_texture, UV - vec2(0.0, pixel.y)).a));
	EMISSION = echo_color.rgb * energy * (0.35 + (1.0 - inner) * 0.65);
	ALPHA = source.a * opacity * echo_color.a;
}
