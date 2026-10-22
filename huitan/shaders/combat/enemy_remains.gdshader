shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D effect_texture : source_color, filter_nearest, repeat_disable;
instance uniform vec4 frame_rect : instance_index(1) = vec4(0.0, 0.0, 1.0, 1.0);
instance uniform float opacity : instance_index(2) = 1.0;
instance uniform vec4 tint : source_color, instance_index(3) = vec4(1.0);
instance uniform float hit_flash : instance_index(4) = 0.0;
instance uniform float death_energy : instance_index(5) = 0.0;
instance uniform float wave_finish_silhouette : instance_index(0) = 0.0;
instance uniform float hit_silhouette_amount : instance_index(6) = 0.0;
instance uniform vec4 hit_silhouette_rim_color : source_color, instance_index(7) = vec4(1.0, 0.96, 0.82, 1.0);
void fragment() {
	vec4 pixel = texture(effect_texture, frame_rect.xy + UV * frame_rect.zw);
	ALBEDO = mix(pixel.rgb * tint.rgb, vec3(1.0), hit_flash);
	EMISSION = ALBEDO * death_energy;
	float silhouette = max(wave_finish_silhouette, hit_silhouette_amount);
	if (silhouette > 0.0) {
		vec2 uv = frame_rect.xy + UV * frame_rect.zw;
		vec2 texel = 1.0 / vec2(textureSize(effect_texture, 0));
		vec2 low = min(frame_rect.xy, frame_rect.xy + frame_rect.zw) + texel * 0.5;
		vec2 high = max(frame_rect.xy, frame_rect.xy + frame_rect.zw) - texel * 0.5;
		float edge = min(texture(effect_texture, clamp(uv + vec2(texel.x, 0.0), low, high)).a,
			texture(effect_texture, clamp(uv - vec2(texel.x, 0.0), low, high)).a);
		edge = min(edge, min(texture(effect_texture, clamp(uv + vec2(0.0, texel.y), low, high)).a,
			texture(effect_texture, clamp(uv - vec2(0.0, texel.y), low, high)).a));
		vec3 rim = wave_finish_silhouette > 0.0 ? vec3(1.0, 0.84, 0.52) : hit_silhouette_rim_color.rgb;
		ALBEDO = mix(ALBEDO, vec3(0.008, 0.012, 0.025), silhouette);
		EMISSION = mix(EMISSION, rim * (1.0 - edge), silhouette);
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	ALPHA = pixel.a * opacity * tint.a;
}
