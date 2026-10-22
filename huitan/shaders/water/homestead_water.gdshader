shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

#include "res://shaders/includes/rain_surface.gdshaderinc"
#include "res://shaders/includes/water_foam.gdshaderinc"

uniform vec4 shallow_color : source_color = vec4(0.26, 0.46, 0.5, 1.0);
uniform vec4 deep_color : source_color = vec4(0.1, 0.25, 0.3, 1.0);
uniform vec2 pond_scale = vec2(3.4, 2.5);
uniform float edge_softness = 0.075;
uniform vec4 foam_color : source_color = vec4(0.78, 0.85, 0.85, 1.0);
uniform float foam_scale = 1.0;
uniform float foam_density = 0.55;
uniform float foam_motion = 0.08;
uniform float bank_foam_width = 0.14;
uniform float foam_strength = 0.8;
uniform float wave_strength = 0.08;
uniform float highlight_strength = 1.0;
uniform float highlight_roughness = 0.22;
uniform float glint_strength = 0.8;
uniform float opacity = 0.86;
uniform float reflection_strength = 0.85;
uniform sampler2D reflection_texture_0 : filter_linear, repeat_disable;
uniform sampler2D reflection_texture_1 : filter_linear, repeat_disable;
uniform mat4 reflection_matrix_0;
uniform mat4 reflection_matrix_1;
uniform vec2 reflection_heights;
uniform bool reflection_enabled_0 = false;
uniform bool reflection_enabled_1 = false;

group_uniforms rain;
uniform float rain_amount = 0.0;
uniform float rain_clock = 0.0;
uniform float rain_density = 1.8;
uniform float rain_radius = 0.28;
uniform float rain_lifetime = 0.8;
uniform float rain_strength = 0.35;
group_uniforms;

varying vec3 world_position;
varying vec3 surface_normal;
varying float clear_water;

void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	vec2 point = world_position.xz;
	float radius = length((UV - 0.5) * 2.0);
	float bank = smoothstep(1.0 - edge_softness, 1.0, radius);
	float wave = sin(point.x * 14.0 + point.y * 7.0 + TIME * 1.1);
	float cross_wave = sin(point.y * 23.0 - point.x * 4.0 - TIME * 0.8);
	vec4 rain = rain_surface(point, rain_clock, rain_density * rain_amount, rain_radius, rain_lifetime) * rain_amount * rain_strength;
	vec2 ripples = vec2(wave, cross_wave) * wave_strength + rain.yz * 0.5;
	NORMAL = normalize(mat3(VIEW_MATRIX) * normalize(vec3(ripples.x, 1.0, ripples.y)));
	surface_normal = normalize(mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0));
	float patches = foam_patches(point, TIME, foam_scale, foam_density, vec2(0.0, foam_motion));
	float bank_distance = (1.0 - radius) * min(pond_scale.x, pond_scale.y);
	float foam = (1.0 - smoothstep(0.015, bank_foam_width, bank_distance)) * (0.12 + patches * 0.88) * foam_strength;
	clear_water = 1.0 - foam;
	vec3 color = mix(deep_color.rgb, shallow_color.rgb, smoothstep(0.3, 1.0, radius));
	color = mix(color, foam_color.rgb, clamp(foam + rain.x * 0.55 + rain.w * 0.3, 0.0, 1.0));
	ROUGHNESS = mix(0.12, 0.75, max(foam, bank));
	SPECULAR = 0.5;
	float fresnel = 0.04 + 0.96 * pow(1.0 - clamp(normalize(CAMERA_POSITION_WORLD - world_position).y, 0.0, 1.0), 5.0);
	bool upper = abs(world_position.y - reflection_heights.y) < abs(world_position.y - reflection_heights.x);
	bool enabled = upper ? reflection_enabled_1 : reflection_enabled_0;
	vec3 reflection = vec3(0.0);
	float reflectivity = 0.0;
	if (enabled) {
		vec4 projected = (upper ? reflection_matrix_1 : reflection_matrix_0) * vec4(world_position, 1.0);
		vec2 projected_uv = projected.xy / max(projected.w, 0.0001) * 0.5 + 0.5;
		projected_uv.y = 1.0 - projected_uv.y;
		vec2 scene_wave = vec2(sin(point.y * 2.7 + TIME * 0.8), cos(point.x * 2.1 - TIME * 0.6)) * wave_strength;
		vec2 scene_uv = projected_uv + scene_wave * vec2(0.016, 0.010) + rain.yz * vec2(0.008, 0.005);
		vec2 light_uv = projected_uv + ripples * vec2(0.024, 0.016);
		float edge = smoothstep(0.0, 0.025, min(min(scene_uv.x, scene_uv.y), min(1.0 - scene_uv.x, 1.0 - scene_uv.y)));
		if (projected.w > 0.0) {
			vec3 scene_reflection = upper ? texture(reflection_texture_1, clamp(scene_uv, vec2(0.001), vec2(0.999))).rgb : texture(reflection_texture_0, clamp(scene_uv, vec2(0.001), vec2(0.999))).rgb;
			vec3 light_reflection = upper ? texture(reflection_texture_1, clamp(light_uv, vec2(0.001), vec2(0.999))).rgb : texture(reflection_texture_0, clamp(light_uv, vec2(0.001), vec2(0.999))).rgb;
			reflection = min(scene_reflection, vec3(1.0)) + max(light_reflection - vec3(1.0), vec3(0.0));
			reflectivity = clamp(mix(fresnel, 1.0, 0.22) * reflection_strength * clear_water * edge, 0.0, 0.95);
		}
	}
	ALBEDO = color * (1.0 - reflectivity);
	EMISSION = reflection * reflectivity;
	ALPHA = mix(mix(opacity, 0.98, reflectivity), 0.96, foam);
}

// 与预览水面共用的 GGX 高光响应：柔和光斑与细碎波纹高光分别调节。
float water_specular(vec3 normal, vec3 light, vec3 view, float roughness) {
	vec3 half_vector = normalize(light + view);
	float nl = max(dot(normal, light), 0.0);
	float nv = max(dot(normal, view), 0.001);
	float nh = max(dot(normal, half_vector), 0.0);
	float vh = max(dot(view, half_vector), 0.0);
	float a = max(roughness * roughness, 0.004);
	float a2 = a * a;
	float denominator = 1.0 - nh * nh + nh * nh * a2;
	float distribution = a2 / max(PI * denominator * denominator, 0.00000001);
	float visibility = 0.5 / max(nl * sqrt(nv * nv * (1.0 - a2) + a2) + nv * sqrt(nl * nl * (1.0 - a2) + a2), 0.0001);
	float fresnel = 0.04 + 0.96 * pow(1.0 - vh, 5.0);
	return distribution * visibility * fresnel * nl;
}

void light() {
	DIFFUSE_LIGHT += max(dot(NORMAL, LIGHT), 0.0) * ATTENUATION * LIGHT_COLOR / PI;
	float pool = water_specular(surface_normal, LIGHT, VIEW, highlight_roughness);
	float glints = water_specular(NORMAL, LIGHT, VIEW, 0.13) * glint_strength;
	float foam_specular = water_specular(NORMAL, LIGHT, VIEW, 0.75) * (1.0 - clear_water);
	SPECULAR_LIGHT += ((pool * 0.2 + glints) * clear_water + foam_specular) * highlight_strength * SPECULAR_AMOUNT * ATTENUATION * LIGHT_COLOR;
}
