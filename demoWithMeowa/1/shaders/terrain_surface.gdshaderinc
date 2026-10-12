// Top surfaces and cliff rims sample the same biome, dirt and path layers.
// Keep tile selection and tinting identical on both sides of an edge.

uniform sampler2D city_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D cyber_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D cultivation_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D wild_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D path_atlas : source_color, filter_nearest_mipmap, repeat_disable;
uniform sampler2D dirt_atlas : source_color, filter_nearest_mipmap, repeat_disable;

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

void apply_paint(int id,int key,vec2 local,vec2 ddx,vec2 ddy,inout vec3 color,inout vec3 surface,inout float grass) {
	vec4 config = paint_setting(id,0);
	if (id == 0 || config.x < 0.5) return;
	vec2 grid = int(config.y) == 2 ? config.zw : vec2(1.0);
	vec2 tile = int(config.y) == 2 ? paint_setting(id,4+key).xy : vec2(0.0);
	vec2 margin = 0.5 * grid / vec2(textureSize(paint_textures,0).xy);
	vec2 uv = (tile + clamp(local,margin,vec2(1.0)-margin)) / grid;
	vec4 paint = textureGrad(paint_textures,vec3(uv,config.x-1.0),ddx/grid,ddy/grid);
	if (paint.a > 0.5) {
		color = paint.rgb * paint_setting(id,1).rgb;
		vec4 response = paint_setting(id,2);
		surface = response.xyz;
		grass = response.w;
	}
}

// 某个世界位置的最终颜色（底材 → 泥土 → 道路），surface 输出粗糙度 / 金属度
vec3 albedo_at(vec2 location, vec2 ddx, vec2 ddy, out vec3 surface, out float grass) {
	vec2 grid = location / cell_size;
	// 地形格 n 的中心在 n * cell_size；显示格的四角正好落在四个地形格中心
	ivec2 top_left = ivec2(floor(grid));
	vec2 local = fract(grid);

	int zone = biome_at(grid);
	grass = zone == 3 ? 1.0 : 0.0;
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
		vec4 dirt = sample_atlas(dirt_atlas, key, local, ddx, ddy,false);
		if (dirt.a > 0.5) {
			color = dirt.rgb * dirt_tint.rgb;
			surface = dirt_surface;
			grass = 0.0;
		}
	}

	key = path_key(top_left);
	if (key > 0) {
		vec4 path = sample_atlas(path_atlas, key, local, ddx, ddy,true);
		if (path.a > 0.5) {
			color = path.rgb * path_tint.rgb;
			surface = path_surface;
			grass = 0.0;
		}
	}
	if (paint_enabled) {
		int nearest = paint_id_at(ivec2(round(grid)));
		if (nearest > 0 && int(paint_setting(nearest,0).y) != 2) {
			apply_paint(nearest,15,fract(grid+0.5),ddx,ddy,color,surface,grass);
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
			apply_paint(id,mask,local,ddx,ddy,color,surface,grass);
		}
	}
	return color;
}

group_uniforms;
