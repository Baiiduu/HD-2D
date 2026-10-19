shader_type spatial;
render_mode cull_disabled;

uniform sampler2D sprite_texture : source_color, filter_nearest, repeat_disable;
#include "res://shaders/includes/pixel_palette.gdshaderinc"
group_uniforms color_ramps;
uniform bool color_ramps_enabled = false;
uniform sampler2D color_palette : source_color, filter_nearest, repeat_disable;
// 0 leaves, 1 dry grass, 2..7 petals; stems and green leaves use row 0.
uniform int plant_palette_row = 0;
uniform float detail_contrast : hint_range(0.0, 1.0) = 1.0;
group_uniforms;
uniform float root_uv = 0.9166667;
// Visible plant height, excluding transparent canvas padding.
uniform float visible_height_uv = 0.5;
uniform float visible_width_uv = 0.7;
uniform float flexibility = 0.055;
uniform vec2 wind_direction = vec2(1.0, 0.25);
uniform float wind_strength = 0.0;
uniform float wind_speed = 1.6;
uniform float gust_strength = 0.3;
uniform float wind_time = 0.0;

#include "res://shaders/includes/environment_dynamics.gdshaderinc"
uniform vec4 ambient_region_wind = vec4(1.0);
uniform float ambient_wind_multiplier = 1.0;
uniform float ambient_wind_time = 0.0;

#include "res://shaders/includes/blink_airflow.gdshaderinc"
uniform float blink_plant_radius = 0.85;
uniform float blink_plant_height = 0.5;
uniform float blink_plant_strength = 0.16;
uniform float blink_plant_duration = 0.85;
uniform float blink_plant_rebound = 0.2;
uniform float blink_plant_response = 1.0;
varying vec3 blink_bend;
#include "res://shaders/includes/charge_airflow.gdshaderinc"

group_uniforms lighting;
uniform bool lighting_enabled = true;
uniform bool stable_shadows = true;
#include "res://shaders/includes/foliage_shadow.gdshaderinc"
uniform float normal_strength : hint_range(0.0, 1.0) = 0.35;
uniform float root_occlusion : hint_range(0.0, 0.8) = 0.3;
uniform float backlight_strength : hint_range(0.0, 0.5) = 0.12;
uniform bool leaf_normals_enabled = false;
uniform bool leaf_normal_available = false;
uniform sampler2D leaf_normal_texture : filter_nearest, repeat_disable;
uniform float leaf_normal_strength : hint_range(0.0, 1.0) = 0.55;
varying vec3 clump_direction;
varying float wind_lean;
uniform bool farming_hide_enabled = false;
uniform sampler2D farming_map : filter_nearest, repeat_disable;
uniform vec4 farming_bounds = vec4(0.0, 0.0, 1.0, 1.0);
varying vec2 farming_uv;

void vertex() {
	// Mark this camera/uniform-driven caster as animated for positional shadow caches.
	// Reading TIME updates the cache; the zero offset preserves all geometry and wind clocks.
	VERTEX.x += TIME * 0.0;
	vec2 origin = MODEL_MATRIX[3].xz;
	farming_uv = (origin - farming_bounds.xy) / farming_bounds.zw;
	float facing = fract(sin(dot(origin, vec2(12.9898, 78.233))) * 43758.5453) * TAU;
	clump_direction = vec3(cos(facing), 0.0, sin(facing));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), MAIN_CAM_INV_VIEW_MATRIX[2].xyz));
	vec3 forward = normalize(cross(MAIN_CAM_INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0)));
	// The casting volume faces the light, independent of the displayed billboard.
	if (lighting_enabled && stable_shadows && IN_SHADOW_PASS) {
		forward = foliage_shadow_forward(INV_VIEW_MATRIX);
		right = cross(vec3(0.0, 1.0, 0.0), forward);
	}
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right * length(MODEL_MATRIX[0].xyz), 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(forward * length(MODEL_MATRIX[2].xyz), 0.0), MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	float weight = pow(clamp((root_uv - UV.y) / root_uv, 0.0, 1.0), 1.8);
	float phase = dot(origin, vec2(0.79, 1.37));
	float clock = ambient_dynamics_enabled ? ambient_wind_time : wind_time;
	float wind_scale = ambient_dynamics_enabled ? ambient_wind_multiplier * dot(ambient_region_weights(origin), ambient_region_wind) : 1.0;
	float gust = 1.0 + gust_strength * sin(clock * 0.47 + dot(origin, vec2(0.13, 0.19)));
	float wave = sin(clock * wind_speed + phase) + 0.22 * sin(clock * wind_speed * 1.83 + phase * 2.1);
	vec3 wind = vec3(wind_direction.x, 0.0, wind_direction.y);
	float bend = wave * gust * wind_strength * wind_scale * flexibility * weight;
	VERTEX.x += dot(wind, right) * bend;
	VERTEX.z += dot(wind, forward) * bend * 0.4;
	// Custom R stores the card center's height above its fixed ground anchor.
	vec3 root = MODEL_MATRIX[3].xyz - vec3(0.0, INSTANCE_CUSTOM.r, 0.0);
	float blink_weight = pow(clamp((root_uv - UV.y) / max(visible_height_uv, 0.001), 0.0, 1.0), 1.8);
	blink_bend = vec3(0.0);
	for (int index = 0; index < blink_path_count; index++) {
		float elapsed = blink_path_starts[index].w;
		float duration = max(blink_plant_duration, 0.001);
		float age = clamp(elapsed / duration, 0.0, 1.0);
		float attack = min(0.05, duration * 0.2);
		float push = smoothstep(0.0, attack, elapsed) * (1.0 - smoothstep(attack, duration * 0.55, elapsed));
		float rebound = blink_plant_rebound * sin(PI * smoothstep(0.55, 1.0, age));
		float influence = blink_path_weight(root, index, blink_plant_radius, blink_plant_height, 0.0);
		blink_bend += blink_path_direction(index) * influence * (push - rebound);
	}
	// Limit overlapping impulses so repeated blinks do not stretch a clump indefinitely.
	blink_bend /= max(1.0, length(blink_bend));
	blink_bend *= blink_plant_strength * blink_plant_response * blink_weight;
	blink_bend += charge_airflow(root) * blink_plant_response * blink_weight;
	VERTEX.x += dot(blink_bend, right);
	VERTEX.z += dot(blink_bend, forward);
	// Wind and blink still animate the sprite; the ground's clump outline stays put.
	if (lighting_enabled && stable_shadows && IN_SHADOW_PASS) {
		VERTEX.x -= dot(wind, right) * bend + dot(blink_bend, right);
		VERTEX.z -= dot(wind, forward) * bend * 0.4 + dot(blink_bend, forward);
	}
	// The displayed card faces the camera; its lighting basis stays in the world.
	wind_lean = bend;
}

