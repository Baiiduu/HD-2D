shader_type spatial;
uniform vec4 plant_color : source_color = vec4(0.48, 0.65, 0.19, 1.0);
uniform float pixel_meters : hint_range(0.01, 0.08) = 0.0234375;
uniform float mottling : hint_range(0.0, 0.3) = 0.07;
uniform bool leaf_surface = false;
varying vec3 surface_position;

void vertex() {
	vec3 physical_scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	surface_position = VERTEX * physical_scale;
}

void fragment() {
	vec3 cell = floor(surface_position / pixel_meters);
	float pattern = fract(sin(dot(cell, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
	float variation = (floor(pattern * 4.0) / 3.0 - 0.5) * mottling;
	vec3 color = plant_color.rgb * (1.0 + variation);
	if (leaf_surface) {
		vec2 leaf_uv = floor(UV * vec2(24.0, 32.0)) / vec2(24.0, 32.0);
		float from_center = abs(leaf_uv.x - 0.5);
		float midrib = 1.0 - step(0.025, from_center);
		float branch = abs(fract((leaf_uv.y - from_center * 0.45) * 6.0 + 0.5) - 0.5);
		float veins = (1.0 - step(0.07, branch)) * step(0.04, from_center) * step(0.15, leaf_uv.y) * (1.0 - step(0.88, leaf_uv.y));
		color *= mix(0.78, 1.16, leaf_uv.y);
		color = mix(color, plant_color.rgb * 1.25, max(midrib * 0.42, veins * 0.22));
	}
	ALBEDO = color * COLOR.rgb;
	ROUGHNESS = 0.92;
	SPECULAR = 0.18;
}
