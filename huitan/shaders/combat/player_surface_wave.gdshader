shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never, depth_test_disabled, shadows_disabled, fog_disabled;

uniform sampler2D scene_depth : hint_depth_texture, filter_nearest, repeat_disable;
instance uniform vec4 wave_shape = vec4(1.15, 0.28, 0.035, 1.4);
instance uniform float wave_progress = 0.0;
varying flat vec3 center;
varying flat vec3 across;
varying flat vec3 upwards;
varying flat vec3 outward;

void vertex() {
	center = MODEL_MATRIX[3].xyz;
	across = normalize(MODEL_MATRIX[0].xyz);
	upwards = normalize(MODEL_MATRIX[1].xyz);
	outward = normalize(MODEL_MATRIX[2].xyz);
}

void fragment() {
	float depth = texture(scene_depth, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#endif
	vec4 scene = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 world = scene.xyz / scene.w;
	vec3 relative = world - center;
	vec3 local = vec3(dot(relative, across), dot(relative, upwards), dot(relative, outward));
	vec3 surface_normal = normalize(cross(dFdx(world), dFdy(world)));
	float alignment = abs(dot(surface_normal, outward));
	// Reject floor, sky, objects in front of the contact, and empty air walls.
	if (abs(local.z) > wave_shape.y || alignment < 0.55 || depth < 0.00001) { discard; }
	vec2 pixel = floor(local.xy / 0.025) * 0.025;
	float radius = length(pixel);
	float maximum = max(wave_shape.x, 0.01);
	float p = clamp(wave_progress, 0.0, 1.0);
	float front = maximum * (0.08 + 0.92 * (1.0 - pow(1.0 - p, 2.0)));
	float width = wave_shape.z;
	float ring = 1.0 - smoothstep(width * 0.4, width * 1.6, abs(radius - front));
	float inner = (1.0 - smoothstep(width * 0.5, width * 1.5, abs(radius - front * 0.72))) * 0.32;
	float angle = atan(pixel.y, pixel.x);
	float broken = smoothstep(-0.6, 0.15, sin(angle * 5.0 + radius * 6.0)) * 0.7 + 0.3;
	float fade = (1.0 - smoothstep(0.18, 1.0, p)) * smoothstep(0.0, 0.04, p);
	float mask = (ring + inner) * broken * fade * (1.0 - smoothstep(maximum * 0.9, maximum, radius));
	mask *= smoothstep(0.55, 0.85, alignment);
	ALBEDO = vec3(0.0);
	EMISSION = mix(vec3(1.0, 0.51, 0.18), vec3(1.0, 0.94, 0.73), ring) * wave_shape.w;
	ALPHA = mask;
}
