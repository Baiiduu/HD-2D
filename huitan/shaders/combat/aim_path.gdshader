shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(0.9, 0.82, 0.66, 1.0);
uniform float opacity = 0.45;
uniform float dash_period = 0.224;
varying vec4 segment;

void vertex() {
	segment = INSTANCE_CUSTOM;
}

void fragment() {
	float along = segment.x + UV.x * segment.y;
	float dash = 1.0 - step(0.45, fract(along / dash_period));
	ALBEDO = tint.rgb;
	ALPHA = dash * mix(segment.z, segment.w, UV.x) * opacity * tint.a;
}
