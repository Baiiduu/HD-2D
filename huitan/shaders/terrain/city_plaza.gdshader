shader_type spatial;

#include "res://shaders/includes/rain_surface.gdshaderinc"
#include "res://shaders/includes/lumina_surface.gdshaderinc"

uniform sampler2D stone_texture : source_color, filter_nearest, repeat_enable;
uniform sampler2D worn_texture : source_color, filter_nearest, repeat_enable;
uniform sampler2D strip_texture : source_color, filter_nearest, repeat_enable;
uniform sampler2D trim_texture : source_color, filter_nearest, repeat_enable;
uniform sampler2D octagon_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D arrow_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D inlay_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D marker_texture : source_color, filter_nearest, repeat_disable;
uniform sampler2D stone_normal : filter_nearest, repeat_enable;
uniform sampler2D strip_normal : filter_nearest, repeat_enable;
uniform sampler2D octagon_normal : filter_nearest, repeat_disable;

// Shared live data also lets the terrain painter replace this surface.
uniform sampler2D terrain_map : filter_nearest, repeat_disable;
uniform ivec2 map_origin = ivec2(0);
uniform float cell_size = 1.6;
uniform vec2 plaza_center = vec2(58.4, 44.0);
uniform vec2 plaza_half_size = vec2(19.2);
uniform float texture_meters = 2.4;
uniform float division_spacing = 6.4;
uniform float division_width = 0.5;
uniform float trim_width = 0.05;
uniform float octagon_size = 4.0;
uniform float wear_density = 0.07;
uniform float inlay_density = 0.025;
uniform int ornament_seed = 13102026;
uniform float normal_strength = 0.6;
uniform float roughness = 0.78;
uniform float wet_response = 0.8;
uniform float wetness = 0.4;
uniform float weather_wetness = 0.0;
uniform float rain_amount = 0.0;
uniform float rain_clock = 0.0;
uniform float rain_density = 0.9;
uniform float rain_radius = 0.11;
uniform float rain_strength = 0.32;

varying vec3 world_position;

float plaza_hash(vec2 p) {
	return fract(sin(dot(p + float(ornament_seed % 997), vec2(127.1, 311.7))) * 43758.5453);
}

float octagon_distance(vec2 p) {
	vec2 a = abs(p);
	return max(max(a.x, a.y), (a.x + a.y) * 0.70710678);
}

vec2 slope(vec3 encoded) {
	vec3 n = encoded * 2.0 - 1.0;
	return vec2(-n.x, n.y) / max(n.z, 0.25);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ivec2 cell = ivec2(round(world_position.xz / cell_size)) - map_origin;
	ivec4 data = ivec4(round(texelFetch(terrain_map, clamp(cell, ivec2(0), textureSize(terrain_map, 0) - 1), 0) * 255.0));
	// Grass, paths, custom brushes and changed heights show the real Terrain below.
	if (data.r != 0 || data.g != 0 || data.b != 8 || data.a != 0) { discard; }
	vec2 p = world_position.xz - plaza_center;
	vec2 uv = (p + vec2(texture_meters * 0.5)) / texture_meters;
	vec3 color = texture(stone_texture, uv).rgb;
	vec2 gradient = slope(texture(stone_normal, uv).rgb);
	float worn = plaza_hash(floor(uv));
	if (worn < wear_density) { color = texture(worn_texture, uv).rgb; }
	// The native sheet has different crop extents; place ornaments, never resize the PNGs.
	float small = texture_meters / 3.0;
	vec2 stone_cell = floor((p + vec2(texture_meters * 0.5)) / small);
	vec2 inlay_uv = fract((p + vec2(texture_meters * 0.5)) / small);
	if (plaza_hash(stone_cell + 179.0) < inlay_density) { color = texture(inlay_texture, inlay_uv).rgb; }
	bool in_plaza = all(lessThan(abs(p), plaza_half_size));
	vec2 signed_lines = mod(p, vec2(division_spacing)) - division_spacing * 0.5;
	vec2 lines = abs(signed_lines);
	float edge = min(plaza_half_size.x - abs(p.x), plaza_half_size.y - abs(p.y));
	float line_distance = min(min(lines.x, lines.y), max(edge, 0.0));
	if (!in_plaza) { line_distance = abs(p.y); }
	float half_band = division_width * 0.5;
	if (line_distance < half_band + trim_width) {
		bool vertical = in_plaza && lines.x < lines.y;
		vec2 band_uv = vertical ? vec2(0.5 + signed_lines.x / division_width, p.y / 1.55) : vec2(0.5 + (in_plaza ? signed_lines.y : p.y) / division_width, p.x / 1.55);
		color = texture(strip_texture, band_uv).rgb;
		gradient = slope(texture(strip_normal, band_uv).rgb);
		if (!vertical) { gradient = gradient.yx; }
		if (line_distance >= half_band) {
			color = texture(trim_texture, world_position.xz / 0.5).rgb;
			gradient = vec2(0.0);
		}
		// Pale diamonds at the middle of each division segment, not a luminous decal.
		vec2 middle = mod(p + vec2(division_spacing * 0.5), vec2(division_spacing)) - division_spacing * 0.5;
		vec2 marker_point = vertical ? vec2(signed_lines.x, middle.y) : vec2(middle.x, signed_lines.y);
		if (in_plaza && abs(marker_point.x) < 0.325 && abs(marker_point.y) < 0.1875) {
			color = texture(marker_texture, marker_point / vec2(0.65, 0.375) + 0.5).rgb;
		}
	}
	if (in_plaza && octagon_distance(p) < octagon_size * 0.46) {
		vec2 center_uv = p / octagon_size + 0.5;
		color = texture(octagon_texture, center_uv).rgb;
		gradient = slope(texture(octagon_normal, center_uv).rgb);
	}
	vec2 arrow_point = vec2(abs(p.x) - (octagon_size * 0.5 + 1.2), p.y);
	vec2 arrow_uv = arrow_point / vec2(2.575, 1.9) + vec2(0.56, 0.5);
	// Clip the footprint to the triangle to avoid a rectangular patch around it.
	if (in_plaza && arrow_uv.x > 0.22 && arrow_uv.x < 0.82 && abs(arrow_uv.y - 0.52) < (0.82 - arrow_uv.x) * 0.61) {
		color = texture(arrow_texture, arrow_uv).rgb;
		gradient = vec2(0.0);
	}
	NORMAL = lumina_bump(NORMAL, VERTEX, world_position.xz, gradient * normal_strength);
	if (lumina_relief_enabled) { color = lumina_tone(color); }
	float wet = wet_response * clamp(wetness + weather_wetness, 0.0, 1.0);
	color *= mix(1.0, 0.65, wet);
	vec4 rain = rain_surface(world_position.xz, rain_clock, rain_density * rain_amount, rain_radius, 0.38);
	float splash = clamp((rain.x * 0.65 + rain.w) * rain_strength * rain_amount, 0.0, 0.5);
	ALBEDO = mix(color, vec3(0.62, 0.71, 0.77), splash);
	ROUGHNESS = max(mix(roughness, 0.24, wet), lumina_relief_enabled ? lumina_matte_floor : 0.0);
	METALLIC = 0.0;
}
