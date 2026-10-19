extends SceneTree
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func run() -> void:
	var world_profile := load("res://data/combat/scenes/world/configuration.tres") as SceneCombatConfiguration
	check(world_profile.has_method("validation_errors"), "Scene profiles expose a non-mutating configuration validator")
	if not world_profile.has_method("validation_errors"): quit(1); return
	check(world_profile.call("validation_errors").is_empty(), "The authored World profile is valid")
	check(load("res://data/combat/scenes/city/configuration.tres").call("validation_errors").is_empty(), "The authored City profile is valid")
	var profile := world_profile.duplicate() as SceneCombatConfiguration
	profile.max_active_enemies = 0
	check("max_active_enemies" in String(profile.call("validation_error")), "Invalid capacity reports the exact parameter")
	profile.max_active_enemies = world_profile.max_active_enemies
	profile.crowd_clearance_distance = NAN
	check("crowd_clearance_distance" in String(profile.call("validation_error")), "Non-finite scalar input is rejected")
	profile.crowd_clearance_distance = world_profile.crowd_clearance_distance
	profile.skill_definitions = world_profile.skill_definitions.duplicate()
	profile.skill_definitions.append(profile.skill_definitions[0])
	check("skill_definitions" in String(profile.call("validation_error")), "Duplicate skill ids cannot silently select the first definition")
	profile.skill_definitions = [CombatSkillDefinition.new()]
	check(profile.call("validation_errors").size() >= 2, "An empty skill id and missing levels both produce diagnostics")
	var innate := world_profile.skill_definitions[0].duplicate() as CombatSkillDefinition
	innate.id = &"dash"
	profile.skill_definitions = [innate]
	check("skill_definitions" in String(profile.call("validation_error")), "Scene learning pools reject character-owned ability ids before binding")
	profile.skill_definitions = []
	profile.growth_definitions = []
	profile.experience_rules = null
	profile.cards_per_draw = 100
	check(profile.call("validation_errors").is_empty(), "Optional pools and experience rules can be omitted; large test draws remain supported")
	profile.sword_rules = profile.sword_rules.duplicate()
	profile.sword_rules.damage = -1.0
	check("sword_rules" in String(profile.call("validation_error")), "Nested rules include their owning property in the diagnostic")
	check(world_profile.call("validation_errors").is_empty(), "Validation never rewrites the shared World template")
	# 无效配置不能先打开开局选卡，或悄悄用场景默认值启动。
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("BattleConfiguration").configuration = profile
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("MapEffects/BGM").music_enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	world.get_node("MapEffects/CoreFeedbackAudio").enabled = false
	root.add_child(world)
	for index in 12: await physics_frame
	var wave := world.get_node("WavePrototype") as WavePrototype
	wave.player.global_position = wave.global_position + Vector3.UP * 0.1
	check(not wave.start_run() and wave.outcome == WavePrototype.Outcome.ERROR and "sword_rules" in wave.result_reason, "Invalid scene configuration stops before opening the initial draft")
	check(not wave.skill_draft.initial_choice.is_open and wave.enemies.is_empty(), "Rejected configuration creates no partial battle")
	world.free()
	for index in 3: await physics_frame
	print(JSON.stringify({"suite":"combat_configuration_validation", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
