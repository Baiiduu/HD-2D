extends SceneTree
## 场景集成契约：运行状态不能写回模板；编辑器保存的相机参数必须生效。
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(35.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func frames(count := 12) -> void:
	for index in count: await physics_frame

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var profile := load("res://data/combat/scenes/world/configuration.tres") as SceneCombatConfiguration
	var original_enabled := profile.ricochet_rules.enabled
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("MapEffects/BGM").music_enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	root.add_child(world)
	await frames()
	var player := world.get_node("Player") as Player
	var manager := player.skill_manager
	var run_manager := world.get_node("WavePrototype/RunSkillManager") as RunSkillManager
	check(manager == player.get_node("CharacterSkillManager") and manager != run_manager, "The player owns a separate character skill manager")
	check(player.body_ricochet.get_parent() == manager and player._blink.get_parent() == manager, "Ricochet and dash components belong to the character manager")
	check(manager.get_registered_ids().size() == 2 and manager.get_skill(&"basic_sword") == null, "Only ricochet and dash are character skills")
	check(not run_manager.is_skill_available(&"body_ricochet") and not run_manager.is_skill_available(&"dash") and run_manager.get_registered_ids().size() == 5, "The run manager contains only the five learnable components")
	check(manager.set_skill_enabled(CharacterSkillManager.BODY_RICOCHET, false), "Character ricochet has an independent runtime switch")
	check(profile.ricochet_rules.enabled == original_enabled, "Runtime switching leaves the loaded character template unchanged")
	check(not player.body_ricochet.begin_charge(Vector3.RIGHT), "Direct ability commands obey the character manager")
	run_manager.reset()
	check(not manager.is_skill_enabled(CharacterSkillManager.BODY_RICOCHET), "Resetting learnable skills cannot reset character skill switches")
	check(not player.sword.get_combat_stats().is_empty(), "Basic sword stats remain active independently of both skill registries")
	manager.set_skill_enabled(CharacterSkillManager.BODY_RICOCHET, true)
	var wave := world.get_node("WavePrototype") as WavePrototype
	player._blink._cooldown = 0.5
	wave.set_combat_frozen(true)
	player._blink.advance(0.1)
	check(manager.combat_frozen and is_equal_approx(player._blink._cooldown, 0.5), "Combat freeze also stops manually advanced dash timing")
	player._blink.discard_buffered_input()
	player._blink.request(Vector3.RIGHT)
	check(is_zero_approx(player._blink._buffer_remaining), "Direct dash input during freeze cannot leave a buffered request for resume")
	wave.set_combat_frozen(false)
	player._blink.advance(0.1)
	check(not manager.combat_frozen and is_equal_approx(player._blink._cooldown, 0.4), "Dash timing resumes without accumulating frozen time")
	manager.unregister_skill(CharacterSkillManager.BODY_RICOCHET)
	check(not player.body_ricochet.begin_charge(Vector3.RIGHT), "Unregistered ricochet rejects direct component input")
	manager.unregister_skill(CharacterSkillManager.DASH)
	player._blink.request(Vector3.RIGHT)
	check(not player._blink.active, "Unregistered dash rejects direct component input")
	world.free()
	await frames(3)
	var city: Node3D = load("res://scenes/city/city.tscn").instantiate()
	city.get_node("LoadoutUI").save_enabled = false
	city.get_node("MapEffects/BGM").music_enabled = false
	city.get_node("MapEffects/Weather").rain_audio_enabled = false
	city.get_node("MapEffects/Weather").wind_audio_enabled = false
	var camera := city.get_node("MapEffects/Camera3D") as FollowCamera
	camera.distance = 37.0
	camera.fov = 34.0
	camera.focus_height = 1.2
	root.add_child(city)
	await frames()
	check(is_equal_approx(camera.distance, 37.0) and is_equal_approx(camera.fov, 34.0) and is_equal_approx(camera.focus_height, 1.2), "City preserves authored camera distance, FOV and focus")
	var city_player := city.get_node("Player") as Player
	check(city_player.skill_manager.get_registered_ids().size() == 2 and city.get_node("WavePrototype/RunSkillManager").get_registered_ids().size() == 5, "City uses the same separated ownership with its independent profile")
	city.free()
	await frames(3)
	await create_timer(0.1).timeout
	print(JSON.stringify({"suite":"scene_configuration_contract", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
