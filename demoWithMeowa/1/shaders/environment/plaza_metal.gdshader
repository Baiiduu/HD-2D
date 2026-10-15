shader_type spatial;

#include "res://shaders/includes/lumina_surface.gdshaderinc"
uniform sampler2D metal_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float roughness = 0.42;
uniform float metallic = 0.65;
uniform bool globe_engraving = false;
// Globe UVs are in metres / 1.6; the circumference determines longitude placement.
uniform vec2 globe_uv_span = vec2(3.5, 1.75);

void fragment() {
	vec3 color = texture(metal_texture, UV).rgb * tint.rgb;
	vec2 texel = 1.0 / vec2(textureSize(metal_texture, 0));
	float height = lumina_height(color);
	vec2 slope = vec2(lumina_height(texture(metal_texture, UV + vec2(texel.x, 0.0)).rgb * tint.rgb) - height,
		lumina_height(texture(metal_texture, UV + vec2(0.0, texel.y)).rgb * tint.rgb) - height);
	NORMAL = lumina_bump(NORMAL, VERTEX, UV, slope / texel * 0.002);
	if (globe_engraving) {
		vec2 globe_uv = UV / globe_uv_span;
		vec2 grid = abs(fract(globe_uv * vec2(12.0, 6.0) + 0.5) - 0.5);
		vec2 width = max(fwidth(globe_uv * vec2(12.0, 6.0)), vec2(0.004));
		vec2 engraved = 1.0 - smoothstep(vec2(0.004), vec2(0.004) + width, grid);
		float line = max(engraved.x, engraved.y);
		color = mix(color, vec3(0.22, 0.29, 0.34), line * 0.6);
	}
	ALBEDO = color;
	METALLIC = metallic;
	ROUGHNESS = roughness;
}
