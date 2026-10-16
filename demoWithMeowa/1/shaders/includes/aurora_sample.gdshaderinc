// No TIME here: animating the atlas must not rebuild the lighting cubemap.
group_uniforms aurora;
uniform bool aurora_enabled = false;
uniform sampler2D aurora_texture : filter_linear, repeat_enable;
uniform float aurora_strength : hint_range(0.0, 3.0) = 1.0;
group_uniforms;

vec3 sample_aurora(vec3 direction) {
	float elevation = asin(clamp(direction.y, -1.0, 1.0));
	vec2 uv = vec2(atan(direction.x, -direction.z) / TAU + 0.5,
		1.0 - clamp(elevation / (PI * 0.5), 0.0, 1.0));
	return texture(aurora_texture, uv).rgb * smoothstep(0.05, 0.18, elevation);
}
