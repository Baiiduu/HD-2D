shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D airflow_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float flow_opacity : hint_range(0.0, 1.0) = 0.5;
uniform vec4 brush_region = vec4(0.0, 0.0, 1.0, 1.0);

void fragment() {
	// GPUParticles aligns local Y to velocity. Rotate UVs, preserving the source
	// pixels, so the native horizontal brush follows that axis.
	vec2 uv = brush_region.xy + vec2(UV.y, UV.x) * brush_region.zw;
	vec4 ink = texture(airflow_texture, uv);
	// The brush is a grayscale mask. Discard the dark canvas rather than drawing
	// a rectangular gray card, and retain an antialiased continuous stroke.
	float mask = smoothstep(0.04, 0.6, max(ink.r, max(ink.g, ink.b)));
	ALBEDO = COLOR.rgb;
	EMISSION = COLOR.rgb * 0.35;
	ALPHA = ink.a * mask * COLOR.a * flow_opacity;
}
