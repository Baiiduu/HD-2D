shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// Flowing pixel water, bank/fall foam and independent planar mirrors.

uniform sampler2D water_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform sampler2D terrain_map : filter_nearest, repeat_disable;
uniform ivec2 map_origin = ivec2(-7, -6);
uniform vec4 shallow_color : source_color = vec4(0.26, 0.46, 0.5, 1.0);
uniform vec4 deep_color : source_color = vec4(0.1, 0.25, 0.3, 1.0);
uniform vec4 foam_color : source_color = vec4(0.72, 0.83, 0.85, 1.0);
uniform vec2 flow = vec2(0.0, 0.12);
uniform float cell_size = 1.6;
uniform float texture_pixels = 64.0;
// 深度差小于该值（米）的地方画泡沫
uniform float foam_distance = 0.12;
uniform float depth_fade = 1.6;
uniform float opacity = 0.86;
uniform float wave_strength = 0.08;
uniform float reflection_strength = 0.85;
uniform sampler2D reflection_texture_0 : filter_linear, repeat_disable;
uniform sampler2D reflection_texture_1 : filter_linear, repeat_disable;
uniform mat4 reflection_matrix_0;
uniform mat4 reflection_matrix_1;
uniform vec2 reflection_heights = vec2(-0.32, 0.48);
uniform bool reflection_enabled_0 = false;
uniform bool reflection_enabled_1 = false;

varying vec3 world_position;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}

ivec4 cell_at(ivec2 cell) {
	ivec2 point = cell - map_origin;
	ivec2 size = textureSize(terrain_map, 0);
	if (any(lessThan(point, ivec2(0))) || any(greaterThanEqual(point, size))) { return ivec4(0); }
	return ivec4(round(texelFetch(terrain_map, point, 0) * 255.0));
}

vec3 flow_pattern(vec2 uv, float time) {
	float phase = fract(time * 0.28);
	float phase2 = fract(time * 0.28 + 0.5);
	vec2 velocity = flow / 0.28;
	// Each moving phase is blended out before its wrap; no periodic jump.
	vec2 a = floor((uv - velocity * phase) * texture_pixels) / texture_pixels;
	vec2 b = floor((uv - velocity * phase2 + 0.37) * texture_pixels) / texture_pixels;
	return mix(textureGrad(water_texture, a, dFdx(uv), dFdy(uv)).rgb, textureGrad(water_texture, b, dFdx(uv), dFdy(uv)).rgb, abs(phase - 0.5) * 2.0);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 grid = world_position.xz / cell_size;
	ivec2 cell = ivec2(floor(grid + 0.5));
	vec2 local = fract(grid + 0.5);
	ivec4 me = cell_at(cell);
	float bank = 9.0, fall = 9.0;
	// Map foam survives viewing angle changes; depth also catches props.
	for (int direction = 0; direction < 4; direction++) {
		ivec2 offset = direction == 0 ? ivec2(-1, 0) : direction == 1 ? ivec2(1, 0) : direction == 2 ? ivec2(0, -1) : ivec2(0, 1);
		float distance = (direction == 0 ? local.x : direction == 1 ? 1.0 - local.x : direction == 2 ? local.y : 1.0 - local.y) * cell_size;
		ivec4 neighbor = cell_at(cell + offset);
		if ((neighbor.g & 4) == 0) { bank = min(bank, distance); }
		else if (neighbor.b > me.b) { fall = min(fall, distance); }
	}
	float scene_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	float water_depth = max(0.0, -view.z / view.w + VERTEX.z);
	vec3 pattern = flow_pattern(grid, TIME);
	float texel = cell_size / texture_pixels;
	vec2 pixel = (floor(world_position.xz / texel) + 0.5) * texel;
	float turbulence = noise(pixel * 6.0 - flow * TIME * 8.0) * 0.6 + noise(pixel * 13.0 + TIME * 0.7) * 0.4;
	float bank_foam = 1.0 - smoothstep(0.02, foam_distance + 0.08, bank - turbulence * 0.09);
	float fall_foam = (1.0 - smoothstep(0.05, 0.65, fall - turbulence * 0.25)) * (0.4 + turbulence * 0.6);
	float contact_foam = 1.0 - smoothstep(0.02, foam_distance, water_depth);
	float foam = max(max(bank_foam, fall_foam), contact_foam) * mix(0.4, 0.95, step(0.4, hash(floor(pixel / texel) + floor(TIME * 5.0))));
	float glint = smoothstep(0.72, 0.95, dot(pattern, vec3(0.3, 0.4, 0.3)));
	vec3 color = mix(shallow_color.rgb, deep_color.rgb, clamp(water_depth / depth_fade, 0.0, 1.0));
	color += glint * shallow_color.rgb * 0.28;
	color = mix(color, foam_color.rgb, foam);
	vec2 ripples = vec2(sin(pixel.y * 6.0 + TIME * 1.5) + (pattern.r - pattern.b), cos(pixel.x * 4.0 - TIME * 1.1) + (pattern.g - pattern.b)) * wave_strength;
	vec3 world_normal = normalize(vec3(ripples.x, 1.0, ripples.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_normal, 0.0)).xyz);
	ROUGHNESS = mix(0.12, 0.75, foam);
	SPECULAR = 0.35;
	float fresnel = 0.04 + 0.96 * pow(1.0 - clamp(dot(normalize(CAMERA_POSITION_WORLD - world_position), world_normal), 0.0, 1.0), 5.0);
	bool upper = abs(world_position.y - reflection_heights.y) < abs(world_position.y - reflection_heights.x);
	bool enabled = upper ? reflection_enabled_1 : reflection_enabled_0;
	enabled = enabled && min(abs(world_position.y - reflection_heights.x), abs(world_position.y - reflection_heights.y)) < 0.01;
	vec3 reflection = vec3(0.0);
	float reflectivity = 0.0;
	if (enabled) {
		vec4 projected = (upper ? reflection_matrix_1 : reflection_matrix_0) * vec4(world_position, 1.0);
		vec2 uv = projected.xy / max(projected.w, 0.0001) * 0.5 + 0.5;
		uv.y = 1.0 - uv.y;
		uv += ripples * vec2(0.016, 0.010);
		float edge = smoothstep(0.0, 0.025, min(min(uv.x, uv.y), min(1.0 - uv.x, 1.0 - uv.y)));
		if (projected.w > 0.0) {
			reflection = upper ? texture(reflection_texture_1, clamp(uv, vec2(0.001), vec2(0.999))).rgb : texture(reflection_texture_0, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
			reflectivity = clamp((0.08 + fresnel * 0.92) * reflection_strength * (1.0 - foam) * edge, 0.0, 0.95);
		}
	}
	ALBEDO = color * (1.0 - reflectivity);
	// Reflection already contains lighting; avoid lighting it a second time.
	EMISSION = reflection * reflectivity;
	ALPHA = mix(mix(opacity, 0.98, reflectivity), 0.96, foam);
}
