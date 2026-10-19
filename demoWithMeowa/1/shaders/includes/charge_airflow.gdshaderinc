// Uniforms belong to the map's existing materials. Zero pull preserves other scenes.
uniform vec4 charge_field = vec4(0.0);
uniform float charge_pull = 0.0;

vec3 charge_airflow(vec3 point) {
	if (charge_pull <= 0.0 || charge_field.w <= 0.0) return vec3(0.0);
	vec2 toward = charge_field.xz - point.xz;
	float distance = length(toward);
	float influence = 1.0 - smoothstep(charge_field.w * 0.25, charge_field.w, distance);
	influence *= 1.0 - smoothstep(0.5, 2.5, abs(point.y - charge_field.y));
	vec2 inward = toward / max(distance, 0.15);
	vec2 swirl = vec2(-inward.y, inward.x) * 0.25;
	return vec3(inward.x + swirl.x, 0.0, inward.y + swirl.y) * influence * charge_pull;
}
