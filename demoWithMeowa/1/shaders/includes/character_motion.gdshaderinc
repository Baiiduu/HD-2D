// World-space rigid rotation about the feet; every character pass uses this card.
vec3 character_motion_rotate(vec3 value, vec3 axis, float sine, float cosine) {
	return value * cosine + cross(axis, value) * sine + axis * dot(axis, value) * (1.0 - cosine);
}

mat4 character_motion_card(mat4 card, vec3 pivot, vec3 lean) {
	float angle = length(lean);
	if (angle < 0.000001) { return card; }
	vec3 axis = lean / angle;
	float sine = sin(angle);
	float cosine = cos(angle);
	return mat4(vec4(character_motion_rotate(card[0].xyz, axis, sine, cosine), 0.0),
		vec4(character_motion_rotate(card[1].xyz, axis, sine, cosine), 0.0),
		vec4(character_motion_rotate(card[2].xyz, axis, sine, cosine), 0.0),
		vec4(pivot + character_motion_rotate(card[3].xyz - pivot, axis, sine, cosine), 1.0));
}
