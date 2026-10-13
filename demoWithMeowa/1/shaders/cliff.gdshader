shader_type spatial;

#include "res://shaders/terrain_surface.gdshaderinc"
#include "res://shaders/lumina_surface.gdshaderinc"

// 草地衔接崖顶与崖脚；坡道及铺装侧边共享顶面取样，保留岩壁主体。
// UV2 = (墙顶高度, 墙底高度)，所有距离都量化到纹理像素，保持像素风。

uniform sampler2D wall_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(0.92, 0.88, 0.82, 1.0);
// 降低岩层颜色的饱和度，避免崖壁比地面更抢眼
uniform float saturation : hint_range(0.0, 1.0) = 0.55;
uniform float texel = 0.025;
// 草沿厚度、沿下阴影线厚度（纹理像素）
uniform int lip_pixels = 3;
uniform int lip_shadow_pixels = 2;
// 崖底接触阴影的范围（米）与最暗程度
uniform float base_shadow_height = 0.5;
uniform float base_shadow_strength = 0.45;
uniform float roughness = 0.9;
uniform sampler2D wall_normal_texture : filter_nearest_mipmap, repeat_enable;
uniform bool wall_normal_enabled = false;
uniform bool edge_color_matching_enabled = false;

group_uniforms grass_transition;
uniform bool transition_enabled = true;
uniform sampler2D grass_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 grass_tint : source_color = vec4(0.78, 0.91, 0.82, 1.0);
uniform float grass_lip_pixels : hint_range(0.0, 8.0) = 3.0;
uniform float edge_variation_pixels : hint_range(0.0, 4.0) = 2.0;
uniform float transition_height : hint_range(0.0, 0.4) = 0.16;
uniform float moss_strength : hint_range(0.0, 1.0) = 0.4;
uniform float lip_shadow_strength : hint_range(0.0, 0.5) = 0.16;
uniform float base_blend_height : hint_range(0.0, 0.4) = 0.16;

group_uniforms surface_edge;
uniform bool surface_edge_enabled = true;
uniform float surface_edge_lip_pixels : hint_range(0.0, 8.0) = 2.0;
uniform float surface_edge_height : hint_range(0.0, 0.4) = 0.14;
uniform float surface_edge_normal_softening : hint_range(0.0, 0.8) = 0.35;
uniform float edge_wetness = 0.6;
uniform float edge_wet_darkening = 0.65;
uniform float edge_wet_roughness = 0.16;
uniform float edge_grass_wet_response = 0.2;

varying float world_y;
varying vec2 wall_span;
varying vec3 terrain_position;
varying vec2 wall_direction;
varying vec3 world_position;
varying vec2 world_wall_direction;

float edge_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float edge_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(edge_hash(cell), edge_hash(cell + vec2(1.0, 0.0)), f.x),
		mix(edge_hash(cell + vec2(0.0, 1.0)), edge_hash(cell + vec2(1.0)), f.x), f.y);
}

// Only blend against actual grass cells; paths, soil and water retain their edging.
bool has_grass(vec2 point) {
	ivec2 index = ivec2(round(point / cell_size)) - map_origin;
	ivec2 size = textureSize(terrain_map, 0);
	bool inside = all(greaterThanEqual(index, ivec2(0))) && all(lessThan(index, size));
	ivec2 cell = ivec2(round(texelFetch(terrain_map, clamp(index, ivec2(0), size - 1), 0).rg * 255.0));
	int paint = paint_enabled ? paint_id_at(ivec2(round(point / cell_size))) : 0;
	return inside && cell.x == 3 && (cell.y & 7) == 0 && paint == 0;
}

bool has_land(vec2 point) {
	ivec2 index = ivec2(round(point / cell_size)) - map_origin;
	ivec2 size = textureSize(terrain_map, 0);
	bool inside = all(greaterThanEqual(index, ivec2(0))) && all(lessThan(index, size));
	int overlay = int(round(texelFetch(terrain_map, clamp(index, ivec2(0), size - 1), 0).g * 255.0));
	return inside && (overlay & 4) == 0;
}

vec3 rim_color(vec2 point,vec2 ddx,vec2 ddy,out vec3 surface,out float grass,out float paving) {
	int row;
	vec3 unused_normal;
	vec3 color = sample_surface_detail(point,ddx,ddy,false,true,false,surface,grass,row,unused_normal,paving);
	if (lumina_relief_enabled) color = lumina_tone(color);
	color = meadow_color(color,point,grass);
	bool clean_grass = smooth_grass_enabled && row == 0 && grass > 0.5;
	return pixel_palette_enabled && row >= 0 && !clean_grass ? pixel_palette_map(color,pixel_palette_texture,row) : color;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_y = world_position.y;
	wall_span = UV2;
	terrain_position = VERTEX;
	wall_direction = NORMAL.xz;
	world_wall_direction = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xz;
}

