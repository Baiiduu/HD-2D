shader_type canvas_item;
render_mode unshaded;

uniform vec4 glint_color : source_color = vec4(1.0, 0.93, 0.68, 1.0);

void fragment() {
	float light = dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	COLOR.rgb = mix(glint_color.rgb, vec3(1.0), smoothstep(0.65, 1.0, light)) * light * 1.6;
}
