// Top surfaces and cliff rims sample the same biome, dirt and path layers.
// Keep tile selection and tinting identical on both sides of an edge.

#include "res://shaders/pixel_palette.gdshaderinc"

group_uniforms pixel_palette;
uniform bool pixel_palette_enabled = false;
uniform sampler2D pixel_palette_texture : source_color, filter_nearest, repeat_disable;
// Only the new 64-pixel cobble sample opts in; 1 restores its source detail.
uniform float pixel_stone_detail_strength : hint_range(0.0, 1.0, 0.05) = 1.0;
uniform float pixel_grass_contrast : hint_range(0.0, 1.0, 0.02) = 1.0;
uniform vec4 pixel_grass_center : source_color = vec4(0.4, 0.5, 0.3, 1.0);
group_uniforms;

group_uniforms smooth_grass;
// The clean grass surface has independent material data, not leaf-shaped relief.
uniform bool smooth_grass_enabled = false;
uniform sampler2D smooth_grass_orm_dry : filter_nearest_mipmap, repeat_enable;
uniform sampler2D smooth_grass_orm_wet : filter_nearest_mipmap, repeat_enable;
group_uniforms;

group_uniforms surface_normals;
uniform bool surface_normals_enabled = false;
uniform float surface_normal_strength : hint_range(0.0, 1.5, 0.05) = 0.8;
uniform sampler2D wild_normal_texture : filter_nearest_mipmap, repeat_enable;
uniform sampler2D path_normal_texture : filter_nearest_mipmap, repeat_disable;
uniform sampler2DArray paint_normals : filter_nearest_mipmap, repeat_disable;
uniform bool wild_normal_enabled = false;
uniform bool path_normal_enabled = false;
uniform float wild_normal_strength = 1.0;
uniform float path_normal_strength = 1.0;

group_uniforms edge_blending;
uniform bool path_edge_blending_enabled = false;
uniform float path_edge_width : hint_range(0.025, 0.3, 0.025) = 0.125;
uniform float path_edge_strength : hint_range(0.0, 0.8, 0.05) = 0.4;

group_uniforms grass_variation;
uniform bool grass_variation_enabled = false;
uniform float grass_variation_strength : hint_range(0.0, 0.5, 0.01) = 0.16;
uniform float grass_variation_size : hint_range(0.5, 20.0, 0.1) = 2.631579;
group_uniforms;

float surface_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec3 meadow_color(vec3 color, vec2 location, float grass) {
	if (!grass_variation_enabled || grass <= 0.0) return color;
	vec2 p = location / max(grass_variation_size, 0.01) + vec2(27.3, 18.1);
	vec2 cell = floor(p);
	vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	float meadow = mix(mix(surface_hash(cell), surface_hash(cell + vec2(1.0, 0.0)), f.x),
		mix(surface_hash(cell + vec2(0.0, 1.0)), surface_hash(cell + vec2(1.0)), f.x), f.y);
	return color * mix(1.0 - grass_variation_strength, 1.0 + grass_variation_strength * 0.25, smoothstep(0.22, 0.8, meadow));
}

vec2 normal_slope(vec3 encoded) {
	vec3 normal = encoded * 2.0 - 1.0;
	return vec2(-normal.x, normal.y) / max(normal.z, 0.25);
}

uniform sampler2D city_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D cyber_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D cultivation_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D wild_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D path_atlas : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D dirt_atlas : source_color, filter_nearest_mipmap, repeat_disable;

group_uniforms battle_paving;
// Fixed paint ID confines this authored layout to the existing battle cells.
uniform bool battle_paving_enabled = false;
uniform int battle_paving_paint_id = 11;
uniform vec4 battle_paving_rect = vec4(-15.2, 29.6, 30.4, 30.4);
uniform sampler2D battle_paving_albedo : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D battle_paving_normal : filter_nearest_mipmap, repeat_disable;
uniform sampler2D battle_paving_orm_dry : filter_nearest_mipmap, repeat_disable;
uniform sampler2D battle_paving_orm_wet : filter_nearest_mipmap, repeat_disable;
group_uniforms;

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

// 可配置道路图集；默认布局保持现有 Meowa 四角过渡。
uniform vec2 path_grid = vec2(4.0);
uniform bool path_configured = false;
uniform vec2 path_tiles[16];
uniform bool paint_enabled = false;
uniform sampler2DArray paint_textures : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D paint_settings : filter_nearest, repeat_disable;

