// Top surfaces and cliff rims sample the same biome, dirt and path layers.
// Keep tile selection and tinting identical on both sides of an edge.

#include "res://shaders/includes/pixel_palette.gdshaderinc"

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

// Sparse editor painting is independent of the terrain height/collision grid.
// All textures are runtime RID bindings; an empty canvas preserves the old surface.
group_uniforms surface_canvas;
uniform bool surface_canvas_enabled = false;
uniform vec2 surface_canvas_origin = vec2(0.0);
uniform ivec2 surface_canvas_grid = ivec2(0);
uniform float surface_canvas_chunk_meters = 6.4;
uniform vec2 surface_canvas_texture_origin = vec2(-15.2, 29.6);
uniform sampler2D surface_canvas_lookup : filter_nearest, repeat_disable;
uniform sampler2DArray surface_canvas_layers : filter_nearest, repeat_disable;
uniform sampler2DArray surface_canvas_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2DArray surface_canvas_normal : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2DArray surface_canvas_material : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D surface_canvas_meta : filter_nearest, repeat_disable;
group_uniforms;

group_uniforms surface_materials;
uniform bool surface_material_maps_enabled = true;
uniform float surface_material_ao_strength : hint_range(0.0,1.0,0.05) = 0.85;
uniform float surface_material_roughness_strength : hint_range(0.0,1.0,0.05) = 1.0;
uniform sampler2DArray paint_materials : filter_nearest_mipmap, repeat_disable;
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

