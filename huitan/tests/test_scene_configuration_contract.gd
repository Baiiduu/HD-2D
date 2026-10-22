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
	world.get_node("WorldMainMenu").show_on_world_start = false
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("MapEffects/BGM").music_enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	root.add_child(world)
	await frames()
	var player := world.get_node("Player") as Player
	var storm := world.get_node("WavePrototype/RicochetStorm") as RicochetStorm
	check(is_equal_approx(profile.storm_damage, 20.0) and is_equal_approx(storm.get_attack_stats(1).damage, 20.0), "World binds twenty base storm damage into the actual first-level attack")
	check(is_equal_approx(storm.get_attack_stats(4).damage, 32.0), "World retains storm skill-level scaling on top of the new twenty-damage base")
	var ricochet_growth := RunCombatModifiers.new()
	var speed_growth: GrowthBuffDefinition = load("res://data/combat/scenes/world/growth/ricochet/launch_speed.tres")
	var momentum_growth: GrowthBuffDefinition = load("res://data/combat/scenes/world/growth/ricochet/flight_duration.tres")
	for rank in 6:
		var stats := player.body_ricochet.get_stats(ricochet_growth)
		var seconds: float = (stats.maximum_launch_speed - profile.ricochet_rules.minimum_bounce_speed) / stats.flight_deceleration
		check(is_equal_approx(seconds, [5.0, 7.8125, 11.25, 15.3125, 20.0, 28.203125][rank]), "Actual launch stats reach the twenty-second build at rank four in each direction and continue growing: %d" % rank)
		ricochet_growth.apply_buff(speed_growth)
		ricochet_growth.apply_buff(momentum_growth)
	var loadout := world.get_node("LoadoutUI") as LoadoutUI
	check(not profile.equipment_bonuses_enabled and not loadout.state.equipment_bonuses_enabled, "World binds disabled equipment bonuses before loading character state")
	check(loadout.state.get_attribute_totals().is_empty() and player.max_health == loadout.training_rules.base_health, "World spawns with actual base health despite retained starter equipment")
	var authored_visuals := load("res://data/player/action_visuals.tres") as PlayerActionVisuals
	check(player.action_visuals == profile.action_visuals and player.action_visuals.show_fire_trail, "World's bound scene profile preserves the authored ground fire trail")
	check(player.action_visuals.bounce_frames == authored_visuals.bounce_frames and player.action_visuals.bounce_anchor_pixels == authored_visuals.bounce_anchor_pixels, "World's independent visuals retain the authored bounce animation and contact anchor")
	check(player.fire_trail != null and player.body_ricochet.flight_segment_travelled.is_connected(player.fire_trail._travelled), "The character-owned ricochet still feeds actual travel segments to the player's fire trail")
	var manager := player.skill_manager
	var run_manager := world.get_node("WavePrototype/RunSkillManager") as RunSkillManager
	check(manager == player.get_node("CharacterSkillManager") and manager != run_manager, "The player owns a separate character skill manager")
	check(player.body_ricochet.get_parent() == manager and player._blink.get_parent() == manager, "Ricochet and dash components belong to the character manager")
	check(manager.get_registered_ids().size() == 2 and manager.get_skill(&"basic_sword") == null, "Only ricochet and dash are character skills")
	check(not run_manager.is_skill_available(&"body_ricochet") and not run_manager.is_skill_available(&"dash") and run_manager.get_registered_ids().size() == 5, "The run manager contains only the five learnable components")
	var mirror := run_manager.get_skill(&"mirror_mark") as MirrorMarkAutoAttack
	check(mirror != null and not run_manager.is_skill_available(&"mirror_mark") and not run_manager.is_skill_enabled(&"mirror_mark"), "World temporarily disables mirror learning and execution while retaining the component")
	check(not run_manager.set_skill_level(&"mirror_mark", 1) and mirror.skill_level == 0 and not mirror.is_physics_processing(), "Disabled mirror rejects direct learning and remains idle")
	check(not run_manager.candidates().any(func(option): return String(option.id).begins_with("skill:mirror_mark:")), "World upgrades cannot offer mirror cards")
	var draft := world.get_node("WavePrototype/SkillDraft") as RunSkillDraft
	check(draft.present_initial_choice(), "Remaining World skills still open the starting draw")
	check(draft._initial_pool.size() == 3 and draft._initial_cards.any(func(option): return option.id == &"initial_buff:L01") and not draft._initial_offered.has(&"initial:mirror_mark"), "Starting draw contains two remaining skills and the legendary growth")
	var growth := world.get_node("WavePrototype/RunGrowth") as RunGrowth
	var rerolls := growth.rerolls_left
	draft.initial_choice.request_reroll()
	check(not draft._initial_cards.any(func(option): return option.id == &"initial:mirror_mark") and growth.rerolls_left == rerolls, "A starting draw with no replacement cannot restore mirror or spend a reroll")
	run_manager.reset()
	check(not run_manager.is_skill_available(&"mirror_mark") and not mirror.enabled, "New-run reset preserves the configured mirror exclusion")
	check(profile.population_rules.simulation_skills.all(func(entry): return entry.skill_definition.id != &"mirror_mark" or entry.skill_level == 0), "World's default simulation loadout also leaves mirror unequipped")
	check(manager.set_skill_enabled(CharacterSkillManager.BODY_RICOCHET, false), "Character ricochet has an independent runtime switch")
	check(profile.ricochet_rules.enabled == original_enabled, "Runtime switching leaves the loaded character template unchanged")
	check(not player.body_ricochet.begin_charge(Vector3.RIGHT), "Direct ability commands obey the character manager")
	run_manager.reset()
	check(not manager.is_skill_enabled(CharacterSkillManager.BODY_RICOCHET), "Resetting learnable skills cannot reset character skill switches")
	check(not player.sword.get_combat_stats().is_empty(), "Basic sword stats remain active independently of both skill registries")
	manager.set_skill_enabled(CharacterSkillManager.BODY_RICOCHET, true)
	var wave := world.get_node("WavePrototype") as WavePrototype
	check(profile.pursuit_throttle_threshold == 80 and wave.pursuit_throttle_threshold == 80 and wave._spatial_index.pursuit_throttle_threshold == 80, "World binds the editable pursuit threshold through the controller into its live index")
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
	check(city.get_node("WavePrototype").pursuit_throttle_threshold == 0 and SceneCombatConfiguration.new().pursuit_throttle_threshold == 0, "City and generic scene profiles retain their independent full-rate defaults")
	check(city_player.skill_manager.get_registered_ids().size() == 2 and city.get_node("WavePrototype/RunSkillManager").get_registered_ids().size() == 5, "City uses the same separated ownership with its independent profile")
	city.free()
	await frames(3)
	await create_timer(0.1).timeout
	print(JSON.stringify({"suite":"scene_configuration_contract", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