int paint_id_at(ivec2 cell) {
	ivec2 index = clamp(cell - map_origin,ivec2(0),textureSize(terrain_map,0)-1);
	return int(round(texelFetch(terrain_map,index,0).a * 255.0));
}

vec4 paint_setting(int id,int row) {
	return texelFetch(paint_settings,ivec2(id,row),0);
}

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
vec4 sample_atlas(sampler2D atlas, int key, vec2 local, vec2 ddx, vec2 ddy, bool road) {
	vec2 grid = road ? path_grid : vec2(4.0);
	vec2 tile = road && path_configured ? path_tiles[key] : vec2(ATLAS[key]);
	vec2 margin = 0.5 * grid / vec2(textureSize(atlas,0));
	vec2 inset = clamp(local,margin,vec2(1.0)-margin);
	vec2 uv = (tile + inset) / grid;
	return textureGrad(atlas,uv,ddx/grid,ddy/grid);
}

void apply_paint(int id,int key,vec2 local,vec2 location,vec2 ddx,vec2 ddy,inout vec3 color,inout vec3 surface,inout float grass,inout int palette_row,inout vec4 stone_sampling,inout vec3 normal_data,inout float paving,bool normals) {
	vec4 config = paint_setting(id,0);
	if (id == 0 || config.x < 0.5) return;
	vec2 grid = int(config.y) == 2 ? config.zw : vec2(1.0);
	vec2 tile = int(config.y) == 2 ? paint_setting(id,4+key).xy : vec2(0.0);
	vec2 margin = 0.5 * grid / vec2(textureSize(paint_textures,0).xy);
	vec2 uv = (tile + clamp(local,margin,vec2(1.0)-margin)) / grid;
	vec4 paint = textureGrad(paint_textures,vec3(uv,config.x-1.0),ddx/grid,ddy/grid);
	if (paint.a > 0.5) {
		paving = 0.0;
		normal_data = vec3(0.0);
		vec4 normal_config = paint_setting(id,3);
		if (normals && normal_config.x > 0.5) {
			vec3 encoded = textureGrad(paint_normals,vec3(uv,config.x-1.0),ddx/grid,ddy/grid).rgb;
			normal_data = vec3(normal_slope(encoded) * normal_config.y,1.0);
		}
		color = paint.rgb * paint_setting(id,1).rgb;
		// ID 1 is the existing cobble atlas slice; soil and other brushes keep their colors.
		palette_row = id == 1 ? 1 : -1;
		stone_sampling = vec4(local, float(key), id == 1 ? 1.0 : -1.0);
		vec4 response = paint_setting(id,2);
		surface = response.xyz;
		grass = response.w;
		vec2 paving_uv = (location-battle_paving_rect.xy)/battle_paving_rect.zw;
		if (battle_paving_enabled && id == battle_paving_paint_id &&
			all(greaterThanEqual(paving_uv,vec2(0.0))) && all(lessThanEqual(paving_uv,vec2(1.0)))) {
			vec2 dx = ddx*cell_size/battle_paving_rect.zw;
			vec2 dy = ddy*cell_size/battle_paving_rect.zw;
			color = textureGrad(battle_paving_albedo,paving_uv,dx,dy).rgb * paint_setting(id,1).rgb;
			normal_data = vec3(0.0);
			if (normals) {
				vec3 encoded = textureGrad(battle_paving_normal,paving_uv,dx,dy).rgb;
				normal_data = vec3(normal_slope(encoded)*normal_config.y,1.0);
			}
			palette_row = -1;
			stone_sampling.w = -1.0;
			paving = 1.0;
		}
	}
}

