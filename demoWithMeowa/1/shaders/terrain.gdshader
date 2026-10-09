shader_type spatial;

// 统一地形：区域底材 + Meowa dual-grid 过渡图集叠层。
// 世界被划分为 cell_size 米的地形格，格子数据由 Terrain 节点以纹理形式传入
// （R = 区域类型，G = 覆盖层标记：1 道路、2 泥土）；
// 显示格相对地形格偏移半格，每个显示格由四角地形格组合出 16 种情况之一，
// 再从 4×4 图集取对应的过渡瓦片。图集是抠好背景的前景层，叠在区域底材上。

uniform sampler2D city_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D cyber_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D cultivation_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D wild_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D path_atlas : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D dirt_atlas : source_color, filter_nearest_mipmap, repeat_disable;

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

group_uniforms map_edge;
// 地图最外圈多少米逐渐融进雾色（0 = 关闭），颜色应与环境雾、天空雾带一致
uniform float edge_fade_distance = 0.0;
uniform vec4 edge_fog_color : source_color = vec4(0.2, 0.32, 0.4, 1.0);

// 以下三项由 Terrain 节点在运行时设置
uniform sampler2D terrain_map : filter_nearest, repeat_disable;
uniform ivec2 map_origin = ivec2(0);
uniform float cell_size = 1.6;

group_uniforms layers;
uniform vec4 city_tint : source_color = vec4(0.92, 0.95, 1.0, 1.0);
uniform vec4 cyber_tint : source_color = vec4(0.3, 0.35, 0.46, 1.0);
uniform vec4 cultivation_tint : source_color = vec4(0.92, 1.0, 0.98, 1.0);
uniform vec4 wild_tint : source_color = vec4(0.78, 0.91, 0.82, 1.0);
uniform vec4 path_tint : source_color = vec4(1.0);
uniform vec4 dirt_tint : source_color = vec4(0.9, 0.95, 0.9, 1.0);
// x = 干燥时的粗糙度，y = 金属度，z = 能被打湿的程度（草地不湿，泥土半湿，硬质地面全湿）
uniform vec3 city_surface = vec3(0.72, 0.0, 1.0);
uniform vec3 cyber_surface = vec3(0.35, 0.35, 1.0);
uniform vec3 cultivation_surface = vec3(0.6, 0.0, 0.85);
uniform vec3 wild_surface = vec3(0.97, 0.0, 0.0);
uniform vec3 path_surface = vec3(0.74, 0.0, 1.0);
uniform vec3 dirt_surface = vec3(0.95, 0.0, 0.6);

const int OVERLAY_PATH = 1;
const int OVERLAY_DIRT = 2;
// 四角组合 key（左上 1 + 左下 2 + 右上 4 + 右下 8）→ 图集中的 (列, 行)，与 Meowa 预览器一致
const ivec2 ATLAS[16] = ivec2[](
	ivec2(0, 3), ivec2(3, 3), ivec2(0, 0), ivec2(3, 2),
	ivec2(0, 2), ivec2(1, 2), ivec2(2, 3), ivec2(3, 1),
	ivec2(1, 3), ivec2(0, 1), ivec2(3, 0), ivec2(2, 0),
	ivec2(1, 0), ivec2(2, 2), ivec2(1, 1), ivec2(2, 1));

varying vec3 world_position;

// 地图外的格子按最近的边缘格处理，避免边界处出现过渡瓦片
ivec2 cell_data(ivec2 cell) {
	ivec2 index = clamp(cell - map_origin, ivec2(0), textureSize(terrain_map, 0) - 1);
	vec2 value = texelFetch(terrain_map, index, 0).rg;
	return ivec2(round(value * 255.0));
}

bool is_path(ivec2 cell) {
	return (cell_data(cell).y & OVERLAY_PATH) != 0;
}

bool is_dirt(ivec2 cell) {
	return (cell_data(cell).y & OVERLAY_DIRT) != 0;
}

