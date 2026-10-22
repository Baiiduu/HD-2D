shader_type spatial;

// 入场临时使用：保留原城市的贴图、下沿融合与受光，但不写 FOG，
// 让引擎真实的体积雾积分同时覆盖墙体和灯窗。
uniform sampler2D background_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float background_brightness = 0.85;
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform bool has_albedo_texture = false;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform vec4 emission_tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform bool emission_uses_texture = false;
uniform float entry_light_gain = 1.0;
uniform float entry_weight = 1.0;
instance uniform vec3 blend_profile = vec3(0.0, 3.0, 0.14);

varying float height_from_origin;

void vertex() {
	height_from_origin = (MODEL_MATRIX * vec4(VERTEX, 0.0)).y;
}

void fragment() {
	vec3 texel = has_albedo_texture ? texture(albedo_texture, UV).rgb : vec3(1.0);
	float body = clamp((height_from_origin - blend_profile.x) / max(blend_profile.y, 0.01), 0.0, 1.0);
	if (body <= 0.001) {
		discard;
	}
	float surface = body * (1.0 - blend_profile.z);
	float view_aspect = abs(dFdy(SCREEN_UV.y)) / max(abs(dFdx(SCREEN_UV.x)), 0.000001);
	vec2 image_size = vec2(textureSize(background_texture, 0));
	float image_aspect = image_size.x / max(image_size.y, 1.0);
	vec2 scale = vec2(min(view_aspect / image_aspect, 1.0), min(image_aspect / view_aspect, 1.0));
	vec2 uv = vec2((SCREEN_UV.x - 0.5) * scale.x + 0.5, SCREEN_UV.y * scale.y);
	vec3 background = texture(background_texture, uv).rgb * background_brightness;
	ALBEDO = albedo_tint.rgb * texel * surface;
	ROUGHNESS = 0.98;
	METALLIC = 0.0;
	SPECULAR = 0.15 * surface;
	vec3 source_light = emission_tint.rgb * emission_energy * (emission_uses_texture ? texel : vec3(1.0));
	EMISSION = source_light * mix(1.0, entry_light_gain, entry_weight) * surface + background * (1.0 - surface);
}
