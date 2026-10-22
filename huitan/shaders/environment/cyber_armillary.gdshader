shader_type spatial;

uniform sampler2D albedo_atlas : source_color, filter_nearest, repeat_disable;
// RGB = AO / roughness / metallic; alpha stores the emission mask.
uniform sampler2D orm_atlas : filter_nearest, repeat_disable;
uniform float emission_energy : hint_range(0.0, 5.0, 0.05) = 1.7;

void fragment() {
	vec3 color = texture(albedo_atlas, UV).rgb;
	vec4 properties = texture(orm_atlas, UV);
	ALBEDO = color * COLOR.rgb;
	AO = properties.r;
	ROUGHNESS = properties.g;
	METALLIC = properties.b;
	SPECULAR = 0.3;
	EMISSION = color * properties.a * emission_energy;
}
