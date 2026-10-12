shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 rain_color : source_color = vec4(0.65, 0.76, 0.84, 0.24);
uniform vec2 slant = vec2(0.08, 0.02);

#include "res://shaders/blink_airflow.gdshaderinc"
uniform float blink_rain_radius = 1.1;
uniform float blink_rain_height = 1.3;
uniform float blink_rain_offset = 0.9;
uniform float blink_rain_strength = 0.22;
uniform float blink_rain_tilt = 0.8;
uniform float blink_rain_duration = 0.45;

void vertex() {
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), MAIN_CAM_INV_VIEW_MATRIX[2].xyz));
	vec3 forward = normalize(cross(MAIN_CAM_INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0)));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(forward, 0.0), MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	vec3 airflow = vec3(0.0);
	for (int index = 0; index < blink_path_count; index++) {
		float age = clamp(blink_path_starts[index].w / max(blink_rain_duration, 0.001), 0.0, 1.0);
		float response = smoothstep(0.0, 0.08, age) * (1.0 - smoothstep(0.08, 1.0, age));
		float influence = blink_path_weight(MODEL_MATRIX[3].xyz, index, blink_rain_radius, blink_rain_height, blink_rain_offset);
		airflow += blink_path_direction(index) * influence * response;
	}
	airflow /= max(1.0, length(airflow));
	vec3 rain_slant = vec3(slant.x, 0.0, slant.y) + airflow * blink_rain_tilt;
	vec3 displacement = airflow * blink_rain_strength;
	VERTEX.x += dot(displacement, right) - VERTEX.y * dot(rain_slant, right);
	VERTEX.z += dot(displacement, forward) - VERTEX.y * dot(rain_slant, forward);
}

void fragment() {
	float width = 1.0 - smoothstep(0.05, 0.5, abs(UV.x - 0.5));
	float tail = sin(UV.y * PI);
	float distance_fade = smoothstep(1.5, 3.0, length(VERTEX)) * (1.0 - smoothstep(18.0, 32.0, length(VERTEX)));
	ALBEDO = rain_color.rgb;
	ALPHA = rain_color.a * width * tail * distance_fade;
}