void fragment() {
	vec3 color = texture(wall_texture, UV).rgb;
	if (surface_normals_enabled && wall_normal_enabled) {
		NORMAL = lumina_bump(NORMAL,VERTEX,UV,normal_slope(texture(wall_normal_texture,UV).rgb) * 1.6 * surface_normal_strength);
	} else if (lumina_relief_enabled) {
		vec2 sample_step = vec2(1.0) / vec2(textureSize(wall_texture, 0));
		float h = lumina_height(color);
		float hx = lumina_height(texture(wall_texture, UV + vec2(sample_step.x, 0.0)).rgb);
		float hy = lumina_height(texture(wall_texture, UV + vec2(0.0, sample_step.y)).rgb);
		vec2 gradient = vec2((hx - h) / sample_step.x, (hy - h) / sample_step.y);
		NORMAL = lumina_bump(NORMAL, VERTEX, UV, gradient * 0.008 * lumina_relief_strength);
	}
	color = mix(vec3(dot(color, vec3(0.3, 0.59, 0.11))), color, saturation) * tint.rgb;
	if (edge_color_matching_enabled && lumina_relief_enabled) color = lumina_tone(color);
	float from_top = floor((wall_span.x - world_y) / texel);
	float from_bottom = floor((world_y - wall_span.y) / texel) * texel;
	float edge_depth = max(0.0, wall_span.x - terrain_position.y);
	float edge_span = max(wall_span.x - wall_span.y, texel);
	float edge_width = max(texel, min(surface_edge_height, edge_span * 0.35));
	vec2 folded_point = world_position.xz - world_wall_direction * (edge_depth + texel * 0.5);
	vec2 edge_ddx = dFdx(folded_point / cell_size);
	vec2 edge_ddy = dFdy(folded_point / cell_size);
	vec3 top_surface = vec3(roughness, 0.0, 0.0);
	float top_grass = 1.0;
	float top_paving = 0.0;
	vec3 top_color = vec3(0.0);
	bool land_edge = surface_edge_enabled && has_land(terrain_position.xz - wall_direction * texel);
	if (land_edge && edge_depth <= max(grass_lip_pixels, surface_edge_lip_pixels) * texel + edge_width) {
		// Share the exact atlas selection used on top: dirt ramps must not get a green rim.
		if (edge_color_matching_enabled) {
			top_color = rim_color(folded_point,edge_ddx,edge_ddy,top_surface,top_grass,top_paving);
		} else {
			int unused_row;
			vec3 unused_normal;
			top_color = sample_surface_detail(folded_point,edge_ddx,edge_ddy,pixel_palette_enabled,true,false,top_surface,top_grass,unused_row,unused_normal,top_paving);
		}
	}
	bool grass_top = transition_enabled && has_grass(terrain_position.xz - wall_direction * texel);
	float edge_roughness = roughness;
	float edge_metallic = 0.0;
	float rim_shade_cover = 0.0;
	bool paved_rim = false;
	if (land_edge && (top_grass < 0.5 || !has_grass(terrain_position.xz - wall_direction * texel))) {
		float depth = floor(edge_depth / texel) * texel;
		float lip = min(surface_edge_lip_pixels * texel, edge_span * 0.2);
		float cover = 1.0 - smoothstep(lip, lip + edge_width, depth);
		float full_surface = 1.0 - smoothstep(max(0.0, lip - texel), lip + texel, depth);
		vec2 pixel = (floor(world_position.xz / texel) + 0.5) * texel;
		float weight = cover * mix(0.35 + edge_noise(pixel * 5.0) * 0.2, 1.0, full_surface);
		float wet = mix(top_surface.z, edge_grass_wet_response, top_grass) * edge_wetness;
		top_color *= mix(1.0, edge_wet_darkening, wet);
		color = mix(color, top_color, weight);
		// Short ramp wedges must not paint the old bottom shadow across the top seam.
		rim_shade_cover = weight * full_surface;
		edge_roughness = mix(roughness, mix(top_surface.x, edge_wet_roughness, wet), weight);
		edge_metallic = top_surface.y * weight;
		if (top_paving > 0.5) {
			vec2 uv = (folded_point-battle_paving_rect.xy)/battle_paving_rect.zw;
			vec2 dx = edge_ddx*cell_size/battle_paving_rect.zw;
			vec2 dy = edge_ddy*cell_size/battle_paving_rect.zw;
			vec3 response = mix(textureGrad(battle_paving_orm_dry,uv,dx,dy).rgb,textureGrad(battle_paving_orm_wet,uv,dx,dy).rgb,wet);
			float wall_roughness = lumina_relief_enabled ? max(roughness,lumina_matte_floor) : roughness;
			edge_roughness = mix(wall_roughness,response.g,weight);
			edge_metallic = response.b * weight;
			AO = mix(1.0,response.r,weight);
			paved_rim = true;
		}
		float fade = smoothstep(lip, lip + edge_width, depth);
		color *= 1.0 - lip_shadow_strength * 4.0 * fade * (1.0 - fade);
	} else if (grass_top) {
		// UV2 and VERTEX are both local: Ground's vertical offset must not shift the rim.
		float depth = max(0.0, floor((wall_span.x - terrain_position.y) / texel)) * texel;
		float bottom = max(0.0, floor((terrain_position.y - wall_span.y) / texel)) * texel;
		float span = max(wall_span.x - wall_span.y, texel);
		vec2 pixel = (floor(terrain_position.xz / texel) + 0.5) * texel;
		float pattern = edge_noise(pixel * 5.0);
		float lip = max(0.0, grass_lip_pixels + floor((pattern - 0.5) * 2.0 * edge_variation_pixels)) * texel;
		float width = max(texel, min(transition_height, span * 0.35));
		// Fold the existing top texture down the face instead of painting a flat green stripe.
		vec2 grass_uv = (terrain_position.xz - wall_direction * (depth + texel * 0.5)) / cell_size;
		vec3 grass = texture(grass_texture, grass_uv).rgb * grass_tint.rgb;
		if (edge_color_matching_enabled) {
			vec3 rim_surface; float rim_grass; float unused_paving;
			grass = rim_color(grass_uv * cell_size,edge_ddx,edge_ddy,rim_surface,rim_grass,unused_paving);
		} else if (pixel_palette_enabled && !smooth_grass_enabled) grass = pixel_palette_map(grass, pixel_palette_texture, 0);
		float cover = 1.0 - smoothstep(lip, lip + width, depth);
		float moss = moss_strength * smoothstep(0.25, 0.75, pattern);
		float full_grass = 1.0 - smoothstep(max(0.0, lip - texel), lip + texel, depth);
		color = mix(color, grass, cover * mix(moss, 1.0, full_grass));
		float shadow_fade = smoothstep(lip, lip + width, depth);
		float rim_shadow = 4.0 * shadow_fade * (1.0 - shadow_fade);
		color *= 1.0 - lip_shadow_strength * rim_shadow;
		if (has_grass(terrain_position.xz + wall_direction * texel) && base_blend_height > 0.0) {
			vec2 base_uv = (terrain_position.xz + wall_direction * (bottom + texel * 0.5)) / cell_size;
			vec3 base_grass = texture(grass_texture, base_uv).rgb * grass_tint.rgb;
			if (edge_color_matching_enabled) {
				vec3 base_surface; float base_grass_amount; float unused_paving;
				base_grass = rim_color(base_uv * cell_size,edge_ddx,edge_ddy,base_surface,base_grass_amount,unused_paving);
			} else if (pixel_palette_enabled && !smooth_grass_enabled) base_grass = pixel_palette_map(base_grass, pixel_palette_texture, 0);
			float base_cover = 1.0 - smoothstep(0.0, min(base_blend_height, span * 0.25), bottom);
			color = mix(color, base_grass, base_cover * moss_strength * (0.35 + pattern * 0.65));
		}
	} else if (from_top < float(lip_pixels)) {
		color = COLOR.rgb * (from_top < 1.0 ? 1.12 : 1.0);
	} else if (from_top < float(lip_pixels + lip_shadow_pixels)) {
		color *= 0.55;
	}
	float shade = mix(1.0 - base_shadow_strength, 1.0, smoothstep(0.0, base_shadow_height, from_bottom));
	shade = mix(shade, 1.0, rim_shade_cover);
	// A narrow shading bevel follows the actual sloped wall top, leaving geometry intact.
	vec2 tangent = vec2(wall_direction.y, -wall_direction.x);
	float along_dx = dot(dFdx(terrain_position.xz), tangent);
	float along_dy = dot(dFdy(terrain_position.xz), tangent);
	float slope = (dFdx(wall_span.x) * along_dx + dFdy(wall_span.x) * along_dy)
		/ max(along_dx * along_dx + along_dy * along_dy, 0.0000001);
	vec3 top_normal = normalize(vec3(-tangent.x * slope, 1.0, -tangent.y * slope));
	vec3 view_top_normal = normalize(mat3(VIEW_MATRIX) * MODEL_NORMAL_MATRIX * top_normal);
	float normal_cover = land_edge ? 1.0 - smoothstep(0.0, max(texel, edge_width * 0.5), edge_depth) : 0.0;
	NORMAL = normalize(mix(NORMAL, view_top_normal, normal_cover * surface_edge_normal_softening));
	ALBEDO = (lumina_relief_enabled && !edge_color_matching_enabled ? lumina_tone(color) : color) * shade;
	ROUGHNESS = lumina_relief_enabled && !paved_rim ? max(edge_roughness,lumina_matte_floor) : edge_roughness;
	METALLIC = edge_metallic;
}
