shader_type spatial;

#include "res://shaders/includes/lumina_surface.gdshaderinc"
#include "res://shaders/includes/pixel_palette.gdshaderinc"

uniform sampler2D surface_texture : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_texture_linear : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool pixel_sampling = true;
uniform float surface_roughness = 0.9;
uniform float surface_contrast : hint_range(0.0, 1.2, 0.05) = 1.0;
uniform vec4 surface_contrast_center : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform sampler2D pixel_palette_texture : source_color, filter_nearest, repeat_disable;
uniform bool pixel_palette_enabled = false;
uniform int pixel_palette_row : hint_range(0, 3, 1) = 2;
// Painted blocks in the source sheet span several file pixels. Sample their actual scale.
uniform float relief_sample_pixels : hint_range(1.0, 16.0, 1.0) = 6.0;
uniform float relief_height : hint_range(0.0, 0.04, 0.001) = 0.012;
uniform bool surface_normal_enabled = false;
uniform sampler2D surface_normal_texture : filter_nearest_mipmap_anisotropic, repeat_enable;
uniform float surface_normal_strength : hint_range(0.0, 1.5, 0.05) = 0.8;

vec3 surface_color(vec2 uv) {
	vec3 color = pixel_sampling ? texture(surface_texture, uv).rgb : texture(surface_texture_linear, uv).rgb;
	return mix(surface_contrast_center.rgb, color, surface_contrast);
}

void fragment() {
	vec3 color = surface_color(UV);
	if (surface_normal_enabled) {
		vec3 normal = texture(surface_normal_texture,UV).rgb * 2.0 - 1.0;
		vec2 gradient = vec2(-normal.x,normal.y) / max(normal.z,0.25);
		NORMAL = lumina_bump(NORMAL,VERTEX,UV,gradient * 1.6 * surface_normal_strength);
	}
	if (lumina_relief_enabled) {
		if (!surface_normal_enabled) {
			vec2 texel = relief_sample_pixels / vec2(textureSize(surface_texture, 0));
			float height = lumina_height(color);
			float hx = lumina_height(surface_color(UV + vec2(texel.x, 0.0)));
			float hy = lumina_height(surface_color(UV + vec2(0.0, texel.y)));
			vec2 slope = vec2((hx - height) / texel.x, (hy - height) / texel.y);
			NORMAL = lumina_bump(NORMAL, VERTEX, UV, slope * relief_height * lumina_relief_strength);
		}
		color = lumina_tone(color);
	}
	if (pixel_palette_enabled) {
		color = pixel_palette_map(color, pixel_palette_texture, pixel_palette_row);
	}
	ALBEDO = color;
	ROUGHNESS = lumina_relief_enabled ? max(surface_roughness, lumina_matte_floor) : surface_roughness;
}
