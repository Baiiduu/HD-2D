shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D slash_texture : source_color, filter_nearest, repeat_disable;
uniform vec4 frame_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float opacity = 0.9;
uniform float energy = 0.15;
uniform float leading_angle = 0.0;
uniform float half_angle = 1.05;
uniform float art_angle = 0.0;
uniform float fade = 1.0;
uniform vec2 plane_slope = vec2(0.0);
uniform vec2 art_scale = vec2(2.357895);

void vertex() {
	VERTEX.y += dot(VERTEX.xz, plane_slope);
}

void fragment() {
	vec2 offset = UV - vec2(0.5);
	float angle = atan(offset.x, -offset.y);
	float reached = step(angle, leading_angle);
	float end_progress = clamp(min(leading_angle - angle, angle + half_angle) / 0.35, 0.0, 1.0);
	float tapered = step(1.0 - end_progress, length(offset * art_scale));
	float c = cos(art_angle);
	float s = sin(art_angle);
	vec2 art_uv = vec2(c * offset.x - s * offset.y, s * offset.x + c * offset.y) + vec2(0.5);
	vec4 effect = texture(slash_texture, frame_rect.xy + art_uv * frame_rect.zw);
	ALBEDO = effect.rgb;
	EMISSION = effect.rgb * energy;
	ALPHA = effect.a * opacity * reached * tapered * fade;
}
