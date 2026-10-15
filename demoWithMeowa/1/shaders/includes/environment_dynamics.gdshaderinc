// Spatial weights are evaluated at each plant/particle's world position, not the camera.
uniform bool ambient_dynamics_enabled = false;
uniform vec4 ambient_home_bounds = vec4(0.0);
uniform vec4 ambient_core_bounds = vec4(0.0);
uniform vec4 ambient_activity_bounds = vec4(0.0);
uniform float ambient_region_blend = 4.0;

float ambient_rect_weight(vec2 point, vec4 bounds) {
	vec2 edge = abs(point - bounds.xy - bounds.zw * 0.5) - bounds.zw * 0.5;
	float distance = max(edge.x, edge.y);
	return 1.0 - smoothstep(-ambient_region_blend * 0.5, ambient_region_blend * 0.5, distance);
}

vec4 ambient_region_weights(vec2 point) {
	float core = ambient_rect_weight(point, ambient_core_bounds);
	float activity = max(core, ambient_rect_weight(point, ambient_activity_bounds));
	float home = ambient_rect_weight(point, ambient_home_bounds) * (1.0 - activity);
	return vec4(home, core, activity - core, 1.0 - activity - home);
}
