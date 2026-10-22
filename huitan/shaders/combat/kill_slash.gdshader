shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D slash_texture : source_color, filter_nearest, repeat_disable;
uniform float slash_clock = 0.0;
varying float life_progress;

void vertex() {
	float age = max(0.0, slash_clock - INSTANCE_CUSTOM.w);
	life_progress = age / max(COLOR.a, 0.001);
	vec3 normal = INV_VIEW_MATRIX[2].xyz;
	vec3 heading = INSTANCE_CUSTOM.xyz;
	vec3 axis = heading - normal * dot(heading, normal);
	if (length(axis) < 0.001) axis = INV_VIEW_MATRIX[0].xyz;
	axis = normalize(axis);
	mat4 facing = MODEL_MATRIX;
	facing[0].xyz = axis * length(MODEL_MATRIX[0].xyz);
	facing[1].xyz = normalize(cross(normal, axis)) * length(MODEL_MATRIX[1].xyz);
	facing[2].xyz = normal;
	facing[3].xyz += heading * age * 1.4;
	MODELVIEW_MATRIX = VIEW_MATRIX * facing;
}

void fragment() {
	// 快速拉开原生长刃，后半段按像素破碎，不拉伸或重画素材。
	if (life_progress >= 1.0 || UV.x > smoothstep(0.0, 0.14, life_progress)) discard;
	vec4 pixel = texture(slash_texture, UV);
	vec2 cell = floor(UV * vec2(textureSize(slash_texture, 0)));
	float grain = fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
	if (grain < smoothstep(0.42, 1.0, life_progress) * 0.95) discard;
	ALBEDO = pixel.rgb;
	EMISSION = pixel.rgb * 0.55;
	ALPHA = pixel.a * (1.0 - smoothstep(0.35, 1.0, life_progress));
}
