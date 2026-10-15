shader_type spatial;

#include "res://shaders/includes/rain_surface.gdshaderinc"

// 无纹理灰盒；后续在相同 TerrainData 上接回既有铺装与侧壁材质。
uniform vec4 top_color : source_color = vec4(0.56, 0.58, 0.58, 1.0);
// 灰盒保留纯色；只复用预览地面的湿润、真实反光与雨水响应。
uniform float wetness = 0.6;
uniform float wet_darkening = 0.65;
uniform float wet_roughness = 0.16;
uniform float weather_wetness = 0.0;
uniform float rain_amount = 0.0;
uniform float rain_clock = 0.0;
uniform float rain_density = 0.9;
uniform float rain_radius = 0.11;
uniform float rain_strength = 0.32;
varying vec3 world_position;

void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }

void fragment() {
	float wet = clamp(wetness + weather_wetness, 0.0, 1.0);
	vec3 color = top_color.rgb * mix(1.0, wet_darkening, wet);
	vec4 rain = rain_surface(world_position.xz, rain_clock, rain_density * rain_amount, rain_radius, 0.38);
	float splash = clamp((rain.x * 0.65 + rain.w) * rain_strength * rain_amount, 0.0, 0.5);
	ALBEDO = mix(color, vec3(0.62, 0.71, 0.77), splash);
	ROUGHNESS = mix(0.72, wet_roughness, wet);
	SPECULAR = 0.5;
}
