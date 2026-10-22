shader_type canvas_item;
render_mode unshaded;

// Render once to an angular atlas shared by the visible sky and wet stone.
uniform float aurora_clock = 0.0;
uniform vec3 green_color : source_color = vec3(0.22, 0.95, 0.66);
uniform vec3 blue_color : source_color = vec3(0.20, 0.48, 1.0);
uniform vec3 purple_color : source_color = vec3(0.48, 0.29, 0.76);
uniform vec3 pink_color : source_color = vec3(0.95, 0.30, 0.64);

vec3 curtain(float azimuth, float elevation, float phase, float height_offset) {
	float drift = aurora_clock * 0.065;
	float a = azimuth + phase + sin(aurora_clock * 0.035 + phase) * 0.045;
	float fold = sin(a * 3.0 + sin(a * 2.0 - drift) * 0.8 + drift);
	float base = 0.61 + height_offset + fold * 0.075
		+ sin(a * 7.0 - drift * 0.7) * 0.035;
	float height = elevation - base;
	float extent = 0.18 + 0.055 * sin(a * 4.0 + drift * 0.4);
	float vertical = smoothstep(-0.025, 0.018, height)
		* (1.0 - smoothstep(extent * 0.62, extent, height));
	// Periodic coordinates keep the 360-degree seam continuous.
	float thread = sin(a * 93.0 + sin(a * 17.0 + drift) * 2.0 - drift * 1.8);
	float fine = sin(a * 177.0 + sin(a * 11.0 - drift) * 2.5 + drift);
	float filaments = 0.25 + pow(thread * 0.5 + 0.5, 3.0) * 0.60
		+ (fine * 0.5 + 0.5) * 0.15;
	float opening = smoothstep(-0.55, 0.65, sin(a * 4.0 + sin(a * 2.0) * 0.7 + drift * 0.35));
	float veil = vertical * filaments * (0.08 + opening * 0.92);
	float foot = exp(-abs(height) * 75.0) * 0.28 * (0.5 + filaments * 0.5);
	float tier = clamp(height / extent, 0.0, 1.0);
	vec3 tint = mix(green_color, blue_color, smoothstep(0.04, 0.36, tier));
	tint = mix(tint, purple_color, smoothstep(0.30, 0.60, tier));
	tint = mix(tint, pink_color, smoothstep(0.65, 0.9, tier) * 0.65);
	return tint * (veil * 0.78 + foot);
}

void fragment() {
	float azimuth = (UV.x - 0.5) * TAU;
	float elevation = (1.0 - UV.y) * (PI * 0.5);
	vec3 color = curtain(azimuth, elevation, 0.0, 0.0);
	color += curtain(azimuth, elevation, 1.7, 0.105) * 0.26;
	COLOR = vec4(color, 1.0);
}
