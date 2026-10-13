shader_type spatial;

#include "res://shaders/rain_surface.gdshaderinc"
#include "res://shaders/terrain_surface.gdshaderinc"
#include "res://shaders/lumina_surface.gdshaderinc"

// 统一地形：区域底材 + Meowa dual-grid 过渡图集叠层。
// 世界被划分为 cell_size 米的地形格，格子数据由 Terrain 节点以纹理形式传入
// （R = 区域类型，G = 覆盖层标记：1 道路、2 泥土）；
// 显示格相对地形格偏移半格，每个显示格由四角地形格组合出 16 种情况之一，
// 再从 4×4 图集取对应的过渡瓦片。图集是抠好背景的前景层，叠在区域底材上。

group_uniforms wetness;
// 全局湿润程度：0 = 干燥，1 = 雨后
uniform float wetness : hint_range(0.0, 1.0) = 0.4;
// 湿润时颜色变暗的程度、湿润表面的粗糙度
uniform float wet_darkening : hint_range(0.0, 1.0) = 0.65;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.16;
// 积水坑开关；噪声阈值越高积水越少；积水处颜色与粗糙度
uniform bool puddles = false;
uniform float puddle_threshold : hint_range(0.0, 1.0) = 0.9;
uniform float puddle_darkening : hint_range(0.0, 1.0) = 0.45;
uniform float puddle_roughness : hint_range(0.0, 1.0) = 0.02;
uniform float texture_pixels = 64.0;
// Existing Meowa albedo supplies small-scale surface response, without new art.
uniform float stone_relief : hint_range(0.0, 0.02, 0.001) = 0.006;
uniform float stone_gloss_variation : hint_range(0.0, 1.0, 0.05) = 0.55;

group_uniforms grass_lighting;
uniform bool grass_lighting_enabled = true;
uniform float grass_relief : hint_range(0.0, 0.02, 0.001) = 0.008;
uniform float grass_wet_response : hint_range(0.0, 0.5) = 0.2;
uniform float grass_sheen : hint_range(0.0, 0.6) = 0.35;
// GroundDressing supplies the mask and strength; an unbound material has no roots.
uniform float grass_root_occlusion : hint_range(0.0, 0.8) = 0.0;
uniform sampler2D grass_root_map : filter_linear, repeat_disable;
uniform vec4 grass_root_bounds = vec4(0.0, 0.0, 1.0, 1.0);

group_uniforms farming;
uniform bool farming_enabled = false;
uniform sampler2D farming_map : filter_nearest, repeat_disable;
uniform float farming_wet_darkening : hint_range(0.3, 1.0) = 0.68;
uniform float farming_wet_roughness : hint_range(0.2, 1.0) = 0.72;

group_uniforms rain;
uniform float rain_amount = 0.0;
uniform float rain_clock = 0.0;
uniform float rain_density = 0.9;
uniform float rain_radius = 0.11;
uniform float rain_strength = 0.32;
uniform float weather_wetness = 0.0;

group_uniforms map_edge;
// 地图最外圈多少米逐渐融进雾色（0 = 关闭），颜色应与环境雾、天空雾带一致
uniform float edge_fade_distance = 0.0;
uniform vec4 edge_fog_color : source_color = vec4(0.2, 0.32, 0.4, 1.0);

varying vec3 world_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1.0, 0.0)), f.x),
		mix(hash(cell + vec2(0.0, 1.0)), hash(cell + vec2(1.0)), f.x), f.y);
}

