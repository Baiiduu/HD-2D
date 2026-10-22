shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled, skip_vertex_transform;

uniform sampler2D mask_atlas : filter_nearest, repeat_disable;
uniform float effect_clock = 0.0;
uniform vec4 shadow_color : source_color = vec4(0.055, 0.065, 0.14, 1.0);
uniform vec4 rim_color : source_color = vec4(0.92, 0.65, 0.32, 1.0);
uniform float shadow_opacity = 0.48;
uniform float rim_opacity = 0.62;
uniform float fade_seconds = 0.12;
uniform float contraction = 0.18;
varying flat vec4 tile_region;
varying flat vec2 stage;

void vertex() {
	float progress = clamp((effect_clock - INSTANCE_CUSTOM.r) / max(INSTANCE_CUSTOM.g, 0.001), 0.0, 1.0);
	float released = INSTANCE_CUSTOM.b;
	float fade = released < 0.0 ? 1.0 : 1.0 - smoothstep(0.0, max(fade_seconds, 0.001), effect_clock - released);
	float tighten = 1.0 - contraction * smoothstep(0.55, 1.0, progress);
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	vec3 away = cross(vec3(0.0, 1.0, 0.0), right);
	// 脚底固定在预留落点，Q/E 只调整贴地朝向；不跟随人物或相机位移。
	vec3 point = MODEL_MATRIX[3].xyz + right * VERTEX.x * length(MODEL_MATRIX[0].xyz) * tighten
		+ away * (VERTEX.y + 0.5) * length(MODEL_MATRIX[1].xyz) * tighten;
	VERTEX = (VIEW_MATRIX * vec4(point, 1.0)).xyz;
	tile_region = COLOR;
	stage = vec2(progress, fade);
}

void fragment() {
	vec2 mask = texture(mask_atlas, tile_region.xy + UV * tile_region.zw).rg;
	if (mask.r + mask.g < 0.01) { discard; }
	float appear = smoothstep(0.0, 0.35, stage.x);
	float body = mask.r * shadow_opacity * mix(0.35, 1.0, appear);
	float rim = mask.g * rim_opacity * mix(0.25, 1.0, smoothstep(0.1, 0.85, stage.x));
	ALBEDO = mix(shadow_color.rgb, rim_color.rgb, mask.g);
	ALPHA = max(body, rim) * stage.y;
}
