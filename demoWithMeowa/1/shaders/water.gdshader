shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// 像素风水面：纹理按像素步进流动，岸边按深度差画出泡沫。

uniform sampler2D water_texture : source_color, filter_nearest_mipmap, repeat_enable;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
uniform vec4 shallow_color : source_color = vec4(0.42, 0.74, 0.82, 1.0);
uniform vec4 deep_color : source_color = vec4(0.18, 0.42, 0.58, 1.0);
uniform vec4 foam_color : source_color = vec4(0.92, 0.97, 1.0, 1.0);
uniform vec2 flow = vec2(0.0, 0.12);
uniform float cell_size = 1.6;
uniform float texture_pixels = 64.0;
// 深度差小于该值（米）的地方画泡沫
uniform float foam_distance = 0.12;
uniform float depth_fade = 1.6;
uniform float opacity = 0.7;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// 流动偏移按纹理像素取整，水纹一格一格地移动
	vec2 offset = floor(flow * TIME * texture_pixels) / texture_pixels;
	vec2 uv = world_position.xz / cell_size;
	vec3 pattern = texture(water_texture, uv - offset).rgb;
	vec3 pattern2 = texture(water_texture, uv * 0.5 + offset.yx * 0.7 + 0.37).rgb;
	float highlight = step(0.82, max(dot(pattern, vec3(0.33)), dot(pattern2, vec3(0.33))));

	float scene_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	float water_depth = (-view.z / view.w) - (-VERTEX.z);
	float texel = cell_size / texture_pixels;
	float depth_steps = floor(water_depth / texel) * texel;

	vec3 color = mix(shallow_color.rgb, deep_color.rgb, clamp(depth_steps / depth_fade, 0.0, 1.0));
	color = mix(color, foam_color.rgb, highlight * 0.6);
	float alpha = opacity;
	if (depth_steps < foam_distance) {
		color = foam_color.rgb;
		alpha = 0.95;
	}
	ALBEDO = color;
	ALPHA = alpha;
	ROUGHNESS = 0.08;
	SPECULAR = 0.6;
}
