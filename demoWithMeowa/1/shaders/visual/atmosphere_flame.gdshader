shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://shaders/visual/atmosphere_common.gdshaderinc"
uniform float energy = 3.0;
uniform float flame_seed = 0.0;

void vertex() {
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec3 center = MODEL_MATRIX[3].xyz;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right, 0.0), vec4(0.0, 1.0, 0.0, 0.0),
		vec4(normalize(cross(right, vec3(0.0, 1.0, 0.0))), 0.0), vec4(center, 1.0));
}

void fragment() {
	vec2 uv = (floor(UV * vec2(24.0, 32.0)) + 0.5) / vec2(24.0, 32.0);
	float y = 1.0 - uv.y;
	float x = (uv.x - 0.5) * 2.0;
	float time = atmosphere_clock;
	x += (atmosphere_noise(vec2(y * 4.0 - time * 1.7, time * 0.4 + flame_seed)) - 0.5) * y * 0.6;
	float width = pow(max(1.0 - y, 0.0), 0.7) * (0.8 + 0.2 * sin(time * 2.0 + y * 7.0));
	float heat = 1.0 - abs(x) / max(width, 0.01) + (atmosphere_noise(vec2(x * 5.0, y * 6.0 - time * 3.5)) - 0.5) * 0.7;
	if (heat < 0.15 || y < 0.03) discard;
	vec3 color = mix(vec3(1.0, 0.13, 0.015), vec3(1.0, 0.65, 0.06), smoothstep(0.2, 0.7, heat));
	color = mix(color, vec3(1.0, 0.91, 0.58), smoothstep(0.8, 1.15, heat) * (1.0 - y));
	ALBEDO = color * energy;
}
