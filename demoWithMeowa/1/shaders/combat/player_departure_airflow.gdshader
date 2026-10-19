shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D airflow_texture : source_color, filter_nearest, repeat_disable;
instance uniform float progress = 0.0;
instance uniform float opacity = 0.65;
instance uniform vec4 wall_plane = vec4(0.0);
varying vec3 airflow_world_position;

void vertex() {
	airflow_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	if (dot(wall_plane.xyz, airflow_world_position) + wall_plane.w < 0.01) { discard; }
	vec4 ink = texture(airflow_texture, UV);
	vec2 cell = floor(UV * vec2(textureSize(airflow_texture, 0)) / 2.0);
	float breakup = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	float dissolve = 1.0 - smoothstep(breakup * 0.65 + 0.2, breakup * 0.65 + 0.35, progress);
	ALBEDO = ink.rgb;
	EMISSION = ink.rgb * 0.3;
	ALPHA = ink.a * opacity * (1.0 - smoothstep(0.15, 1.0, progress)) * dissolve;
}
