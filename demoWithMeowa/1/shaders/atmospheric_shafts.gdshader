shader_type fog;

// Distant world-space air. The map and its surrounding safety margin are excluded.
uniform vec3 origins[3];
uniform vec3 directions[3];
uniform vec3 ray_right;
uniform vec3 ray_up;
uniform sampler2D shaft_mask : repeat_disable, filter_linear;
uniform float ray_length = 26.0;
uniform float beam_width = 1.4;
uniform float density = 0.006;
uniform float upper_air_gain = 4.0;
uniform float texture_strength = 0.3;
uniform float haze_clock = 0.0;
uniform float halo_strength = 0.2;
uniform vec3 glow_color : source_color = vec3(1.0, 0.83, 0.55);
uniform vec4 exclusion_bounds = vec4(-20.0, -18.4, 44.0, 18.4);

float wisp(vec3 p) {
	return 0.65 + 0.20 * sin(p.x * 0.53 + p.y * 0.31 + haze_clock * 0.12)
		+ 0.15 * sin(p.z * 0.71 - p.y * 0.23 - haze_clock * 0.08);
}

void fog() {
	float beams = 0.0;
	float glow = 0.0;
	for (int i = 0; i < 3; i++) {
		vec3 offset = WORLD_POSITION - origins[i];
		float along = dot(offset, directions[i]);
		float t = clamp(along / ray_length, 0.0, 1.0);
		float radius = max(0.08, beam_width * 1.25 * t);
		float radial = length(offset - directions[i] * along) / radius;
		float edge = exp(-radial * radial * 0.8) * (1.0 - smoothstep(0.75, 1.0, radial));
		float ends = smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.97, 1.08, t));
		vec2 projected_uv = vec2(dot(offset, ray_right), dot(offset, ray_up)) / (radius * 2.0) + 0.5;
		float pattern = textureLod(shaft_mask, projected_uv, 0.0).r;
		beams += edge * ends * pattern;
		float halo_radius = length(offset - directions[i] * along) / max(beam_width * 2.5, 1.0);
		glow += exp(-halo_radius * halo_radius * 1.5) * exp(-pow((t - 0.3) * 4.5, 2.0));
	}
	vec2 outside = max(exclusion_bounds.xy - WORLD_POSITION.xz, WORLD_POSITION.xz - exclusion_bounds.zw);
	float distant_only = smoothstep(0.0, 4.0, max(outside.x, outside.y));
	float ground_fade = smoothstep(0.05, 0.9, WORLD_POSITION.y);
	float upper = mix(1.0, upper_air_gain, smoothstep(2.5, 7.0, WORLD_POSITION.y));
	DENSITY = density * (beams + glow * halo_strength * 0.15) * distant_only * ground_fade
		* upper * mix(1.0, wisp(WORLD_POSITION), texture_strength);
	ALBEDO = vec3(0.92, 0.94, 0.97);
	// A very weak diffuse halo, without a visible solar disc or full-screen exposure change.
	EMISSION = glow_color * glow * halo_strength * 0.25 * distant_only * ground_fade;
}