void fragment() {
	if (farming_hide_enabled && all(greaterThanEqual(farming_uv, vec2(0.0))) && all(lessThan(farming_uv, vec2(1.0))) && texture(farming_map, farming_uv).r > 0.5) discard;
	vec4 sprite = texture(sprite_texture, UV);
	ALBEDO = sprite.rgb;
	if (color_ramps_enabled) {
		int row = plant_palette_row;
		if (row >= 2) {
			bool green = sprite.g > sprite.r * 1.04 && sprite.g > sprite.b * 1.04;
			// Keep the darkest shared outline and green stems in the foliage family.
			if (green || max(sprite.r, max(sprite.g, sprite.b)) < 0.025) row = 0;
		}
		vec3 center = texelFetch(color_palette, ivec2(2, row), 0).rgb;
		ALBEDO = pixel_palette_map(mix(center, sprite.rgb, detail_contrast), color_palette, row);
	}
	ALPHA = sprite.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	if (lighting_enabled && stable_shadows && IN_SHADOW_PASS) {
		vec2 center = vec2(0.5, root_uv - visible_height_uv * 0.45);
		vec2 radius = vec2(visible_width_uv * 0.65, visible_height_uv * 0.55);
		float coverage = foliage_shadow_coverage(UV, center, radius);
		if (coverage <= foliage_shadow_sample(UV)) discard;
		ALPHA = 1.0;
	}
	ROUGHNESS = 1.0;
	if (lighting_enabled) {
		float height = clamp((root_uv - UV.y) / root_uv, 0.0, 1.0);
		vec3 side = cross(vec3(0.0, 1.0, 0.0), clump_direction);
		float leaf = (UV.x - 0.5) * 0.45 + (sprite.g - sprite.r) * 0.2;
		vec3 wind = vec3(wind_direction.x, 0.0, wind_direction.y);
		vec3 world_normal = normalize(vec3(0.0, 1.0, 0.0)
			+ normal_strength * (clump_direction * (0.35 + height * 0.25) + side * leaf)
			+ wind * wind_lean * 0.5 + blink_bend * 0.5);
		if (leaf_normals_enabled && leaf_normal_available) {
			vec3 leaf_normal = texture(leaf_normal_texture,UV).rgb * 2.0 - 1.0;
			world_normal = normalize(world_normal + (side * leaf_normal.x + clump_direction * leaf_normal.y) * leaf_normal_strength);
		}
		NORMAL = normalize(mat3(VIEW_MATRIX) * world_normal);
		float root = 1.0 - smoothstep(0.0, 0.48, height);
		ALBEDO *= 1.0 - root_occlusion * root * 0.45;
		AO = 1.0 - root_occlusion * root;
		AO_LIGHT_AFFECT = 0.25;
		// Native backlighting respects the real lights and their attenuation/shadows.
		BACKLIGHT = vec3(backlight_strength * smoothstep(0.12, 0.8, height));
	}
}