// 积水坑分布：在纹理像素中心求值，坑的边缘是整像素的阶梯
bool is_puddle(vec2 location) {
	float texel = cell_size / texture_pixels;
	vec2 pixel = (floor(location / texel) + 0.5) * texel;
	float n = noise(pixel * 0.45) * 0.7 + noise(pixel * 1.7 + 7.3) * 0.3;
	return n > puddle_threshold;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 location = world_position.xz;
	vec2 grid = location / cell_size;
	vec2 ddx = dFdx(grid);
	vec2 ddy = dFdy(grid);
	vec3 surface;
	float grass;
	int palette_row;
	vec3 normal_data;
	vec3 color = albedo_normal_at(location, ddx, ddy, surface, grass, palette_row, normal_data);
	float grass_surface = grass;
	grass *= grass_lighting_enabled ? 1.0 : 0.0;

	// 湿润：颜色变暗、粗糙度降低，灯光会在地面上拉出倒影
	float wet = mix(surface.z, grass_wet_response, grass) * clamp(wetness + weather_wetness, 0.0, 1.0);
	float roughness = mix(surface.x, mix(wet_roughness, 0.62, grass), wet);
	// Sparse damp patches catch the real light; roots and most grass stay matte.
	float damp_patch = smoothstep(1.0 - grass_sheen, 1.1 - grass_sheen, noise(location * 1.9 + vec2(11.3, 7.1)));
	roughness = mix(roughness, 0.22, grass * damp_patch * smoothstep(0.015, 0.1, wet));
	vec3 relief_color = color;
	if ((pixel_stone_detail_strength < 1.0 && palette_row == 1) || (pixel_grass_contrast < 1.0 && palette_row == 0)) {
		vec3 relief_surface;
		float relief_grass;
		relief_color = albedo_relief_at(location, ddx, ddy, relief_surface, relief_grass);
	}
	float stone_luma = dot(relief_color, vec3(0.2126, 0.7152, 0.0722));
	float stone_face = smoothstep(0.1, 0.45, stone_luma);
	float stone_surface = step(0.8, surface.z) * (1.0 - step(0.01, surface.y));
	// Dark joints stay rough; irregular polished faces catch native specular light.
	float gloss = stone_gloss_variation * wet * stone_surface;
	roughness = mix(roughness, mix(0.82, 0.2 + noise(location * 2.1) * 0.16, stone_face), gloss);
	float relief = stone_relief * stone_surface + grass_relief * grass;
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float determinant = dot(dpdx, r1);
	if (normal_data.z > 0.5) {
		NORMAL = lumina_bump(NORMAL,VERTEX,location,normal_data.xy * surface_normal_strength);
	}
	if (normal_data.z < 0.5 && !lumina_relief_enabled && abs(determinant) > 0.000001 && relief > 0.0) {
		vec3 gradient = (r1 * dFdx(stone_luma) + r2 * dFdy(stone_luma)) * relief / determinant;
		// Clamp relief on distant texels to avoid sparkling pixel edges.
		gradient /= max(1.0, length(gradient) / 0.22);
		NORMAL = normalize(NORMAL - gradient);
	}
	if (lumina_relief_enabled) {
		if (normal_data.z < 0.5) {
		// Sample the final composed surface: roads, custom brushes and dual-grid edges agree.
		float step_meters = cell_size / max(texture_pixels, 1.0);
		vec3 neighbor_surface;
		float neighbor_grass;
		float h = lumina_height(relief_color);
		float hx = lumina_height(albedo_relief_at(location + vec2(step_meters, 0.0), ddx, ddy, neighbor_surface, neighbor_grass));
		float hz = lumina_height(albedo_relief_at(location + vec2(0.0, step_meters), ddx, ddy, neighbor_surface, neighbor_grass));
		float amplitude = mix(0.009, 0.004, grass) * lumina_relief_strength;
		NORMAL = lumina_bump(NORMAL, VERTEX, location, vec2(hx - h, hz - h) * amplitude / step_meters);
		}
		color = lumina_tone(color);
		roughness = max(roughness, lumina_matte_floor);
	}
	// Meadow colour belongs to the ground, independent of the lighting style.
	color = meadow_color(color,location,grass_surface);
	if (pixel_palette_enabled && palette_row >= 0) {
		color = pixel_palette_map(color, pixel_palette_texture, palette_row);
	}
	color *= mix(1.0, wet_darkening, wet);
	if (farming_enabled) {
		ivec2 farm_index = clamp(ivec2(round(grid)) - map_origin, ivec2(0), textureSize(farming_map, 0) - 1);
		float watered = texelFetch(farming_map, farm_index, 0).g;
		color *= mix(1.0, farming_wet_darkening, watered);
		roughness = mix(roughness, farming_wet_roughness, watered);
	}
	if (grass > 0.0 && grass_root_occlusion > 0.0) {
		vec2 root_uv = (location - grass_root_bounds.xy) / grass_root_bounds.zw;
		float roots = texture(grass_root_map, root_uv).r * grass_root_occlusion;
		color *= 1.0 - roots * 0.3;
		AO = 1.0 - roots;
		AO_LIGHT_AFFECT = 0.2;
	}
	if (puddles && wet > 0.5 && is_puddle(location)) {
		color *= puddle_darkening;
		roughness = puddle_roughness;
	}
	// Rain lands on exposed top surfaces. Water cells get their own ripples.
	if ((cell_data(ivec2(round(grid))).y & 4) == 0) {
		vec4 rain = rain_surface(location, rain_clock, rain_density * rain_amount, rain_radius, 0.38);
		float splash = clamp((rain.x * 0.65 + rain.w) * rain_strength * rain_amount * mix(0.3, 1.0, surface.z), 0.0, 0.5);
		color = mix(color, vec3(0.62, 0.71, 0.77), splash);
	}
	// 地图边缘融进雾里：离地图边界越近，越接近雾色
	vec2 map_min = (vec2(map_origin) - 0.5) * cell_size;
	vec2 map_max = map_min + vec2(textureSize(terrain_map, 0)) * cell_size;
	vec2 to_edge = min(location - map_min, map_max - location);
	float edge = edge_fade_distance > 0.0 ? 1.0 - smoothstep(0.0, edge_fade_distance, min(to_edge.x, to_edge.y)) : 0.0;
	ALBEDO = color * (1.0 - edge);
	EMISSION = edge_fog_color.rgb * edge;
	ROUGHNESS = mix(roughness, 1.0, edge);
	METALLIC = surface.y;
}
