shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D stroke_texture : filter_nearest, repeat_disable;
uniform sampler2D flow_noise : filter_linear_mipmap, repeat_enable;
uniform float attack_radius = 1.52;
uniform float attack_angle = 6.283185;
uniform float leading_angle = 0.0;
uniform float trail_angle = 2.617994;
uniform float band_width = 0.28;
uniform float inner_ratio = 0.58;
uniform float pixel_size = 0.016;
uniform float visual_age = 0.0;
uniform float sweep_seconds = 0.1;
uniform float release = 0.0;
uniform float blade_presence = 1.0;
uniform float opacity = 0.9;
uniform float energy = 0.85;
uniform float flow_speed = 1.6;
uniform float distortion = 0.07;
uniform float wake_strength = 0.4;
uniform float spark_strength = 0.4;
uniform float secondary_strength = 0.24;
uniform float secondary_offset = 2.356194;
uniform bool blade_enabled = true;
uniform bool trail_enabled = true;
uniform vec2 plane_slope = vec2(0.0);
uniform vec4 blade_color : source_color = vec4(1.0, 0.95, 0.80, 1.0);
uniform vec4 middle_color : source_color = vec4(1.0, 0.50, 0.22, 0.9);
uniform vec4 tail_color : source_color = vec4(0.82, 0.10, 0.23, 0.78);

void vertex() {
	VERTEX.y += dot(VERTEX.xz, plane_slope);
}

float brush(vec2 uv) {
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	return texture(stroke_texture, vec2(uv.x, 0.31 + uv.y * 0.34)).r * inside;
}

// x 是尾迹，y 是短亮刃；两层共用原生笔触，只沿真实刀锋之后展开。
vec2 stroke(vec2 point, float head, float span, float inset, float width_scale) {
	// span is draw-uniform; keep per-pixel mip derivatives on the original path.
	if (span < 0.001) { return vec2(0.0); }
	float theta = atan(point.x, -point.y);
	float behind = mod(head - theta + 6.283185, 6.283185);
	float length_limit = max(span, 0.001);
	float along = 1.0 - behind / length_limit;
	float reached = step(0.001, span) * step(0.0, along) * step(along, 1.0);
	float width = max(band_width * width_scale * mix(0.32, 1.0, smoothstep(0.0, 0.35, along)), 0.001);
	float center = attack_radius - pixel_size - band_width * (0.55 + inset + (1.0 - along) * 0.3);
	float across = 0.5 + (length(point) - center) / width;
	vec2 uv = vec2(along, across);
	float clock = visual_age * flow_speed;
	float noise = texture(flow_noise, vec2(along * 2.3 - clock, across * 0.7)).r;
	float fine = texture(flow_noise, vec2(along * 5.1 - clock * 1.4, across * 1.8 + 0.3)).r;
	float painted = brush(uv + vec2((noise - 0.5) * 0.02, (noise - 0.5) * distortion));
	float wake = brush(vec2(along * 0.95 + 0.035, (across - 0.52) * 1.7 + (fine - 0.5) * distortion));
	float erosion = smoothstep(0.0, 0.96, release);
	float density = painted * mix(0.76, 1.1, fine);
	float body = smoothstep(0.045 + erosion * 0.75, 0.12 + erosion * 0.85, density);
	float tail = max(body * 0.78, wake * wake_strength * (1.0 - erosion));
	tail *= smoothstep(0.0, 0.18, along) * reached;
	float blade = smoothstep(0.2, 0.75, painted) * (1.0 - smoothstep(0.025, 0.16, behind / length_limit));
	blade *= blade_presence * reached;
	return vec2(tail, blade);
}

float spark_flecks(vec2 point, float trailing) {
	vec2 grain_uv = vec2(point.x * 4.0 - visual_age * flow_speed, point.y * 4.0);
	// 分支前计算原坐标的梯度，避免跳过空白像素后改变 mip 采样。
	vec2 grain_dx = dFdx(grain_uv);
	vec2 grain_dy = dFdy(grain_uv);
	float flecks = 0.0;
	if (trailing != 0.0 && spark_strength != 0.0) {
		float grain = textureGrad(flow_noise, grain_uv, grain_dx, grain_dy).r;
		flecks = step(0.86, grain) * trailing * spark_strength * 0.35;
	}
	return flecks;
}

void fragment() {
	vec2 point = (UV - vec2(0.5)) * (2.0 * attack_radius);
	float covered = max(0.0, leading_angle + attack_angle * 0.5);
	vec2 primary_stroke = stroke(point, leading_angle, min(trail_angle, covered), 0.0, 1.0);
	float secondary_span = min(trail_angle * 0.65, max(0.0, covered - secondary_offset));
	vec2 secondary = stroke(point, leading_angle - secondary_offset, secondary_span, 0.65, 0.55);
	// 交错层是旧刀势的低亮余迹，不增加第二道可造成伤害的亮刃。
	float trailing = max(primary_stroke.x, secondary.x * secondary_strength);
	float blade = primary_stroke.y;
	if (!blade_enabled) { blade = 0.0; }
	if (!trail_enabled) { trailing = 0.0; }
	float flecks = spark_flecks(point, trailing);
	vec4 color = mix(tail_color, middle_color, clamp(primary_stroke.x * 0.55 + flecks, 0.0, 1.0));
	color = mix(color, blade_color, blade);
	float clearance = smoothstep(attack_radius * inner_ratio, attack_radius * inner_ratio + pixel_size, length(point));
	float alpha = max(trailing, blade) * clearance * (1.0 - smoothstep(0.5, 1.0, release));
	ALBEDO = color.rgb;
	EMISSION = color.rgb * energy * (0.22 + blade * 0.78 + flecks);
	ALPHA = alpha * color.a * opacity;
}
