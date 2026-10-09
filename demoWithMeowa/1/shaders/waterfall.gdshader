shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// 像素风瀑布：按纹理像素列生成竖向水流条纹，每列下落节奏不同；
// 顶端一条翻沫，底部的白沫由水面的岸边泡沫提供。UV2 = (瀑布顶高度, 瀑布底高度)。

uniform vec4 water_color : source_color = vec4(0.3, 0.58, 0.78, 1.0);
uniform vec4 streak_color : source_color = vec4(0.6, 0.83, 0.95, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
// 下落速度（米/秒）
uniform float speed = 1.6;
uniform float texture_pixels = 64.0;
uniform float cell_size = 1.6;
uniform int top_foam_pixels = 2;
uniform float glow = 0.12;

varying float world_y;
varying vec2 span;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
	span = UV2;
}

void fragment() {
	float texel = cell_size / texture_pixels;
	float column = floor(UV.x * texture_pixels);
	float h = hash(column);
	// 以像素为单位、随时间向下移动的相位；每列的周期和偏移不同
	float phase = floor((span.x - world_y) / texel - TIME * speed * (0.8 + h * 0.5) / texel);
	float period = 7.0 + floor(h * 9.0);
	float position = mod(phase + floor(h * 31.0), period);
	vec3 color = water_color.rgb * (0.9 + hash(column + 7.0) * 0.2);
	if (position < 1.0) {
		color = foam_color.rgb;
	} else if (position < 3.0) {
		color = streak_color.rgb;
	}
	if ((span.x - world_y) / texel < float(top_foam_pixels)) {
		color = foam_color.rgb;
	}
	ALBEDO = color;
	EMISSION = color * glow;
	ALPHA = 0.9;
	ROUGHNESS = 0.2;
}
