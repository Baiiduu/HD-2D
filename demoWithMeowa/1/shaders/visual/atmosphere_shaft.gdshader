shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, skip_vertex_transform;

#include "res://shaders/visual/atmosphere_common.gdshaderinc"
uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
uniform vec3 light_direction = vec3(0.4, 0.8, 0.3);
uniform vec4 light_color : source_color = vec4(0.65, 0.76, 1.0, 1.0);
uniform float energy = 0.15;
uniform vec2 near_fade = vec2(3.0, 10.0);
instance uniform float shaft_length = 12.0;
instance uniform float shaft_width = 2.0;
instance uniform float shaft_top_width = 0.6;
instance uniform float shaft_seed = 0.0;
varying vec3 shaft_world;
varying float axis_fade;
varying float ground_y;

void vertex() {
	vec3 axis = normalize(light_direction);
	vec3 base = MODEL_MATRIX[3].xyz;
	float along = 1.0 - UV.y;
	vec3 center = base + axis * along * shaft_length;
	vec3 view = normalize(CAMERA_POSITION_WORLD - center);
	vec3 side = normalize(cross(axis, view) + vec3(0.0001, 0.0, 0.0));
	float width = shaft_width * mix(1.0, shaft_top_width, along);
	shaft_world = center + side * (UV.x - 0.5) * width;
	ground_y = base.y;
	axis_fade = 1.0 - smoothstep(0.83, 0.98, abs(dot(axis, view)));
	VERTEX = (VIEW_MATRIX * vec4(shaft_world, 1.0)).xyz;
}

void fragment() {
	float x = (UV.x - 0.5) * 2.0;
	float along = 1.0 - UV.y;
	float edge = max(exp(-x * x * 4.0) - 0.018, 0.0);
	float ends = smoothstep(ground_y, ground_y + min(1.3, shaft_length * 0.2), shaft_world.y)
		* (1.0 - smoothstep(0.65, 1.0, along));
	float noise = atmosphere_noise(vec2(x * 4.0 + shaft_seed, along * 4.0 - atmosphere_clock * 0.18));
	float breathing = 0.86 + 0.14 * sin(atmosphere_clock * 0.36 + shaft_seed);
	float distance_fade = smoothstep(near_fade.x, near_fade.y, distance(CAMERA_POSITION_WORLD, shaft_world));
	vec4 background = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(scene_depth, SCREEN_UV).r, 1.0);
	float contact = smoothstep(0.0, 0.35, -background.z / background.w + VERTEX.z);
	float amount = edge * ends * axis_fade * distance_fade * contact * breathing * (0.4 + noise * 0.6);
	ALBEDO = light_color.rgb * energy * amount;
	ALPHA = 1.0;
}
