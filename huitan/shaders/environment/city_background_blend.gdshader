shader_type spatial;

// The existing city surfaces remain lit. Custom FOG mixes their final shaded
// colour with the original matte, without another mesh or transparent pass.
uniform sampler2D background_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float background_brightness = 0.85;
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;
uniform bool has_albedo_texture = false;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform vec4 emission_tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform bool emission_uses_texture = false;
// X: group bottom relative to the mesh origin. Y: linear blend height.
// Z: restrained background contribution above the blend band.
instance uniform vec3 blend_profile = vec3(0.0, 3.0, 0.14);

varying float height_from_origin;

void vertex() {
	height_from_origin = (MODEL_MATRIX * vec4(VERTEX, 0.0)).y;
}

void fragment() {
	vec3 texel = vec3(1.0);
	if (has_albedo_texture) {
		texel = texture(albedo_texture, UV).rgb;
	}
	ALBEDO = albedo_tint.rgb * texel;
	ROUGHNESS = 0.98;
	METALLIC = 0.0;
	SPECULAR = 0.15;
	EMISSION = emission_tint.rgb * emission_energy * (emission_uses_texture ? texel : vec3(1.0));

	// Match night_sky.gdshader's aspect-fill, top-aligned image framing.
	float view_aspect = abs(dFdy(SCREEN_UV.y)) / max(abs(dFdx(SCREEN_UV.x)), 0.000001);
	vec2 image_size = vec2(textureSize(background_texture, 0));
	float image_aspect = image_size.x / max(image_size.y, 1.0);
	vec2 scale = vec2(min(view_aspect / image_aspect, 1.0), min(image_aspect / view_aspect, 1.0));
	vec2 uv = vec2((SCREEN_UV.x - 0.5) * scale.x + 0.5, SCREEN_UV.y * scale.y);
	vec3 background = texture(background_texture, uv).rgb * background_brightness;
	float body = clamp((height_from_origin - blend_profile.x) / max(blend_profile.y, 0.01), 0.0, 1.0);
	if (body <= 0.001) {
		discard;
	}
	FOG = vec4(background, 1.0 - body * (1.0 - blend_profile.z));
}
