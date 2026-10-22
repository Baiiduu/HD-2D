shader_type fog;

// Density only: native spot lighting and its shadow map illuminate this volume.
// Unlike an emissive cone, blocked regions of the beam remain dark.
uniform float density : hint_range(0.0, 0.3, 0.005) = 0.07;
uniform vec3 scattering_color : source_color = vec3(0.9, 0.92, 0.95);

void fog() {
	float depth = 1.0 - UVW.y;
	float radius = mix(0.035, 0.5, clamp(depth, 0.0, 1.0));
	float radial = length(UVW.xz - vec2(0.5)) / radius;
	float edge = 1.0 - smoothstep(0.65, 1.0, radial);
	float ends = smoothstep(0.0, 0.06, depth) * (1.0 - smoothstep(0.92, 1.0, depth));
	DENSITY = density * edge * ends * mix(1.0, 0.65, depth);
	ALBEDO = scattering_color;
}
