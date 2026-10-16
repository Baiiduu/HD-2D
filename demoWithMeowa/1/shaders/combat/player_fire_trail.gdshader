shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

// Opaque pixel cutouts retain real depth, without transparent rectangles or overlays.
// A single shared clock is advanced by the owner, never TIME: upgrades freeze all phases.
uniform float effect_clock = 0.0;
uniform float fresh_seconds = 0.18;
uniform float burn_seconds = 0.65;
uniform float ember_seconds = 1.35;
uniform float energy = 1.1;
uniform float pixels_per_meter = 40.0;
varying vec3 world_point;
varying flat vec4 piece; // birth, traversal seconds, centerline length, width

float fire_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float fire_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(fire_hash(cell), fire_hash(cell + vec2(1.0, 0.0)), f.x),
		mix(fire_hash(cell + vec2(0.0, 1.0)), fire_hash(cell + vec2(1.0)), f.x), f.y);
}

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	piece = INSTANCE_CUSTOM;
}

void fragment() {
	float along = (UV.x - 0.5) * (piece.z + piece.w);
	float fraction = clamp(along / max(piece.z, 0.00001) + 0.5, 0.0, 1.0);
	float age = max(0.0, effect_clock - piece.x - fraction * piece.y);
	float lifetime = fresh_seconds + burn_seconds + ember_seconds;
	if (age >= lifetime) discard;
	float burn = smoothstep(fresh_seconds * 0.65, fresh_seconds + burn_seconds * 0.25, age);
	float ember = smoothstep(fresh_seconds + burn_seconds * 0.7, fresh_seconds + burn_seconds + 0.18, age);
	float fading = smoothstep(fresh_seconds + burn_seconds, lifetime, age);
	vec2 pixel = floor(world_point.xz * pixels_per_meter);
	vec2 p = (pixel + 0.5) / pixels_per_meter;
	float clock = floor(effect_clock * 14.0) / 14.0;
	float clumps = fire_noise(p * 10.5 + vec2(0.0, -clock * 2.0));
	float threads = fire_noise(p * 27.0 + vec2(clock * 2.5, -clock * 3.5));
	float grain = fire_hash(pixel);
	float across = (UV.y - 0.5) * piece.w;
	float cap = along - clamp(along, -piece.z * 0.5, piece.z * 0.5);
	float radius = length(vec2(cap, across)) / max(piece.w * 0.5, 0.00001);
	float edge = 1.0 - radius;
	float heat = edge * 0.7 + clumps * 0.42 + threads * 0.2;
	float threshold = mix(0.57, 0.73, burn);
	threshold = mix(threshold, 0.9, ember);
	// Late coals keep a fixed pattern in world space, with a slow pulse instead of swimming.
	float coal = fire_noise(p * 20.0) * 0.65 + grain * 0.35;
	float coal_heat = edge * 0.55 + coal * 0.6;
	heat = mix(heat, coal_heat, ember);
	float ragged_edge = mix(0.5, 1.0, clumps);
	if (radius > mix(ragged_edge, 0.9, ember) || heat < threshold || grain < burn * 0.08 + fading * 0.8) discard;
	float core = smoothstep(threshold + 0.06, 1.15, heat);
	vec3 orange = vec3(1.0, 0.16, 0.012);
	vec3 yellow = vec3(1.0, 0.74, 0.16);
	vec3 fresh = mix(orange, yellow, core * (1.0 - burn * 0.6));
	vec3 coals = mix(vec3(0.3, 0.008, 0.002), vec3(0.95, 0.09, 0.012), smoothstep(0.82, 1.12, coal_heat));
	vec3 tint = mix(fresh, coals, ember);
	float pulse = mix(1.0, 0.8 + 0.2 * sin(effect_clock * 4.0 + grain * 12.0), ember);
	ALBEDO = tint * mix(0.8, 0.35, ember);
	EMISSION = tint * energy * mix(1.65, 0.55, ember) * (1.0 - fading * 0.85) * pulse;
	ROUGHNESS = 1.0;
}
