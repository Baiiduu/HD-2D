shader_type spatial;
render_mode cull_disabled;

uniform sampler2D tree_texture : source_color, filter_nearest, repeat_disable;
uniform float root_uv = 0.953125;
uniform float wind_strength = 0.65;
uniform vec2 wind_direction = vec2(1.0, 0.25);
uniform float wind_speed = 1.6;
uniform float gust_strength = 0.3;
uniform float crown_sway = 0.045;
uniform float normal_strength : hint_range(0.0, 1.0) = 0.5;
uniform float local_light_softness : hint_range(0.0, 8.0) = 4.0;
#include "res://shaders/includes/foliage_shadow.gdshaderinc"
varying vec3 world_right;
varying vec3 world_forward;

void vertex() {
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), MAIN_CAM_INV_VIEW_MATRIX[2].xyz));
	vec3 forward = normalize(cross(MAIN_CAM_INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0)));
	// Only the light selects the crown's casting pose; Q/E affects the visible tree.
	if (IN_SHADOW_PASS) {
		forward = foliage_shadow_forward(INV_VIEW_MATRIX);
		right = cross(vec3(0.0, 1.0, 0.0), forward);
	}
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(right * length(MODEL_MATRIX[0].xyz), 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(forward * length(MODEL_MATRIX[2].xyz), 0.0), MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	world_right = normalize(MODEL_MATRIX[0].xyz);
	world_forward = normalize(MODEL_MATRIX[2].xyz);
	vec2 origin = MODEL_MATRIX[3].xz;
	float crown = smoothstep(0.32, 0.95, clamp((root_uv - UV.y) / root_uv, 0.0, 1.0));
	float phase = dot(origin, vec2(0.79, 1.37));
	float gust = 1.0 + gust_strength * sin(TIME * 0.47 + phase);
	float bend = sin(TIME * wind_speed + phase) * gust * wind_strength * crown_sway * crown;
	vec3 wind = vec3(wind_direction.x, 0.0, wind_direction.y);
	VERTEX.x += dot(wind, right) * bend;
	VERTEX.z += dot(wind, forward) * bend * 0.25;
	if (IN_SHADOW_PASS) {
		VERTEX.x -= dot(wind, right) * bend;
		VERTEX.z -= dot(wind, forward) * bend * 0.25;
	}
}

void fragment() {
	vec4 tree = texture(tree_texture, UV);
	ALBEDO = tree.rgb;
	ALPHA = tree.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	if (IN_SHADOW_PASS) {
		float crown_shadow = foliage_shadow_coverage(UV, vec2(0.5, root_uv * 0.4), vec2(0.46, root_uv * 0.39));
		float trunk_shadow = foliage_shadow_coverage(UV, vec2(0.5, root_uv * 0.78), vec2(0.065, root_uv * 0.23));
		if (max(crown_shadow, trunk_shadow) <= foliage_shadow_sample(UV)) discard;
		ALPHA = 1.0;
	}
	ROUGHNESS = 1.0;
	float height = clamp((root_uv - UV.y) / root_uv, 0.0, 1.0);
	float crown = smoothstep(0.28, 0.58, height);
	// A world-space lighting basis keeps camera rotation from changing the albedo's lighting.
	vec3 trunk_normal = normalize(world_forward + world_right * (UV.x - 0.5) * 0.65 + vec3(0.0, 0.12, 0.0));
	float crown_height = clamp((0.55 - UV.y) / 0.5, 0.0, 1.0);
	vec3 crown_normal = normalize(vec3(0.0, 0.25 + crown_height * 0.9, 0.0) + normal_strength *
		(world_forward * 1.3 + world_right * (UV.x - 0.5) * 1.6));
	NORMAL = normalize(mat3(VIEW_MATRIX) * normalize(mix(trunk_normal, crown_normal, crown)));
	BACKLIGHT = vec3(crown * 0.12);
	AO = mix(0.7, 1.0, smoothstep(0.0, 0.22, height));
	AO_LIGHT_AFFECT = 0.25;
}

float tree_fresnel_weight(float cosine) {
	float grazing = 1.0 - clamp(cosine, 0.0, 1.0);
	float squared = grazing * grazing;
	return squared * squared * grazing;
}

void light() {
	float nl = max(dot(NORMAL, LIGHT), 0.0);
	float nv = max(dot(NORMAL, VIEW), 0.0001);
	vec3 halfway = normalize(LIGHT + VIEW);
	float lh = clamp(dot(LIGHT, halfway), 0.0, 1.0);
	float fd90 = 2.0 * lh * lh * ROUGHNESS - 0.5;
	float diffuse = nl * (1.0 + fd90 * tree_fresnel_weight(nl)) * (1.0 + fd90 * tree_fresnel_weight(nv)) / PI;
	// Billboard leaves can approach the lamp as the view turns. Bound that near-field
	// response without changing the actual light, its ground reflection or shadows.
	float height = clamp((root_uv - UV.y) / root_uv, 0.0, 1.0);
	float softness = local_light_softness * mix(0.06, 1.0, smoothstep(0.28, 0.58, height));
	float attenuation = LIGHT_IS_DIRECTIONAL ? ATTENUATION : ATTENUATION / (1.0 + ATTENUATION * softness);
	DIFFUSE_LIGHT += (vec3(diffuse) + (vec3(1.0 / PI) - vec3(diffuse)) * BACKLIGHT) * attenuation * LIGHT_COLOR;
	// This material is fully rough (ROUGHNESS = 1); retain the native GGX response.
	vec3 fresnel = vec3(0.04) + vec3(0.96) * tree_fresnel_weight(lh);
	float visibility = 0.5 / max(nl + nv, 0.0001);
	SPECULAR_LIGHT += nl * visibility / PI * fresnel * SPECULAR_AMOUNT * attenuation * LIGHT_COLOR;
}
