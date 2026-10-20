extends SceneTree
## Real shader functions vs frozen pre-optimization sources; no rendering or timing.
const MATH = preload("res://tests/fixtures/effect_shader_math.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures <= 8: printerr("FAIL: ", label)

func models(name: String, functions: Array[String]) -> Array:
	var old := FileAccess.get_file_as_string("res://tests/fixtures/legacy_" + name + ".txt")
	var current := FileAccess.get_file_as_string("res://shaders/combat/" + name)
	return [MATH.build(old, functions), MATH.build(current, functions)]

func shader_contract_checks() -> void:
	for name in ["player_sword_orbit.gdshader", "player_air_envelope.gdshader"]:
		var before := FileAccess.get_file_as_string("res://tests/fixtures/legacy_" + name + ".txt")
		var after := FileAccess.get_file_as_string("res://shaders/combat/" + name)
		var prefix := after.get_slice("void fragment()", 0) if name.contains("air_envelope") else after.get_slice("vec2 stroke(", 0)
		check(before.begins_with(prefix), "Uniforms, sampling filters, render modes and vertex motion stay unchanged: " + name)
		var material := CombatEffectLayer.material(load("res://shaders/combat/" + name))
		check(material.next_pass is ShaderMaterial, "Existing monster overlay remains attached: " + name)
		var baseline := Shader.new()
		baseline.code = before
		check(material.shader.get_shader_uniform_list() == baseline.get_shader_uniform_list(), "Headless shader parser preserves uniform bindings: " + name)
	var air := FileAccess.get_file_as_string("res://shaders/combat/player_air_envelope.gdshader")
	check(air.find("texture(flow_noise,") < air.find("body_coverage(VERTEX,") and air.find("texture(flow_brush,") < air.find("body_coverage(VERTEX,"), "Mipmapped noise and brush sampling precede per-pixel mask exits")

func sword_checks() -> void:
	var pair := models("player_sword_orbit.gdshader", ["brush", "stroke"])
	var old = pair[0]
	var current = pair[1]
	if old == null or current == null:
		check(false, "Sword shader CPU translation compiles")
		return
	for span in [0.0, 0.0005, 0.00099999, 0.001, 0.00100001, 0.5, 2.617994, 6.283185]:
		for age in [0.0, 0.05, 0.15, 0.3]:
			for release in [0.0, 0.5, 0.96, 1.0]:
				for effect in pair:
					effect.visual_age = age
					effect.release = release
				for index in 24:
					var angle := -PI + TAU * index / 24.0
					var point := Vector2(sin(angle), -cos(angle)) * (0.5 + index * 0.045)
					for layer in [Vector2(0.0, 1.0), Vector2(0.65, 0.55)]:
						check(old.stroke(point, 0.7, span, layer.x, layer.y) == current.stroke(point, 0.7, span, layer.x, layer.y), "Sword original brush/noise, threshold, layers and fade are identical")
	current.texture_calls = 0
	current.stroke(Vector2(1, 0), 0.7, 0.0, 0.65, 0.55)
	check(current.texture_calls == 0, "An unborn sword layer does not sample brush or noise")
	current.texture_calls = 0
	current.stroke(Vector2(1, 0), 0.7, 0.001, 0.65, 0.55)
	check(current.texture_calls > 0, "The exact first visible span keeps its original sampling")

func fire_checks() -> void:
	var pair := models("ground_fire_surface.gdshaderinc", ["fire_hash", "fire_noise", "ground_fire_surface"])
	var old = pair[0]
	var current = pair[1]
	if old == null or current == null:
		check(false, "Ground fire CPU translation compiles")
		return
	for width in [0.1, 0.36, 0.8]:
		for segment_length in [0.0, 0.01, 0.7, 4.0]:
			for durations in [Vector3(0.18, 0.65, 1.35), Vector3(0.05, 0.1, 0.1), Vector3(0.6, 1.5, 3.0)]:
				for age in [-0.00001, 0.0, durations.x, durations.x + durations.y, durations.x + durations.y + durations.z - 0.00001, durations.x + durations.y + durations.z]:
					for radius in [0.0, 0.5, 0.99999, 1.0, 1.00001, 1.5]:
						for density in [20.0, 40.0, 80.0]:
							var ground := Vector2(age * 1.7 - 3.0, density * 0.13)
							var ribbon := Vector2(segment_length * 0.5 + width * radius * 0.3, width * radius * 0.4)
							var a = old.ground_fire_surface(ground, ribbon, segment_length, width, age, 3.7, durations, 1.1, density)
							var b = current.ground_fire_surface(ground, ribbon, segment_length, width, age, 3.7, durations, 1.1, density)
							check(a.coverage == b.coverage and a.albedo == b.albedo and a.emission == b.emission, "Fire caps, burn/ember transitions, world pixel density and expiry remain identical")
	for sample in [Vector3(0.0, 0.181, 0.1), Vector3(0.0, 0.0, 1.0)]:
		for effect in pair:
			effect.noise_calls = 0
			effect.ground_fire_surface(Vector2.ZERO, Vector2(sample.x, sample.y), 0.0, 0.36, sample.z, 3.7, Vector3(0.18, 0.65, 1.35), 1.1, 40.0)
		check(current.noise_calls == 0 and old.noise_calls > 0, "Definitely empty caps and burnt-out native pixels return before procedural noise")

func air_checks() -> void:
	var pair := models("player_air_envelope.gdshader", ["fragment"])
	var old = pair[0]
	var current = pair[1]
	if old == null or current == null:
		check(false, "Air envelope CPU translation compiles")
		return
	for phase in [0.0, 0.25, 1.0, 7.25]:
		for amount in [0.0, 0.3, 1.0]:
			for covered in [0.0, 1.0]:
				for masking in [false, true]:
					for ink_mode in [0, 1]:
						for x in 17:
							for y in 9:
								for effect in pair:
									effect.UV = Vector2(x / 16.0, y / 8.0)
									effect.UV2 = Vector2(-1.0 if x % 2 == 0 else 1.0, 0.0)
									effect.flow_phase = phase
									effect.flow_amount = amount
									effect.body_cover = covered
									effect.body_mask_enabled = masking
									effect.ink_mode = ink_mode
									effect.opacity = [0.0, 0.000001, 0.55, 1.0][x % 4]
								var a = old.fragment()
								var b = current.fragment()
								check(a == b and (a == 0.0 or (old.ALBEDO == current.ALBEDO and old.EMISSION == current.EMISSION)), "Air keeps original color and all alpha, speed, phase, body clearance and fade factors")
	current.flow_amount = 1.0
	current.opacity = 0.55
	current.body_mask_enabled = true
	current.ink_mode = 0
	current.mask_calls = 0
	current.UV = Vector2(0.3, 0.5)
	current.fragment()
	check(current.mask_calls == 0, "Transparent brush pixels skip the nine-tap body mask")
	current.ink_mode = 1
	current.body_cover = 0.0
	current.flow_phase = 0.0
	current.UV2 = Vector2.ZERO
	current.mask_calls = 0
	current.UV = Vector2(0.3, 0.5)
	current.fragment()
	check(current.mask_calls == 1, "A supported air pixel still checks the real body mask")

func run() -> void:
	shader_contract_checks()
	sword_checks()
	fire_checks()
	air_checks()
	print("Effect shader guards: %d checks, %d failures (CPU math, no GPU/render validation)" % [checks, failures])
	quit(1 if failures else 0)
