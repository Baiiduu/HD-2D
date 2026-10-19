shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D stroke_texture : filter_linear_mipmap, repeat_disable;
uniform sampler2D flow_noise : filter_linear_mipmap, repeat_enable;
uniform float attack_radius = 1.52;
uniform float attack_angle = 2.0944;
uniform float leading_angle = 0.0;
uniform float trail_angle = 1.675;
uniform float band_width = 0.54;
uniform float inner_ratio = 0.42;
uniform float pixel_size = 0.016;
uniform float visual_age = 0.0;
uniform float sweep_seconds = 0.1;
uniform float release = 0.0;
uniform float blade_presence = 1.0;
uniform float opacity = 0.9;
uniform float energy = 1.15;
uniform float flow_speed = 1.6;
uniform float distortion = 0.07;
uniform float wake_strength = 0.45;
uniform float spark_strength = 0.65;
uniform bool blade_enabled = true;
uniform bool trail_enabled = true;
uniform vec2 plane_slope = vec2(0.0);
uniform vec4 blade_color : source_color = vec4(1.0, 0.95, 0.80, 1.0);
uniform vec4 middle_color : source_color = vec4(1.0, 0.50, 0.22, 0.9);
uniform vec4 tail_color : source_color = vec4(0.82, 0.10, 0.23, 0.78);

void vertex() {
	VERTEX.y += dot(VERTEX.xz, plane_slope);
}

float hash(float value) {
	return fract(sin(value * 127.1 + 311.7) * 43758.5453);
}

float brush(vec2 uv) {
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	// 直接采样原生 Meowa 笔触中部，不裁切、重采样或重新像素化源图。
	return texture(stroke_texture, vec2(uv.x, 0.31 + uv.y * 0.34)).r * inside;
}

float motes(vec2 point) {
	float result = 0.0;
	// 显式年龄驱动的六枚解析亮点；随同一节点复用、冻结和实时裁切。
	for (int i = 0; i < 6; i++) {
		float id = float(i);
		float phase = 0.15 + id * 0.12;
		float age = visual_age - sweep_seconds * phase;
		float life = 0.10 + hash(id + 4.0) * 0.08;
		float live = step(0.0, age) * (1.0 - step(life, age));
		float angle = -attack_angle * 0.5 + attack_angle * phase;
		vec2 direction = vec2(sin(angle), -cos(angle));
		vec2 tangent = vec2(-direction.y, direction.x);
		vec2 center = direction * attack_radius * (0.55 + hash(id) * 0.28);
		center += (tangent * (1.2 + hash(id + 1.0)) + direction * 0.4) * max(age, 0.0);
		vec2 delta = point - center;
		vec2 local = vec2(dot(delta, tangent), dot(delta, direction));
		vec2 size = vec2(0.055, 0.012) * (1.0 - clamp(age / life, 0.0, 1.0));
		float mark = 1.0 - smoothstep(0.65, 1.0, length(local / max(size, vec2(0.001))));
		result = max(result, mark * live);
	}
	return result * spark_strength;
}

void fragment() {
	vec2 point = (UV - vec2(0.5)) * (2.0 * attack_radius);
	float span = max(trail_angle, 0.001);
	vec2 head = vec2(sin(leading_angle), -cos(leading_angle)) * (attack_radius - pixel_size);
	vec2 root = vec2(sin(leading_angle - span), -cos(leading_angle - span)) * attack_radius * inner_ratio;
	vec2 control = vec2(sin(leading_angle - span * 0.68), -cos(leading_angle - span * 0.68)) * attack_radius * 0.88;
	vec2 chord = head - root;
	float along = clamp(dot(point - root, chord) / max(dot(chord, chord), 0.00001), 0.0, 1.0);
	vec2 acceleration = 2.0 * (head - 2.0 * control + root);
	// 在承载网格内寻找二次曲线上的最近点，UV 沿笔触而非整片圆环展开。
	for (int j = 0; j < 5; j++) {
		vec2 curve = mix(mix(root, control, along), mix(control, head, along), along);
		vec2 tangent = 2.0 * mix(control - root, head - control, along);
		float denominator = dot(tangent, tangent) + dot(curve - point, acceleration);
		along = clamp(along - dot(curve - point, tangent) / max(denominator, 0.0001), 0.0, 1.0);
	}
	vec2 curve = mix(mix(root, control, along), mix(control, head, along), along);
	vec2 tangent = normalize(mix(control - root, head - control, along));
	float tail = 1.0 - along;
	float reached = step(0.001, along) * step(along, 0.999);
	float width = max(0.001, band_width * mix(0.55, 1.0, sin(along * 3.141593)));
	float across = 0.5 + dot(point - curve, vec2(-tangent.y, tangent.x)) / width;
	vec2 uv = vec2(along, across);
	float clock = visual_age * flow_speed;
	float noise = texture(flow_noise, vec2(tail * 2.3 - clock, across * 0.7)).r;
	float thin_noise = texture(flow_noise, vec2(tail * 5.1 - clock * 1.4, across * 1.8 + 0.3)).r;
	vec2 warped = uv + vec2((noise - 0.5) * 0.025, (noise - 0.5) * distortion);
	float painted = brush(warped);
	float wake = brush(vec2(uv.x * 0.95 + 0.035, (uv.y - 0.52) * 1.7 + (thin_noise - 0.5) * distortion));
	wake *= wake_strength * smoothstep(0.15, 0.50, tail);
	float erosion = smoothstep(0.0, 0.96, release);
	float density = painted * mix(0.76, 1.1, thin_noise);
	float body = smoothstep(0.045 + erosion * 0.75, 0.12 + erosion * 0.85, density);
	float trailing = max(body * 0.76, wake * (1.0 - erosion)) * reached;
	float front = 1.0 - smoothstep(0.25, 0.85, tail);
	float blade = smoothstep(0.18, 0.70, painted) * front * blade_presence * reached;
	if (!blade_enabled) { blade = 0.0; }
	if (!trail_enabled) { trailing = 0.0; }
	float edge = clamp((density - erosion * 0.8) * 1.7, 0.0, 1.0);
	vec4 color = mix(tail_color, middle_color, edge * 0.65);
	color = mix(color, blade_color, blade);
	float flecks = motes(point);
	float alpha = max(max(blade, trailing), flecks) * (1.0 - smoothstep(0.65, 1.0, release));
	color.rgb = mix(color.rgb, blade_color.rgb, flecks);
	ALBEDO = color.rgb;
	EMISSION = color.rgb * energy * (0.24 + max(blade, flecks) * 0.76);
	ALPHA = alpha * color.a * opacity;
}
