shader_type canvas_item;
render_mode unshaded;

uniform float visible_fraction = 0.0;
uniform float sweep_position = 0.0;
uniform float sweep_width = 0.08;
uniform float sweep_strength = 0.0;
uniform vec4 sweep_color : source_color = vec4(1.0, 0.97, 0.8, 1.0);

void fragment() {
	// UV belongs to the full Meowa strip; only travel across earned experience.
	float width = max(sweep_width, 0.001);
	float center = mix(-width, visible_fraction + width, sweep_position);
	float slant = (UV.y - 0.5) * width * 0.55;
	float distance_to_band = (UV.x - center + slant) / width;
	float band = exp(-distance_to_band * distance_to_band * 3.0);
	COLOR.rgb += sweep_color.rgb * band * sweep_strength;
	// Preserve the source alpha; never illuminate transparent sprite margins.
}
