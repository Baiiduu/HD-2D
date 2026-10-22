shader_type canvas_item;
uniform float hit = 0.0;
uniform float charge = 0.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV);
	c.rgb = mix(c.rgb, vec3(1.0, 0.91, 0.68), hit * 0.68);
	c.rgb += vec3(0.20, 0.075, 0.008) * charge * smoothstep(0.35, 0.9, c.r);
	COLOR = c;
}
