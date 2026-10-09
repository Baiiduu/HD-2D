shader_type spatial;

// 崖壁：岩石纹理 + 崖顶草沿（顶点色）+ 沿下的阴影线 + 崖底接触阴影。
// UV2 = (墙顶高度, 墙底高度)，所有距离都量化到纹理像素，保持像素风。

uniform sampler2D wall_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(0.92, 0.88, 0.82, 1.0);
// 降低岩层颜色的饱和度，避免崖壁比地面更抢眼
uniform float saturation : hint_range(0.0, 1.0) = 0.55;
uniform float texel = 0.025;
// 草沿厚度、沿下阴影线厚度（纹理像素）
uniform int lip_pixels = 3;
uniform int lip_shadow_pixels = 2;
// 崖底接触阴影的范围（米）与最暗程度
uniform float base_shadow_height = 0.5;
uniform float base_shadow_strength = 0.45;
uniform float roughness = 0.9;


varying float world_y;
varying vec2 wall_span;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	wall_span = UV2;
}

void fragment() {
	vec3 color = texture(wall_texture, UV).rgb;
	color = mix(vec3(dot(color, vec3(0.3, 0.59, 0.11))), color, saturation) * tint.rgb;
	float from_top = floor((wall_span.x - world_y) / texel);
	float from_bottom = floor((world_y - wall_span.y) / texel) * texel;
	if (from_top < float(lip_pixels)) {
		color = COLOR.rgb * (from_top < 1.0 ? 1.12 : 1.0);
	} else if (from_top < float(lip_pixels + lip_shadow_pixels)) {
		color *= 0.55;
	}
	float shade = mix(1.0 - base_shadow_strength, 1.0, smoothstep(0.0, base_shadow_height, from_bottom));
	ALBEDO = color * shade;
	ROUGHNESS = roughness;
}
