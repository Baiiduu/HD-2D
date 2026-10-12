shader_type spatial;
render_mode cull_disabled;

uniform sampler2D sprite_texture : source_color, filter_nearest, repeat_disable;
uniform float root_uv = 0.9166667;
// Visible plant height, excluding transparent canvas padding.
uniform float visible_height_uv = 0.5;
uniform float flexibility = 0.055;
uniform vec2 wind_direction = vec2(1.0, 0.25);
uniform float wind_strength = 0.0;
uniform float wind_speed = 1.6;
uniform float gust_strength = 0.3;
uniform float wind_time = 0.0;

#include "res://shaders/blink_airflow.gdshaderinc"
uniform float blink_plant_radius = 0.85;
uniform float blink_plant_height = 0.5;
uniform float blink_plant_strength = 0.16;
uniform float blink_plant_duration = 0.85;
uniform float blink_plant_rebound = 0.2;
uniform float blink_plant_response = 1.0;
varying vec3 blink_bend;

group_uniforms lighting;
uniform bool lighting_enabled = true;
uniform bool stable_shadows = true;
uniform float normal_strength : hint_range(0.0, 1.0) = 0.35;
uniform float root_occlusion : hint_range(0.0, 0.8) = 0.3;
uniform float backlight_strength : hint_range(0.0, 0.5) = 0.12;
varying vec3 clump_direction;
varying float wind_lean;
uniform bool farming_hide_enabled = false;
uniform sampler2D farming_map : filter_nearest, repeat_disable;
uniform vec4 farming_bounds = vec4(0.0, 0.0, 1.0, 1.0);
varying vec2 farming_uv;

void vertex() {
	vec2 origin = MODEL_MATRIX[3].xz;
	farming_uv = (origin - farming_bounds.xy) / farming_bounds.zw;
	float facing = fract(sin(dot(origin, vec2(12.9898, 78.233))) * 43758.5453) * TAU;
	clump_direction = vec3(cos(facing), 0.0, sin(facing));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), MAIN_CAM_INV_VIEW_MATRIX[2].xyz));
	vec3 forward = normalize(cross(MAIN_CAM_INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0)));
	// A fixed card silhouette in the shadow pass prevents Q/E from turning the caster.
	// This is a stylized clump shadow, not exact three-dimensional leaf geometry.
	if (lighting_enabled && stable_shadows && IN_SHADOW_PASS) {
		forward = clump_direction;
		right = cross(vec3(0.0, 1.0, 0.0), forward);
	}
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(forward, 0.0), MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	float weight = pow(clamp((root_uv - UV.y) / root_uv, 0.0, 1.0), 1.8);
	float phase = dot(origin, vec2(0.79, 1.37));
	float gust = 1.0 + gust_strength * sin(wind_time * 0.47 + dot(origin, vec2(0.13, 0.19)));
	float wave = sin(wind_time * wind_speed + phase) + 0.22 * sin(wind_time * wind_speed * 1.83 + phase * 2.1);
	vec3 wind = vec3(wind_direction.x, 0.0, wind_direction.y);
	float bend = wave * gust * wind_strength * flexibility * weight;
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
	VERTEX.x += dot(blink_bend, right);
	VERTEX.z += dot(blink_bend, forward);
	// The displayed card faces the camera; its lighting basis stays in the world.
	wind_lean = wave * gust * wind_strength * flexibility * weight;
}

void fragment() {
	if (farming_hide_enabled && all(greaterThanEqual(farming_uv, vec2(0.0))) && all(lessThan(farming_uv, vec2(1.0))) && texture(farming_map, farming_uv).r > 0.5) discard;
	vec4 sprite = texture(sprite_texture, UV);
	ALBEDO = sprite.rgb;
	ALPHA = sprite.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	if (lighting_enabled) {
		float height = clamp((root_uv - UV.y) / root_uv, 0.0, 1.0);
		vec3 side = cross(vec3(0.0, 1.0, 0.0), clump_direction);
		float leaf = (UV.x - 0.5) * 0.45 + (sprite.g - sprite.r) * 0.2;
		vec3 wind = vec3(wind_direction.x, 0.0, wind_direction.y);
		vec3 world_normal = normalize(vec3(0.0, 1.0, 0.0)
			+ normal_strength * (clump_direction * (0.35 + height * 0.25) + side * leaf)
			+ wind * wind_lean * 0.5 + blink_bend * 0.5);
		NORMAL = normalize(mat3(VIEW_MATRIX) * world_normal);
		float root = 1.0 - smoothstep(0.0, 0.48, height);
		ALBEDO *= 1.0 - root_occlusion * root * 0.45;
		AO = 1.0 - root_occlusion * root;
		AO_LIGHT_AFFECT = 0.25;
		// Native backlighting respects the real lights and their attenuation/shadows.
		BACKLIGHT = vec3(backlight_strength * smoothstep(0.12, 0.8, height));
	}
}