void apply_paint(int id,int key,vec2 local,vec2 location,vec2 ddx,vec2 ddy,inout vec3 color,inout vec3 surface,inout float grass,inout int palette_row,inout vec4 stone_sampling,inout vec3 normal_data,inout float paving,inout vec4 material_data,bool normals) {
	vec4 config = paint_setting(id,0);
	if (id == 0 || config.x < 0.5) return;
	vec2 grid = int(config.y) == 2 ? config.zw : vec2(1.0);
	vec2 tile = int(config.y) == 2 ? paint_setting(id,4+key).xy : vec2(0.0);
	if (int(config.y) != 2 && all(greaterThan(config.zw,vec2(0.0)))) {
		local = fract((location+vec2(cell_size*0.5))/config.zw);
		ddx *= cell_size/config.zw;
		ddy *= cell_size/config.zw;
	}
	vec2 margin = 0.5 * grid / vec2(textureSize(paint_textures,0).xy);
	vec2 uv = (tile + clamp(local,margin,vec2(1.0)-margin)) / grid;
	vec4 paint = textureGrad(paint_textures,vec3(uv,config.x-1.0),ddx/grid,ddy/grid);
	if (paint.a > 0.5) {
		paving = 0.0;
		material_data = vec4(1.0,0.0,0.0,0.0);
		normal_data = vec3(0.0);
		vec4 normal_config = paint_setting(id,3);
		if (surface_material_maps_enabled && normal_config.w > 0.5) {
			material_data = vec4(textureGrad(paint_materials,vec3(uv,config.x-1.0),ddx/grid,ddy/grid).rgb,normal_config.w);
		}
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

// R is the brush code (1..255/custom, 256/grass, 257/path); GB is stamp UV.
// A=0 repeats the material in world space, A=1 places one complete source image.
vec4 surface_canvas_record(vec2 location) {
	vec2 grid = (location - surface_canvas_origin) / max(surface_canvas_chunk_meters, 0.0001);
	ivec2 chunk = ivec2(floor(grid));
	if (any(lessThan(chunk, ivec2(0))) || any(greaterThanEqual(chunk, surface_canvas_grid))) return vec4(0.0);
	vec2 encoded = texelFetch(surface_canvas_lookup, chunk, 0).rg;
	int layer = int(round(encoded.r * 255.0)) + int(round(encoded.g * 255.0)) * 256 - 1;
	ivec3 dimensions = textureSize(surface_canvas_layers, 0);
	if (layer < 0 || layer >= dimensions.z) return vec4(0.0);
	ivec2 pixel = clamp(ivec2(floor(fract(grid) * vec2(dimensions.xy))), ivec2(0), dimensions.xy - 1);
	return texelFetch(surface_canvas_layers, ivec3(pixel, layer), 0);
}

bool same_canvas_stamp(vec4 center, vec4 neighbor) {
	return abs(center.r - neighbor.r) < 0.1 && neighbor.a > 0.5 && distance(center.gb, neighbor.gb) < 0.2;
}

// Read stamp axes from its own native neighbors; screen derivatives across a
// stamp boundary must not rotate normals or select a different texture level.
mat2 surface_canvas_stamp_mapping(vec2 location, vec4 center) {
	vec2 step_meters = vec2(surface_canvas_chunk_meters) / vec2(textureSize(surface_canvas_layers, 0).xy);
	vec4 east = surface_canvas_record(location + vec2(step_meters.x, 0.0));
	vec4 west = surface_canvas_record(location - vec2(step_meters.x, 0.0));
	vec4 south = surface_canvas_record(location + vec2(0.0, step_meters.y));
	vec4 north = surface_canvas_record(location - vec2(0.0, step_meters.y));
	bool has_east = same_canvas_stamp(center, east);
	bool has_west = same_canvas_stamp(center, west);
	bool has_south = same_canvas_stamp(center, south);
	bool has_north = same_canvas_stamp(center, north);
	vec2 along_x = vec2(0.0);
	vec2 along_z = vec2(0.0);
	if (has_east && has_west) along_x = (east.gb - west.gb) / (2.0 * step_meters.x);
	else if (has_east) along_x = (east.gb - center.gb) / step_meters.x;
	else if (has_west) along_x = (center.gb - west.gb) / step_meters.x;
	if (has_south && has_north) along_z = (south.gb - north.gb) / (2.0 * step_meters.y);
	else if (has_south) along_z = (south.gb - center.gb) / step_meters.y;
	else if (has_north) along_z = (center.gb - north.gb) / step_meters.y;
	vec2 axis_u = vec2(along_x.x, along_z.x);
	vec2 axis_v = vec2(along_x.y, along_z.y);
	if (length(axis_u) < 0.0001 || length(axis_v) < 0.0001) return mat2(0.0);
	axis_u = normalize(axis_u);
	axis_v = normalize(axis_v);
	if (abs(dot(axis_u, axis_v)) > 0.25) return mat2(0.0);
	return mat2(along_x, along_z);
}

// Keep magnified pixel interiors crisp; blend only the screen footprint at
// their boundaries. Mipmaps handle minification without changing source art.
vec2 surface_canvas_pixel_uv(vec2 uv, vec2 dimensions, vec2 dx, vec2 dy) {
	vec2 texel = uv * dimensions;
	vec2 footprint = max(abs(dx * dimensions) + abs(dy * dimensions), vec2(0.0001));
	return (floor(texel) + 0.5 + clamp((fract(texel) - 0.5) / footprint, vec2(-0.5), vec2(0.5))) / dimensions;
}

void apply_surface_canvas(vec2 location, vec2 dx, vec2 dy, inout vec3 color, inout vec3 surface, inout float grass,
	inout int palette_row, inout vec4 stone_sampling, inout vec3 normal_data, inout float paving, inout vec4 material_data, bool normals) {
	vec4 record = surface_canvas_record(location);
	int code = int(round(record.r));
	if (code < 1 || code > 257) return;
	vec4 config = texelFetch(surface_canvas_meta, ivec2(code, 0), 0);
	int layer = int(round(config.x)) - 1;
	if (layer < 0 || layer >= textureSize(surface_canvas_albedo, 0).z || any(lessThanEqual(config.yz, vec2(0.0)))) return;
	vec4 detail = texelFetch(surface_canvas_meta, ivec2(code, 3), 0);
	vec2 source_uv = record.gb;
	mat2 mapping = mat2(vec2(1.0 / max(detail.y, 0.0001), 0.0), vec2(0.0, 1.0 / max(detail.z, 0.0001)));
	if (record.a < 0.5) {
		source_uv = fract((location - surface_canvas_texture_origin) / max(detail.yz, vec2(0.0001)));
	} else {
		mapping = surface_canvas_stamp_mapping(location, record);
		vec2 step_meters = vec2(surface_canvas_chunk_meters) / vec2(textureSize(surface_canvas_layers, 0).xy);
		vec2 offset = mod(location - surface_canvas_origin, step_meters) - step_meters * 0.5;
		source_uv += mapping * offset;
	}
	vec2 source_dx = mapping * dx;
	vec2 source_dy = mapping * dy;
	vec2 source_size = vec2(textureSize(surface_canvas_albedo, 0).xy) * config.yz;
	vec2 margin = 0.5 / max(source_size, vec2(1.0));
	vec2 albedo_uv = clamp(source_uv, margin, vec2(1.0) - margin) * config.yz;
	// Coverage remains native and sharp, including partially transparent stamps.
	vec2 coverage_uv = record.a > 0.5 ? clamp(record.gb, margin, vec2(1.0) - margin) * config.yz : albedo_uv;
	ivec2 coverage_pixel = clamp(ivec2(floor(coverage_uv * vec2(textureSize(surface_canvas_albedo,0).xy))), ivec2(0), textureSize(surface_canvas_albedo,0).xy - ivec2(1));
	if (texelFetch(surface_canvas_albedo, ivec3(coverage_pixel,layer), 0).a <= 0.5) return;
	vec2 color_dx = source_dx * config.yz;
	vec2 color_dy = source_dy * config.yz;
	albedo_uv = surface_canvas_pixel_uv(albedo_uv, vec2(textureSize(surface_canvas_albedo, 0).xy), color_dx, color_dy);
	vec4 paint = textureGrad(surface_canvas_albedo, vec3(albedo_uv, float(layer)), color_dx, color_dy);
	color = paint.rgb * texelFetch(surface_canvas_meta, ivec2(code, 1), 0).rgb;
	vec4 response = texelFetch(surface_canvas_meta, ivec2(code, 2), 0);
	surface = response.xyz;
	grass = response.w;
	palette_row = code == 256 ? 0 : -1;
	stone_sampling = vec4(source_uv, 0.0, -1.0);
	paving = 0.0;
	material_data = vec4(1.0,0.0,0.0,0.0);
	vec3 material_config = texelFetch(surface_canvas_meta,ivec2(code,5),0).xyz;
	if (surface_material_maps_enabled && material_config.z > 0.5) {
		vec2 material_size = vec2(textureSize(surface_canvas_material,0).xy)*material_config.xy;
		vec2 material_margin = 0.5/max(material_size,vec2(1.0));
		vec2 material_uv = clamp(source_uv,material_margin,vec2(1.0)-material_margin)*material_config.xy;
		vec2 material_dx = source_dx * material_config.xy;
		vec2 material_dy = source_dy * material_config.xy;
		material_uv = surface_canvas_pixel_uv(material_uv, vec2(textureSize(surface_canvas_material,0).xy), material_dx, material_dy);
		material_data = vec4(textureGrad(surface_canvas_material,vec3(material_uv,float(layer)),material_dx,material_dy).rgb,material_config.z);
	}
	normal_data = vec3(0.0);
	if (normals && config.w > 0.5) {
		vec2 normal_scale = texelFetch(surface_canvas_meta, ivec2(code, 4), 0).xy;
		if (all(greaterThan(normal_scale, vec2(0.0)))) {
			vec2 normal_size = vec2(textureSize(surface_canvas_normal, 0).xy) * normal_scale;
			vec2 normal_margin = 0.5 / max(normal_size, vec2(1.0));
			vec2 normal_uv = clamp(source_uv, normal_margin, vec2(1.0) - normal_margin) * normal_scale;
			vec2 normal_dx = source_dx * normal_scale;
			vec2 normal_dy = source_dy * normal_scale;
			normal_uv = surface_canvas_pixel_uv(normal_uv, vec2(textureSize(surface_canvas_normal,0).xy), normal_dx, normal_dy);
			vec2 slope = normal_slope(textureGrad(surface_canvas_normal, vec3(normal_uv, float(layer)), normal_dx, normal_dy).rgb) * detail.x;
			if (record.a > 0.5 && length(mapping[0]) > 0.0001 && length(mapping[1]) > 0.0001) {
				slope = normalize(vec2(mapping[0].x,mapping[1].x)) * slope.x + normalize(vec2(mapping[0].y,mapping[1].y)) * slope.y;
			}
			normal_data = vec3(slope, 1.0);
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
vec3 sample_surface_detail(vec2 location, vec2 ddx, vec2 ddy, bool map_palette, bool stone_details, bool normals, out vec3 surface, out float grass, out int palette_row, out vec3 normal_data, out float paving, out vec4 material_data) {
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
	material_data = vec4(1.0,0.0,0.0,0.0);
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
			int underlay = int(paint_setting(nearest,3).z);
			if (underlay > 0 && underlay != nearest) {
				apply_paint(underlay,15,fract(grid+0.5),location,ddx,ddy,color,surface,grass,palette_row,stone_sampling,normal_data,paving,material_data,normals);
			}
			apply_paint(nearest,15,fract(grid+0.5),location,ddx,ddy,color,surface,grass,palette_row,stone_sampling,normal_data,paving,material_data,normals);
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
			apply_paint(id,mask,local,location,ddx,ddy,color,surface,grass,palette_row,stone_sampling,normal_data,paving,material_data,normals);
		}
	}
	if (surface_canvas_enabled) {
		apply_surface_canvas(location, ddx * cell_size, ddy * cell_size, color, surface, grass, palette_row, stone_sampling, normal_data, paving, material_data, normals);
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
	vec4 unused_material;
	return sample_surface_detail(location,ddx,ddy,map_palette,stone_details,false,surface,grass,palette_row,unused_normal,unused_paving,unused_material);
}

vec3 albedo_normal_at(vec2 location,vec2 ddx,vec2 ddy,out vec3 surface,out float grass,out int palette_row,out vec3 normal_data,out float paving,out vec4 material_data) {
	return sample_surface_detail(location,ddx,ddy,false,true,surface_normals_enabled,surface,grass,palette_row,normal_data,paving,material_data);
}

float mapped_roughness(vec4 data,float wet,float fallback) {
	int flags = int(round(data.w));
	float dry_value = (flags & 2) != 0 ? data.g : fallback;
	float wet_value = (flags & 4) != 0 ? data.b : fallback;
	return mix(fallback,mix(dry_value,wet_value,wet),surface_material_roughness_strength);
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
