shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D effect_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 frame_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float opacity = 1.0;
uniform float reveal = 1.0;
uniform float glint = -1.0;

void fragment() {
	vec2 source_uv = frame_rect.xy + UV * frame_rect.zw;
	vec2 texel = floor(source_uv * vec2(textureSize(effect_texture, 0)));
	vec4 pixel = texture(effect_texture, source_uv);
	float stripe = glint < 0.0 ? 0.0 : 1.0 - step(2.0, abs(texel.x + texel.y * 0.5 - glint));
	vec3 color = mix(pixel.rgb, vec3(1.0, 0.98, 0.8), stripe * 0.8);
	ALBEDO = color;
	EMISSION = color * 0.3;
	ALPHA = pixel.a * opacity * step(source_uv.y, reveal);
}