// 道路格的底材取像素所在一侧的相邻非道路格，避免道路边缘露出错误区域的底材
int biome_at(vec2 grid) {
	ivec2 cell = ivec2(round(grid));
	if (!is_path(cell)) {
		return cell_data(cell).x;
	}
	vec2 offset = grid - vec2(cell);
	ivec2 step_x = ivec2(int(sign(offset.x)), 0);
	ivec2 step_z = ivec2(0, int(sign(offset.y)));
	ivec2 first = abs(offset.x) >= abs(offset.y) ? step_x : step_z;
	ivec2 second = abs(offset.x) >= abs(offset.y) ? step_z : step_x;
	if (!is_path(cell + first)) {
		return cell_data(cell + first).x;
	}
	if (!is_path(cell + second)) {
		return cell_data(cell + second).x;
	}
	if (!is_path(cell + first + second)) {
		return cell_data(cell + first + second).x;
	}
	return cell_data(cell).x;
}

int path_key(ivec2 top_left) {
	return int(is_path(top_left)) + int(is_path(top_left + ivec2(0, 1))) * 2
		+ int(is_path(top_left + ivec2(1, 0))) * 4 + int(is_path(top_left + ivec2(1, 1))) * 8;
}

int dirt_key(ivec2 top_left) {
	return int(is_dirt(top_left)) + int(is_dirt(top_left + ivec2(0, 1))) * 2
		+ int(is_dirt(top_left + ivec2(1, 0))) * 4 + int(is_dirt(top_left + ivec2(1, 1))) * 8;
}

// 用调用方传入的连续坐标导数选 mip，避免 fract() 在瓦片边界处产生接缝
vec4 sample_atlas(sampler2D atlas, int key, vec2 local, vec2 ddx, vec2 ddy) {
	vec2 inset = clamp(local, vec2(0.5 / 64.0), vec2(1.0 - 0.5 / 64.0));
	vec2 uv = (vec2(ATLAS[key]) + inset) / 4.0;
	return textureGrad(atlas, uv, ddx / 4.0, ddy / 4.0);
}

// 某个世界位置的最终颜色（底材 → 泥土 → 道路），surface 输出粗糙度 / 金属度
vec3 albedo_at(vec2 location, vec2 ddx, vec2 ddy, out vec3 surface) {
	vec2 grid = location / cell_size;
	// 地形格 n 的中心在 n * cell_size；显示格的四角正好落在四个地形格中心
	ivec2 top_left = ivec2(floor(grid));
	vec2 local = fract(grid);

	int zone = biome_at(grid);
	vec3 color;
	if (zone == 0) {
		color = textureGrad(city_texture, grid, ddx, ddy).rgb * city_tint.rgb;
		surface = city_surface;
	} else if (zone == 1) {
		color = textureGrad(cyber_texture, grid, ddx, ddy).rgb * cyber_tint.rgb;
		surface = cyber_surface;
	} else if (zone == 2) {
		color = textureGrad(cultivation_texture, grid, ddx, ddy).rgb * cultivation_tint.rgb;
		surface = cultivation_surface;
	} else {
		color = textureGrad(wild_texture, grid, ddx, ddy).rgb * wild_tint.rgb;
		surface = wild_surface;
	}

	int key = dirt_key(top_left);
	if (key > 0) {
		vec4 dirt = sample_atlas(dirt_atlas, key, local, ddx, ddy);
		if (dirt.a > 0.5) {
			color = dirt.rgb * dirt_tint.rgb;
			surface = dirt_surface;
		}
	}

	key = path_key(top_left);
	if (key > 0) {
		vec4 path = sample_atlas(path_atlas, key, local, ddx, ddy);
		if (path.a > 0.5) {
			color = path.rgb * path_tint.rgb;
			surface = path_surface;
		}
	}
	return color;
}

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
	vec3 color = albedo_at(location, ddx, ddy, surface);

	// 湿润：颜色变暗、粗糙度降低，灯光会在地面上拉出倒影
	float wet = surface.z * wetness;
	float roughness = mix(surface.x, wet_roughness, wet);
	color *= mix(1.0, wet_darkening, wet);
	if (puddles && wet > 0.5 && is_puddle(location)) {
		color *= puddle_darkening;
		roughness = puddle_roughness;
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
