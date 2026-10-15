shader_type spatial;
render_mode diffuse_burley;

#include "res://shaders/includes/rain_surface.gdshaderinc"

uniform sampler2D grass_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D stone_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float texture_scale = 1.65;
uniform float meadow_variation = 0.17;
uniform vec4 grass_tint : source_color = vec4(0.86, 0.94, 0.82, 1.0);
uniform vec4 path_color : source_color = vec4(0.54, 0.48, 0.36, 1.0);
uniform float path_detail = 0.4;

group_uniforms surface_lighting;
uniform float wetness = 0.6;
uniform float wet_darkening = 0.65;
uniform float wet_roughness = 0.16;
uniform float stone_relief = 0.006;
uniform float stone_gloss_variation = 0.55;
uniform bool grass_lighting_enabled = true;
uniform float grass_relief = 0.008;
uniform float grass_wet_response = 0.2;
uniform float grass_sheen = 0.35;
uniform float grass_root_occlusion = 0.0;
uniform sampler2D grass_root_map : filter_linear, repeat_disable;
uniform vec4 grass_root_bounds = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool puddles = false;
uniform float puddle_threshold = 0.6;
group_uniforms rain;
uniform float rain_amount = 0.0;
uniform float rain_clock = 0.0;
uniform float rain_density = 0.9;
uniform float rain_radius = 0.11;
uniform float rain_strength = 0.32;
uniform float weather_wetness = 0.0;
group_uniforms;
varying vec3 world_position;

float hash(vec2 point) { return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 point) {
	vec2 cell = floor(point), blend = fract(point);
	blend = blend * blend * (3.0 - 2.0 * blend);
	return mix(mix(hash(cell), hash(cell + vec2(1, 0)), blend.x), mix(hash(cell + vec2(0, 1)), hash(cell + vec2(1)), blend.x), blend.y);
}

void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1)).xyz; }

vec3 pixel_sample(sampler2D material, vec2 uv) {
	vec2 pixel = uv * 64.0;
	vec2 seam = floor(pixel + 0.5);
	vec2 width = max(fwidth(pixel), vec2(0.0001));
	vec2 filtered = (seam + clamp((pixel - seam) / width, vec2(-0.5), vec2(0.5))) / 64.0;
	return textureGrad(material, filtered, dFdx(uv), dFdy(uv)).rgb;
}

void fragment() {
	vec2 point = world_position.xz;
	vec2 uv = UV / texture_scale;
	float macro = noise(point * 0.32) * 0.65 + noise(point * 0.1 + 8.0) * 0.35;
	vec3 grass = pixel_sample(grass_texture, uv) * grass_tint.rgb;
	grass *= 1.0 + (macro - 0.5) * meadow_variation * 2.0;
	grass = mix(grass, grass * vec3(1.08, 1.02, 0.86), smoothstep(0.62, 0.85, macro) * 0.45);
	vec3 dirt = mix(path_color.rgb, pixel_sample(dirt_texture, uv * 1.12), path_detail);
	vec3 stone = pixel_sample(stone_texture, uv * 0.82) * vec3(1.05, 1.03, 0.94);
	float granular = (noise(floor(point * 20.0)) - 0.5) * 0.16;
	float path = clamp(COLOR.r + granular * 4.0 * COLOR.r * (1.0 - COLOR.r), 0.0, 1.0);
	vec3 color = mix(grass, dirt, path);
	color = mix(color, stone, COLOR.g);
	float furrows = 0.92 + sin(point.y * 12.0) * 0.08;
	color = mix(color, dirt * vec3(0.64, 0.59, 0.53) * furrows, COLOR.b);
	// A restrained broad shade keeps repeated material from reading as a flat sheet.
	float cloud = smoothstep(0.48, 0.8, noise(point * 0.055 + vec2(TIME * 0.002, 0.0)));
	color *= 1.0 - cloud * 0.07;
	float grass_weight = (1.0 - path) * (1.0 - COLOR.g) * (1.0 - COLOR.b);
	float lit_grass = grass_lighting_enabled ? grass_weight : 0.0;
	float response = mix(0.6, 1.0, COLOR.g);
	response = mix(response, grass_wet_response, lit_grass);
	float wet = response * clamp(wetness + weather_wetness, 0.0, 1.0);
	float roughness = mix(mix(0.96, 0.79, COLOR.g), mix(wet_roughness, 0.62, lit_grass), wet);
	float damp_patch = smoothstep(1.0 - grass_sheen, 1.1 - grass_sheen, noise(point * 1.9 + vec2(11.3, 7.1)));
	roughness = mix(roughness, 0.22, lit_grass * damp_patch * smoothstep(0.015, 0.1, wet));
	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	float stone_face = smoothstep(0.1, 0.45, luma);
	roughness = mix(roughness, mix(0.82, 0.2 + noise(point * 2.1) * 0.16, stone_face), stone_gloss_variation * wet * COLOR.g);
	float relief = stone_relief * COLOR.g + grass_relief * lit_grass;
	vec3 dpdx = dFdx(VERTEX), dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL), r2 = cross(NORMAL, dpdx);
	float determinant = dot(dpdx, r1);
	if (abs(determinant) > 0.000001 && relief > 0.0) {
		vec3 gradient = (r1 * dFdx(luma) + r2 * dFdy(luma)) * relief / determinant;
		gradient /= max(1.0, length(gradient) / 0.22);
		NORMAL = normalize(NORMAL - gradient);
	}
	color *= mix(1.0, wet_darkening, wet);
	if (lit_grass > 0.0 && grass_root_occlusion > 0.0) {
		vec2 root_uv = (point - grass_root_bounds.xy) / grass_root_bounds.zw;
		float roots = texture(grass_root_map, root_uv).r * grass_root_occlusion * lit_grass;
		color *= 1.0 - roots * 0.3;
		AO = 1.0 - roots;
		AO_LIGHT_AFFECT = 0.2;
	}
	if (puddles && wet > 0.5 && noise(point * 0.45) * 0.7 + noise(point * 1.7 + 7.3) * 0.3 > puddle_threshold) {
		color *= 0.45;
		roughness = 0.02;
	}
	vec4 rain = rain_surface(point, rain_clock, rain_density * rain_amount, rain_radius, 0.38);
	float splash = clamp((rain.x * 0.65 + rain.w) * rain_strength * rain_amount * mix(0.3, 1.0, response), 0.0, 0.5);
	ALBEDO = mix(color, vec3(0.62, 0.71, 0.77), splash);
	ROUGHNESS = roughness;
	SPECULAR = 0.2;
}
