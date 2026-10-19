shader_type canvas_item;
uniform float clock = 0.0;
uniform float motion = 1.0;
void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float warm = smoothstep(0.04, 0.35, base.r - base.b * 0.8);
	float sheen = sin(UV.y * 190.0 + UV.x * 26.0 + clock * 1.8);
	float ripple = sin(UV.y * 321.0 - clock * 2.1);
	float wet = smoothstep(0.37, 0.9, UV.y);
	base.rgb *= 1.0 + motion * warm * (sin(clock * 2.2 + UV.x * 9.0) * 0.028 + sheen * ripple * wet * 0.065);
	float vignette = smoothstep(0.30, 0.84, length((UV - 0.5) * vec2(1.0, 0.78)));
	base.rgb *= 1.0 - vignette * 0.30;
	COLOR = base;
}
