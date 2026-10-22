shader_type spatial;
render_mode cull_disabled, specular_disabled;
#include "res://shaders/includes/character_motion.gdshaderinc"
instance uniform vec3 motion_lean = vec3(0.0);
instance uniform vec3 motion_pivot = vec3(0.0);
instance uniform float wave_finish_silhouette = 0.0;
instance uniform float hit_silhouette_amount : instance_index(6) = 0.0;
instance uniform vec4 hit_silhouette_rim_color : source_color, instance_index(7) = vec4(1.0, 0.96, 0.82, 1.0);
instance uniform vec4 speed_rim_data : instance_index(8) = vec4(0.0);
instance uniform vec3 speed_rim_direction : instance_index(9) = vec3(0.0);
instance uniform vec4 speed_rim_color : source_color, instance_index(10) = vec4(1.0, 0.87, 0.57, 1.0);

uniform sampler2D sprite_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 tint : source_color = vec4(1.0);
uniform bool lighting_enabled = true;
uniform float light_wrap : hint_range(0.0, 0.8) = 0.3;
uniform float top_light_response : hint_range(0.0, 1.0) = 0.4;
uniform float back_rim_strength : hint_range(0.0, 0.5) = 0.12;
uniform float local_light_response : hint_range(0.0, 3.0) = 1.0;
uniform sampler2D normal_texture : filter_nearest, repeat_disable;
uniform bool normal_mapping_enabled = false;
uniform float normal_mapping_strength : hint_range(0.0, 1.0) = 0.4;
uniform vec4 sprite_region = vec4(0.0,0.0,1.0,1.0);
// The water proxy shares lighting, with its own camera and clipping plane.
uniform bool mirror_view = false;
uniform float clip_height = -10000.0;
uniform bool fixed_y = true;
uniform bool flip_h = false;
uniform bool flip_v = false;
varying vec3 world_position;
varying vec3 world_up_view;
varying vec3 card_right_view;
varying vec3 card_up_view;
varying vec3 edge_normal;
varying float edge_amount;

void vertex() {
	// Camera-facing geometry must refresh positional shadows when only the camera moves.
	// TIME marks the caster as animated without changing its pose or animation clock.
	VERTEX.x += TIME * 0.0;
	mat4 camera = mirror_view ? INV_VIEW_MATRIX : MAIN_CAM_INV_VIEW_MATRIX;
	vec3 right = normalize(camera[0].xyz);
	vec3 up = normalize(camera[1].xyz);
	if (fixed_y) {
		right = normalize(vec3(right.x, 0.0, right.z));
		up = vec3(0.0, 1.0, 0.0);
	}
	vec3 facing = normalize(cross(right, up));
	mat4 billboard = mat4(vec4(right * length(MODEL_MATRIX[0].xyz), 0.0),
		vec4(up * length(MODEL_MATRIX[1].xyz), 0.0),
		vec4(facing * length(MODEL_MATRIX[2].xyz), 0.0), MODEL_MATRIX[3]);
	billboard = character_motion_card(billboard, motion_pivot, motion_lean);
	MODELVIEW_MATRIX = VIEW_MATRIX * billboard;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	world_position = (billboard * vec4(VERTEX, 1.0)).xyz;
	world_up_view = mat3(VIEW_MATRIX) * vec3(0.0, 1.0, 0.0);
	card_right_view = mat3(VIEW_MATRIX) * right;
	card_up_view = mat3(VIEW_MATRIX) * up;
}

