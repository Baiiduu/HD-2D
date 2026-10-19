shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform float attack_radius = 1.52;
uniform float leading_angle = 0.0;
uniform float trail_angle = 1.36;
uniform float band_width = 0.22;
uniform float inner_ratio = 0.56;
uniform float pixel_size = 0.016;
uniform float release = 0.0;
uniform float blade_presence = 1.0;
uniform float opacity = 0.9;
uniform float energy = 0.65;
uniform bool blade_enabled = true;
uniform bool trail_enabled = true;
uniform vec2 plane_slope = vec2(0.0);
uniform vec4 blade_color : source_color = vec4(1.0, 0.95, 0.80, 1.0);
uniform vec4 middle_color : source_color = vec4(1.0, 0.55, 0.18, 0.88);
uniform vec4 tail_color : source_color = vec4(0.88, 0.10, 0.23, 0.72);

void vertex() {
	VERTEX.y += dot(VERTEX.xz, plane_slope);
}

float grain(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	// 承载网格遵守真实扇区及挡墙；在其中绘制向腰侧收拢的弧形丝带。
	vec2 raw = (UV - vec2(0.5)) * (2.0 * attack_radius);
	vec2 point = floor(raw / pixel_size + vec2(0.5)) * pixel_size;
	float lag = leading_angle - atan(point.x, -point.y);
	float tail = clamp(lag / max(trail_angle, 0.001), 0.0, 1.0);
	float reached = step(0.0, lag) * step(lag, trail_angle);
	float taper = smoothstep(0.0, 0.045, tail) * pow(1.0 - tail, 0.75);
	float outside = (attack_radius - pixel_size * 0.5) * mix(inner_ratio, 1.0, pow(1.0 - tail, 0.48));
	float width = max(pixel_size * 0.25, min(band_width, outside * 0.75) * taper);
	float across = (outside - length(point)) / width;
	float main = step(0.0, across) * step(across, 0.60);
	float strand = step(0.80, across) * step(across, 1.0) * smoothstep(0.12, 0.35, tail);
	float body = max(main, strand) * reached;
	// 细长主笔触与分离的拖丝，中间留空，不铺满彩色弧面。
	float front = 1.0 - smoothstep(0.26, 0.80, tail);
	float blade = blade_enabled ? main * front * blade_presence : 0.0;
	vec4 color = mix(tail_color, middle_color, front * 0.50);
	color = mix(color, blade_color, blade);
	// 图案固定在本刀局部坐标；显式 release 控制破碎，不使用 TIME。
	float noise = grain(floor(point / (pixel_size * 2.0)));
	float erosion = smoothstep(0.08, 0.95, release) * 0.92;
	float breakup = step(erosion + smoothstep(0.60, 1.0, tail) * 0.12, noise);
	float kept_blade = blade_enabled ? blade : 0.0;
	float kept_trail = trail_enabled ? mix(0.75, 0.40, tail) * breakup : 0.0;
	float alpha = max(kept_blade, kept_trail) * body * (1.0 - smoothstep(0.45, 1.0, release));
	ALBEDO = color.rgb;
	EMISSION = color.rgb * energy * mix(0.30, 1.0, kept_blade);
	ALPHA = alpha * color.a * opacity;
}
