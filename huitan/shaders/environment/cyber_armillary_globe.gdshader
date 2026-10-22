shader_type spatial;

uniform sampler2D albedo_atlas : source_color, filter_nearest, repeat_disable;
// Globe-only packing: R star phase (0 = steady), G roughness, B safe flow, A emission.
uniform sampler2D orm_atlas : filter_nearest, repeat_disable;
// Reuse the original mesh's atlas UVs without changing any geometry or UV data.
uniform vec4 original_uv_rect = vec4(0.01953125, 0.01953125, 0.5078125, 0.24609375);
uniform float longitude_offset : hint_range(-1.0, 1.0, 0.01) = -0.30;
uniform float seam_width : hint_range(0.0, 0.1, 0.005) = 0.04;
uniform float emission_energy : hint_range(0.0, 3.0, 0.05) = 1.2;
// The engine AnimationPlayer loops 0..TAU in 20 seconds and joins combat freeze.
uniform float motion_phase = 0.0;
uniform float flow_strength : hint_range(0.0, 0.02, 0.001) = 0.018;
uniform float flow_light_strength : hint_range(0.0, 0.6, 0.01) = 0.4;
uniform float twinkle_strength : hint_range(0.0, 0.25, 0.01) = 0.10;
uniform int twinkle_cycles : hint_range(1, 12, 1) = 5;

void fragment() {
	vec2 coord = (UV - original_uv_rect.xy) / original_uv_rect.zw;
	coord = vec2(fract(coord.x + longitude_offset), clamp(coord.y, 0.0, 1.0));
	vec3 color = texture(albedo_atlas, coord).rgb;
	vec4 properties = texture(orm_atlas, coord);
	// The native painting's opposite edges differ. Join only this narrow seam;
	// preserve the original texels everywhere else, including both dark caps.
	float edge = min(coord.x, 1.0 - coord.x);
	if (seam_width > 0.0 && edge < seam_width) {
		vec2 across = vec2(1.0 - coord.x, coord.y);
		float blend = 0.5 * (1.0 - smoothstep(0.0, seam_width, edge));
		color = mix(color, texture(albedo_atlas, across).rgb, blend);
		properties = mix(properties, texture(orm_atlas, across), blend);
	}
	vec3 glow = color * properties.a;
	float caps = smoothstep(0.08, 0.22, coord.y) * smoothstep(0.08, 0.22, 1.0 - coord.y);
	float join = smoothstep(seam_width, seam_width * 2.0 + 0.0001, edge);
	float flow = properties.b * caps * join;
	if (flow > 0.0 && flow_strength > 0.0) {
		vec2 drift = vec2(sin(motion_phase + coord.y * TAU * 2.0),
			0.4 * sin(motion_phase * 2.0 - coord.x * TAU));
		vec2 moving = coord + drift * flow_strength * caps * join;
		vec3 moved_color = texture(albedo_atlas, moving).rgb;
		float moved_emission = texture(orm_atlas, moving).a;
		color = mix(color, moved_color, flow);
		glow = mix(glow, moved_color * moved_emission, flow);
		// Broad light crests travel along the painted aurora. UV deformation alone
		// was too small to communicate movement at the formal map camera distance.
		float crest = sin(motion_phase * 2.0 - coord.x * TAU * 3.0 + coord.y * TAU);
		float stream = crest * flow_light_strength * flow;
		color *= 1.0 + stream * 0.45;
		glow *= 1.0 + stream;
	}
	if (properties.r > 0.0 && twinkle_strength > 0.0) {
		float pulse = sin(motion_phase * float(twinkle_cycles) + properties.r * TAU);
		color *= 1.0 + twinkle_strength * 0.25 * pulse;
		glow *= 1.0 + twinkle_strength * pulse;
	}
	ALBEDO = color * COLOR.rgb;
	AO = 1.0;
	ROUGHNESS = properties.g;
	METALLIC = 0.047;
	SPECULAR = 0.3;
	EMISSION = glow * emission_energy;
}