void fragment() {
	if (world_position.y < clip_height) { discard; }
	vec2 uv = UV;
	if (mirror_view) {
		vec2 local = vec2(flip_h ? 1.0-UV.x : UV.x,flip_v ? 1.0-UV.y : UV.y);
		uv = sprite_region.xy + local * sprite_region.zw;
	}
	vec4 color = texture(sprite_texture, uv) * tint;
	ALBEDO = color.rgb;
	ALPHA = color.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ROUGHNESS = 1.0;
	if (lighting_enabled && normal_mapping_enabled) {
		vec3 normal = texture(normal_texture,uv).rgb * 2.0 - 1.0;
		normal.xy *= vec2(flip_h ? -1.0 : 1.0,flip_v ? -1.0 : 1.0);
		NORMAL = normalize(NORMAL + (card_right_view * normal.x + card_up_view * normal.y) * normal_mapping_strength);
	}
	edge_normal = vec3(0.0);
	edge_amount = 0.0;
	float silhouette = max(wave_finish_silhouette, hit_silhouette_amount);
	float silhouette_edge = 0.0;
	if ((lighting_enabled && back_rim_strength > 0.0) || silhouette > 0.0) {
		vec2 pixel = 1.0 / vec2(textureSize(sprite_texture, 0));
		vec2 low = sprite_region.xy + pixel * 0.5;
		vec2 high = sprite_region.xy + sprite_region.zw - pixel * 0.5;
		float left = texture(sprite_texture, clamp(uv - vec2(pixel.x, 0.0),low,high)).a;
		float right = texture(sprite_texture, clamp(uv + vec2(pixel.x, 0.0),low,high)).a;
		float above = texture(sprite_texture, clamp(uv - vec2(0.0, pixel.y),low,high)).a;
		float below = texture(sprite_texture, clamp(uv + vec2(0.0, pixel.y),low,high)).a;
		silhouette_edge = 1.0 - min(min(left, right), min(above, below));
		vec2 outward = vec2(left - right, below - above);
		outward *= vec2(flip_h ? -1.0 : 1.0, flip_v ? -1.0 : 1.0);
		edge_amount = clamp(length(outward), 0.0, 1.0);
		edge_normal = (card_right_view * outward.x + card_up_view * outward.y) / max(length(outward), 0.001);
	}
	EMISSION = vec3(0.0);
	if (silhouette > 0.0) {
		vec3 rim = wave_finish_silhouette > 0.0 ? vec3(1.0, 0.84, 0.52) : hit_silhouette_rim_color.rgb;
		ALBEDO = mix(ALBEDO, vec3(0.008, 0.012, 0.025), silhouette);
		EMISSION = rim * silhouette_edge * silhouette;
	}
	if (speed_rim_data.x > 0.0 && silhouette <= 0.0) {
		vec2 pixel = 1.0 / vec2(textureSize(sprite_texture, 0));
		vec2 step_uv = pixel * max(speed_rim_data.y, 0.5);
		vec2 low = sprite_region.xy + pixel * 0.5;
		vec2 high = sprite_region.xy + sprite_region.zw - pixel * 0.5;
		float l = texture(sprite_texture, clamp(uv - vec2(step_uv.x, 0.0), low, high)).a;
		float r = texture(sprite_texture, clamp(uv + vec2(step_uv.x, 0.0), low, high)).a;
		float t = texture(sprite_texture, clamp(uv - vec2(0.0, step_uv.y), low, high)).a;
		float b = texture(sprite_texture, clamp(uv + vec2(0.0, step_uv.y), low, high)).a;
		vec2 edge = vec2(l - r, b - t) * vec2(flip_h ? -1.0 : 1.0, flip_v ? -1.0 : 1.0);
		vec2 velocity = (VIEW_MATRIX * vec4(speed_rim_direction, 0.0)).xy;
		float rear = smoothstep(-0.15, 0.55, dot(edge / max(length(edge), 0.001), -velocity / max(length(velocity), 0.001)));
		float native_row = floor((uv.y - sprite_region.y) / pixel.y / 3.0);
		float flowing = mix(0.22, 1.0, smoothstep(-0.35, 0.35, sin(native_row * 1.7 - speed_rim_data.z * 18.0)));
		float rim = (1.0 - min(min(l, r), min(t, b))) * rear * flowing * speed_rim_data.x;
		EMISSION += speed_rim_color.rgb * rim;
	}
}

void light() {
	float facing = dot(NORMAL, LIGHT);
	float diffuse = max(facing, 0.0);
	if (lighting_enabled) {
		// Approximate a solid body's broad response, rather than transmitting light through clothing.
		float wrapped = max(facing + light_wrap, 0.0) / (1.0 + light_wrap);
		float upper = max(dot(normalize(world_up_view), LIGHT), 0.0) * 0.75;
		diffuse = mix(wrapped, max(wrapped, upper), top_light_response);
		float back = 1.0 - smoothstep(-0.35, 0.25, facing);
		float rim = edge_amount * back * max(dot(edge_normal, LIGHT) + back * 0.15, 0.0);
		diffuse += rim * back_rim_strength;
	}
	// Scene lights retain native distance/cone attenuation and shadow visibility.
	float response = LIGHT_IS_DIRECTIONAL ? 1.0 : local_light_response;
	DIFFUSE_LIGHT += diffuse * response * ATTENUATION * LIGHT_COLOR / PI;
}
