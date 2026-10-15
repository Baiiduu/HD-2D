shader_type spatial;

#include "res://shaders/includes/lumina_surface.gdshaderinc"
uniform sampler2D grain_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 cloth_color : source_color = vec4(0.48, 0.43, 0.34, 1.0);

float weave(vec2 pixel) {
	vec2 cell = floor(pixel);
	float crossing = mod(floor(cell.x / 3.0) + floor(cell.y / 3.0), 2.0);
	float strand = crossing < 0.5 ? mod(cell.x, 3.0) : mod(cell.y, 3.0);
	return strand == 0.0 ? 0.92 : 1.0;
}

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(grain_texture, 0));
	vec2 pixel = UV / texel;
	float strand = weave(pixel);
	float grain = lumina_height(texture(grain_texture, UV).rgb);
	ALBEDO = cloth_color.rgb * strand * (0.94 + grain * 0.14);
	vec2 slope = vec2(weave(pixel + vec2(1.0, 0.0)) - strand, weave(pixel + vec2(0.0, 1.0)) - strand);
	NORMAL = lumina_bump(NORMAL, VERTEX, UV, slope / texel * 0.001);
	ROUGHNESS = 0.98;
}
