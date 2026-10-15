shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, ambient_light_disabled, specular_disabled, fog_disabled;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform float height = 20.0;
uniform float gain = 0.1;
uniform float beam_width = 7.0;
uniform sampler2D shaft_mask : repeat_disable, filter_linear;
uniform vec3 ray_right;
uniform vec3 ray_up;
instance uniform vec3 ray_origin = vec3(0.0);
varying float along;
varying vec3 source_view;
varying vec3 expected_direction;
varying vec3 world_position;

void vertex() {
	along = 0.5 - VERTEX.y / height;
	source_view = (VIEW_MATRIX * vec4(ray_origin, 1.0)).xyz;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	expected_direction = normalize(source_view - VERTEX);
	float facing = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.8);
	float ends = smoothstep(0.04, 0.22, along) * (1.0 - smoothstep(0.88, 1.0, along));
	float depth = textureLod(scene_depth, SCREEN_UV, 0.0).r;
	vec4 background = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float separation = -background.z / background.w + VERTEX.z;
	float contact = smoothstep(0.0, 0.25, separation);
	vec3 offset = world_position - ray_origin;
	float radius = max(0.08, beam_width * 1.25 * along);
	vec2 projected_uv = vec2(dot(offset, ray_right), dot(offset, ray_up)) / (radius * 2.0) + 0.5;
	float pattern = texture(shaft_mask, projected_uv).r;
	float ground_fade = smoothstep(0.5, 4.5, world_position.y);
	ALBEDO = vec3(1.0);
	ALPHA = facing * ends * contact * pattern * ground_fade;
}

void light() {
	// Only the matching distant light contributes. These helpers are entirely
	// outside the map and use depth testing to stay behind gameplay geometry.
	float matching_light = smoothstep(0.9995, 0.9999, dot(LIGHT, expected_direction));
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * matching_light * gain;
}
