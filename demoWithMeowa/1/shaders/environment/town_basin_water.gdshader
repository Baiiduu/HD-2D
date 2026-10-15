shader_type spatial;

uniform vec4 water_color : source_color = vec4(0.12, 0.25, 0.29, 1.0);

void fragment() {
	float distance = length(UV * 1.6);
	float ripple = sin(distance * 38.0 - TIME * 1.8);
	float small_wave = sin(UV.x * 41.0 + TIME * 0.65) * sin(UV.y * 36.0 - TIME * 0.5);
	ALBEDO = water_color.rgb * (1.0 + ripple * 0.04 + small_wave * 0.025);
	ROUGHNESS = 0.24 + small_wave * 0.035;
	METALLIC = 0.22;
}
