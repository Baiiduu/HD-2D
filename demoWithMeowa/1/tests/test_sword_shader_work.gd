extends SceneTree
## CPU expression oracles and work counts; no GPU filtering or visual acceptance.
const MATH := preload("res://tests/fixtures/effect_shader_math.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		if failures <= 8: printerr("FAIL: ", label)

func before(name: String) -> String:
	return FileAccess.get_file_as_string("res://tests/fixtures/pre_work_sword_" + name + ".gdshader.txt")

func current(name: String) -> String:
	return FileAccess.get_file_as_string("res://shaders/combat/player_sword_" + name + ".gdshader")

func original_sparks(source: String) -> String:
	var start := source.find("\tfloat grain = texture(flow_noise,")
	var end := source.find("\tvec4 color =", start)
	return source.substr(start, end - start)

func sparks_model(source: String, original: String) -> RefCounted:
	if not source.contains("float spark_flecks("):
		source += "\nfloat spark_flecks(vec2 point, float trailing) {\n" + original + "return flecks;\n}\n"
	# Only test deterministic texture values. Gradient placement is checked separately.
	source = source.replace("dFdx(grain_uv)", "vec2(0.01, 0.0)").replace("dFdy(grain_uv)", "vec2(0.0, 0.01)")
	source = source.replace("textureGrad(flow_noise, grain_uv, grain_dx, grain_dy)", "texture(flow_noise, grain_uv)")
	return MATH.build(source, ["spark_flecks"])

func orbit_checks() -> void:
	var original := before("orbit")
	var source := current("orbit")
	var snippet := original_sparks(original)
	var old = sparks_model(original, snippet)
	var fresh = sparks_model(source, snippet)
	check(old != null and fresh != null, "Actual orbit spark expressions compile as CPU data")
	if old == null or fresh == null: return
	for phase in [0.0, 0.01, 0.18, 0.6]:
		for strength in [0.0, 0.4, 1.0, -0.2]:
			for trailing in [0.0, 0.000000000001, 0.2, 0.9, -0.3]:
				for effect in [old, fresh]:
					effect.visual_age = phase
					effect.spark_strength = strength
				for x in 13:
					for y in 9:
						var point := Vector2(-4.0 + x * 0.63, -3.0 + y * 0.71)
						check(old.spark_flecks(point, trailing) == fresh.spark_flecks(point, trailing), "Orbit sparks preserve exact original values, including tiny and negative contributions")
	old.texture_calls = 0
	fresh.texture_calls = 0
	fresh.spark_strength = 0.4
	old.spark_flecks(Vector2(0.3, 0.5), 0.0)
	fresh.spark_flecks(Vector2(0.3, 0.5), 0.0)
	check(old.texture_calls == 1 and fresh.texture_calls == 0, "A zero tail contributes no sparkle noise sample")
	var zero_tail_samples: int = fresh.texture_calls
	fresh.texture_calls = 0
	fresh.spark_strength = 0.0
	fresh.spark_flecks(Vector2(0.3, 0.5), 1.0)
	check(fresh.texture_calls == 0, "Disabled sparkles do not sample noise")
	fresh.texture_calls = 0
	fresh.spark_strength = 0.4
	fresh.spark_flecks(Vector2(0.3, 0.5), 0.000000000001)
	check(fresh.texture_calls == 1, "A nonzero tiny tail still retains the full noise sample")
	var branch := source.find("if (trailing != 0.0")
	check(source.contains("textureGrad(flow_noise, grain_uv, grain_dx, grain_dy)") and branch > source.find("dFdx(grain_uv)") and source.find("dFdx(grain_uv)") >= 0 and branch > source.find("dFdy(grain_uv)"), "Explicit noise gradients are evaluated outside the varying branch")
	var replacement := "\tfloat flecks = spark_flecks(point, trailing);\n"
	check(source.get_slice("void fragment()", 1).replace(replacement, snippet) == original.get_slice("void fragment()", 1), "The final orbit colors, alpha, layers and emission expressions are unchanged")
	print(JSON.stringify({"orbit_zero_tail_spark_samples":{"before":old.texture_calls,"after":zero_tail_samples}}))

func motes_model(source: String) -> RefCounted:
	# GLSL hash() must not resolve to GDScript's unrelated global hash().
	source = source.replace("hash(", "mote_hash(").replace("max(size, vec2(0.001))", "size.max(vec2(0.001))")
	return MATH.build(source, ["mote_hash", "motes"])

func flow_checks() -> void:
	var source := current("flow_slash")
	var old = motes_model(before("flow"))
	var fresh = motes_model(source)
	check(old != null and fresh != null, "Actual analytic mote expressions compile as CPU data")
	if old == null or fresh == null: return
	var visible := 0
	for radius in [1.52, 2.888, 4.028]:
		for sweep in [0.1, 0.012, 0.005]:
			var ages: Array[float] = [-0.01, 0.0, 0.05, 0.12, 0.18, 0.3, 1.0]
			for index in 6:
				var born: float = sweep * (0.15 + index * 0.12)
				var expires: float = born + 0.10 + old.mote_hash(float(index + 4)) * 0.08
				for instant in [born, expires]:
					ages.append_array([instant - 0.000000001, instant, instant + 0.000000001])
			for age in ages:
				for effect in [old, fresh]:
					effect.attack_radius = radius
					effect.sweep_seconds = sweep
					effect.visual_age = age
				for strength in [0.0, 0.65, 1.0]:
					for effect in [old, fresh]: effect.spark_strength = strength
					for index in 6:
						var phase := 0.15 + index * 0.12
						var elapsed: float = age - sweep * phase
						var angle: float = -old.attack_angle * 0.5 + old.attack_angle * phase
						var direction := Vector2(sin(angle), -cos(angle))
						var tangent := Vector2(-direction.y, direction.x)
						var point: Vector2 = direction * radius * (0.55 + old.mote_hash(float(index)) * 0.28)
						point += (tangent * (1.2 + old.mote_hash(float(index + 1))) + direction * 0.4) * maxf(elapsed, 0.0)
						for offset in [Vector2.ZERO, Vector2(0.001, -0.002), Vector2(0.1, 0.2)]:
							var expected: float = old.motes(point + offset)
							visible += 1 if expected > 0.0 else 0
							check(expected == fresh.motes(point + offset), "Mote shapes, movement, color weight and exact birth/expiry remain identical")
	check(visible > 0, "The oracle exercises visible particles, not only empty pixels")
	check(source.get_slice("void fragment()", 1) == before("flow").get_slice("void fragment()", 1), "Normal-slash colors, alpha and emission expressions are unchanged")
	for effect in [old, fresh]:
		effect.visual_age = 1.0
		effect.spark_strength = 0.65
		effect.length_calls = 0
		effect.motes(Vector2.ZERO)
	check(old.length_calls == 6 and fresh.length_calls == 0, "Expired motes skip all six shape evaluations")
	fresh.spark_strength = 0.0
	fresh.visual_age = 0.1
	fresh.length_calls = 0
	fresh.motes(Vector2.ZERO)
	check(fresh.length_calls == 0, "Disabled motes skip all shape evaluations")
	print(JSON.stringify({"expired_mote_shape_evaluations":{"before":old.length_calls,"after":fresh.length_calls}}))

func bindings_checks() -> void:
	for names in [["orbit", "orbit"], ["flow", "flow_slash"]]:
		var old := before(names[0])
		var source := current(names[1])
		check(source.get_slice("void vertex()", 0) == old.get_slice("void vertex()", 0), "Original uniforms, render modes and samplers remain unchanged")
		check(not source.contains("discard;"), "No new fragment discard changes the depth path")
		var material := CombatEffectLayer.material(load("res://shaders/combat/player_sword_" + names[1] + ".gdshader"))
		var baseline := Shader.new()
		baseline.code = old
		check(material.shader.get_shader_uniform_list() == baseline.get_shader_uniform_list(), "Headless shader parser accepts the original material bindings")
		check(material.next_pass is ShaderMaterial and (material.next_pass as ShaderMaterial).shader.get_shader_uniform_list() == baseline.get_shader_uniform_list(), "The monster overlay retains the same shader parameters")

func run() -> void:
	orbit_checks()
	flow_checks()
	bindings_checks()
	print("Sword shader work: %d checks, %d failures (CPU expressions; GPU/visuals require manual acceptance)" % [checks, failures])
	quit(1 if failures else 0)