// Lift isolated local dark minima, while leaving connected joints and broad dark faces intact.
// Metadata follows the final opaque layer, so covered roads and unrelated paint do no extra work.
vec3 quiet_stone(vec3 color, vec4 sampling, vec2 ddx, vec2 ddy) {
	float value = dot(color, vec3(0.2126, 0.7152, 0.0722));
	if (value <= 0.05) return color;
	const vec2 OFFSETS[8] = vec2[](vec2(-1.0, 0.0), vec2(1.0, 0.0),
		vec2(0.0, -1.0), vec2(0.0, 1.0), vec2(-1.0, -1.0), vec2(1.0, 1.0),
		vec2(-1.0, 1.0), vec2(1.0, -1.0));
	float neighbors[8];
	float sum = 0.0;
	vec4 config = paint_setting(1, 0);
	for (int index = 0; index < 8; index++) {
		vec2 local = sampling.xy + OFFSETS[index] / 64.0;
		vec4 sample_color;
		if (sampling.w < 0.5) {
			sample_color = sample_atlas(path_atlas, int(sampling.z), local, ddx, ddy, true);
			sample_color.rgb *= path_tint.rgb;
		} else {
			vec2 grid = int(config.y) == 2 ? config.zw : vec2(1.0);
			vec2 tile = int(config.y) == 2 ? paint_setting(1, 4 + int(sampling.z)).xy : vec2(0.0);
			vec2 margin = 0.5 * grid / vec2(textureSize(paint_textures, 0).xy);
			vec2 uv = (tile + clamp(local, margin, vec2(1.0) - margin)) / grid;
			sample_color = textureGrad(paint_textures, vec3(uv, config.x - 1.0), ddx / grid, ddy / grid);
			sample_color.rgb *= paint_setting(1, 1).rgb;
		}
		// Do not borrow colour from a transparent boundary, including its partial distant mip.
		if (sample_color.a < 0.99) return color;
		neighbors[index] = dot(sample_color.rgb, vec3(0.2126, 0.7152, 0.0722));
		sum += neighbors[index];
	}
	float connected_limit = value + max(0.0005, value * 0.005);
	for (int index = 0; index < 8; index += 2) {
		if (neighbors[index] <= connected_limit && neighbors[index + 1] <= connected_limit) return color;
	}
	float surrounding = sum / 8.0;
	float isolated = smoothstep(0.05, 0.1, value) * smoothstep(0.0002, 0.004, surrounding - value);
	float lift = max(1.0, surrounding / value);
	return color * mix(1.0, lift, isolated * (1.0 - pixel_stone_detail_strength));
}

