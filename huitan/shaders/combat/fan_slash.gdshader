shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D slash_texture : source_color, filter_nearest;
uniform vec4 frame_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 tint : source_color = vec4(1.0);
uniform float opacity = 0.85;
uniform float energy = 0.6;
uniform float leading_angle = 0.9;

void fragment() {
	vec4 effect = texture(slash_texture, frame_rect.xy + UV * frame_rect.zw);
	vec2 offset = UV - vec2(0.5);
	float angle = atan(offset.x, -offset.y);
	float reached = 1.0 - smoothstep(leading_angle - 0.03, leading_angle, angle);
	ALBEDO = effect.rgb * tint.rgb;
	EMISSION = effect.rgb * tint.rgb * energy;
	ALPHA = effect.a * tint.a * opacity * reached;
}