// 某个世界位置的最终颜色（底材 → 泥土 → 道路），surface 输出粗糙度 / 金属度
vec3 sample_surface_detail(vec2 location, vec2 ddx, vec2 ddy, bool map_palette, bool stone_details, bool normals, out vec3 surface, out float grass, out int palette_row, out vec3 normal_data, out float paving) {
	vec2 grid = location / cell_size;
	// 地形格 n 的中心在 n * cell_size；显示格的四角正好落在四个地形格中心
	ivec2 top_left = ivec2(floor(grid));
	vec2 local = fract(grid);

	int zone = biome_at(grid);
	grass = zone == 3 ? 1.0 : 0.0;
	palette_row = -1;
	vec4 stone_sampling = vec4(0.0, 0.0, 0.0, -1.0);
	vec3 color;
	normal_data = vec3(0.0);
	paving = 0.0;
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
		if (normals && wild_normal_enabled) normal_data = vec3(normal_slope(textureGrad(wild_normal_texture,grid,ddx,ddy).rgb) * wild_normal_strength,1.0);
		palette_row = 0;
		surface = wild_surface;
	}

	int key = dirt_key(top_left);
	if (key > 0) {
		vec4 dirt = sample_atlas(dirt_atlas, key, local, ddx, ddy,false);
		if (dirt.a > 0.5) {
			normal_data = vec3(0.0);
			color = dirt.rgb * dirt_tint.rgb;
			palette_row = -1;
			surface = dirt_surface;
			grass = 0.0;
		}
	}

	key = path_key(top_left);
	if (key > 0) {
		vec4 path = sample_atlas(path_atlas, key, local, ddx, ddy,true);
		if (path_edge_blending_enabled && key < 15 && grass > 0.5 && path.a > 0.5) {
			// A narrow, pixel-stable grass fringe uses the original atlas alpha.
			float radius = path_edge_width / cell_size;
			float nearby = min(min(sample_atlas(path_atlas,key,local+vec2(radius,0.0),ddx,ddy,true).a,
				sample_atlas(path_atlas,key,local-vec2(radius,0.0),ddx,ddy,true).a),
				min(sample_atlas(path_atlas,key,local+vec2(0.0,radius),ddx,ddy,true).a,
				sample_atlas(path_atlas,key,local-vec2(0.0,radius),ddx,ddy,true).a));
			vec2 pixel = floor(location / (cell_size / 64.0));
			if (surface_hash(pixel) < (1.0-nearby) * path_edge_strength) path.a = 0.0;
		}
		if (path.a > 0.5) {
			normal_data = vec3(0.0);
			if (normals && path_normal_enabled) {
				vec3 encoded = sample_atlas(path_normal_texture,key,local,ddx,ddy,true).rgb;
				normal_data = vec3(normal_slope(encoded) * path_normal_strength,1.0);
			}
			color = path.rgb * path_tint.rgb;
			palette_row = 1;
			stone_sampling = vec4(local, float(key), 0.0);
			surface = path_surface;
			grass = 0.0;
		}
	}
	if (paint_enabled) {
		int nearest = paint_id_at(ivec2(round(grid)));
		if (nearest > 0 && int(paint_setting(nearest,0).y) != 2) {
			apply_paint(nearest,15,fract(grid+0.5),location,ddx,ddy,color,surface,grass,palette_row,stone_sampling,normal_data,paving,normals);
		}
		int ids[4] = int[](paint_id_at(top_left),paint_id_at(top_left+ivec2(0,1)),
			paint_id_at(top_left+ivec2(1,0)),paint_id_at(top_left+ivec2(1,1)));
		// Stable ID order keeps adjoining brushes consistent when the list is reordered.
		for (int i=0;i<4;i++) {
			for (int j=i+1;j<4;j++) {
				if (ids[j] < ids[i]) { int swap=ids[i]; ids[i]=ids[j]; ids[j]=swap; }
			}
		}
		for (int i=0;i<4;i++) {
			int id=ids[i];
			if (id == 0 || (i > 0 && id == ids[i-1]) || int(paint_setting(id,0).y) != 2) continue;
			int mask=int(paint_id_at(top_left)==id)+int(paint_id_at(top_left+ivec2(0,1))==id)*2
				+int(paint_id_at(top_left+ivec2(1,0))==id)*4+int(paint_id_at(top_left+ivec2(1,1))==id)*8;
			apply_paint(id,mask,local,location,ddx,ddy,color,surface,grass,palette_row,stone_sampling,normal_data,paving,normals);
		}
	}
	if (stone_details && pixel_stone_detail_strength < 1.0 && stone_sampling.w >= 0.0) {
		color = quiet_stone(color, stone_sampling, ddx, ddy);
	}
	if (stone_details && palette_row == 0 && pixel_grass_contrast < 1.0) {
		color = mix(pixel_grass_center.rgb * wild_tint.rgb, color, pixel_grass_contrast);
	}
	bool clean_grass = smooth_grass_enabled && palette_row == 0 && grass > 0.5;
	if (map_palette && palette_row >= 0 && !clean_grass) color = pixel_palette_map(color, pixel_palette_texture, palette_row);
	return color;
}

vec3 sample_surface(vec2 location, vec2 ddx, vec2 ddy, bool map_palette, bool stone_details, out vec3 surface, out float grass, out int palette_row) {
	vec3 unused_normal;
	float unused_paving;
	return sample_surface_detail(location,ddx,ddy,map_palette,stone_details,false,surface,grass,palette_row,unused_normal,unused_paving);
}

vec3 albedo_normal_at(vec2 location,vec2 ddx,vec2 ddy,out vec3 surface,out float grass,out int palette_row,out vec3 normal_data,out float paving) {
	return sample_surface_detail(location,ddx,ddy,false,true,surface_normals_enabled,surface,grass,palette_row,normal_data,paving);
}

vec3 albedo_at(vec2 location, vec2 ddx, vec2 ddy, out vec3 surface, out float grass) {
	int palette_row;
	return sample_surface(location, ddx, ddy, pixel_palette_enabled, true, surface, grass, palette_row);
}

// The final opaque layer decides which ramp applies after local material variation.
vec3 albedo_palette_at(vec2 location, vec2 ddx, vec2 ddy, out vec3 surface, out float grass, out int palette_row) {
	// The top shader maps once, after tone and meadow variation.
	return sample_surface(location, ddx, ddy, false, true, surface, grass, palette_row);
}

// Relief remains based on the source texture instead of palette boundaries.
vec3 albedo_relief_at(vec2 location, vec2 ddx, vec2 ddy, out vec3 surface, out float grass) {
	int palette_row;
	return sample_surface(location, ddx, ddy, false, false, surface, grass, palette_row);
}

group_uniforms;
