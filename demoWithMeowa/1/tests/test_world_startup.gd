extends SceneTree
## 正式 World 的合并回归：实际项目开关、独立地图配置与开战／升级链路。
const SETTINGS := preload("res://scripts/core/game_system_settings.gd")
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func frames(count := 3) -> void:
	for index in count: await physics_frame

func run() -> void:
	# 读取落盘配置，不能让测试启动器的内存开关掩盖 F5 启动回归。
	var saved := ConfigFile.new()
	check(saved.load("res://project.godot") == OK, "The actual project startup configuration is readable")
	check(saved.get_value("application", "run/main_scene") == "res://scenes/world/world.tscn", "F5 still starts the formal World map")
	for id in [SETTINGS.UPGRADES, SETTINGS.DRAFT, SETTINGS.RUN_SKILLS]:
		check(saved.get_value("game_manager", "systems/" + String(id), true) == true, "Normal project startup enables " + String(id))
	var profile := load("res://data/combat/scenes/world/configuration.tres") as SceneCombatConfiguration
	check(not profile.population_rules.simulation_mode, "World starts normal combat instead of bypassing growth in stress simulation")
	check(profile.sword_rules.effect_mode == PlayerSwordRules.SlashVisual.MEOWA_ARC and profile.sword_rules.frames != null, "World retains the authored animated sword trail")
	check(is_equal_approx(profile.default_enemy.separation_radius, 0.65) and is_equal_approx(profile.default_enemy.separation_strength, 0.8) and is_equal_approx(profile.default_enemy.pursuit_flank_strength, 0.15), "World preserves the independently tuned crowd avoidance")
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("MapEffects/BGM").music_enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	world.get_node("MapEffects/CoreFeedbackAudio").enabled = false
	for audio in world.find_children("UIAudio", "", true, false): audio.enabled = false
	root.add_child(world)
	await frames(12)
	var wave := world.get_node("WavePrototype") as WavePrototype
	var growth := wave.get_node("RunGrowth") as RunGrowth
	var player := world.get_node("Player") as Player
	var aurora := world.get_node("MapEffects/Aurora")
	var sky := world.get_node("MapEffects/WorldEnvironment").environment.sky.sky_material as ShaderMaterial
	var ground := (world.get_node("Homestead") as Terrain).top_material
	var terrain := world.get_node("Homestead") as Terrain
	check(terrain.obstacle_certificates_enabled and terrain.obstacle_query_backend == Terrain.ObstacleQueryBackend.NATIVE_QUERIES, "World uses native pure queries while preserving its established body movement")
	check(aurora.enabled and aurora.is_processing(), "World explicitly enables the flowing aurora")
	check(sky.get_shader_parameter("aurora_enabled") == true and ground.get_shader_parameter("aurora_enabled") == true, "World binds the aurora to both sky and wet ground")
	check(sky.get_shader_parameter("aurora_texture") != null and sky.get_shader_parameter("aurora_texture") == ground.get_shader_parameter("aurora_texture"), "Sky and ground use the same live aurora field")
	var clock: float = aurora.clock
	world.get_node("VisualSample").apply_style()
	await frames()
	# process_frame 信号早于 Node._process；等待进程计时器，避免同帧物理追帧误判时钟。
	await create_timer(0.05).timeout
	check(aurora.enabled and ground.get_shader_parameter("aurora_enabled") == true, "Applying Style preserves the independently enabled aurora")
	check(aurora.clock > clock, "The independently enabled aurora clock keeps flowing")
	check(player.action_visuals == profile.action_visuals and player.action_visuals.show_fire_trail and player.action_visuals.bounce_frames != null, "The bound World visuals retain fire and wall-bounce feedback")
	check(player.ricochet_rules == profile.ricochet_rules and wave.default_enemy == profile.default_enemy and wave.enemy_catalog == profile.enemy_catalog, "Runtime retains the independent scene's ricochet and enemy balance")
	check(growth.rules == profile.experience_rules and wave.population_rules == profile.population_rules and wave.health_growth_rules == profile.health_growth_rules, "Experience, population and health scaling retain their independent scene resources")
	check(is_equal_approx(wave.get_node("RicochetStorm").damage, profile.storm_damage), "Storm damage follows the scene profile instead of the shared prototype")
	check(growth.is_enabled() and wave.run_skill_manager.is_enabled(), "The actual runtime enables growth and learnable skills")
	wave.set_physics_process(false)
	player.set_physics_process(false)
	player.global_position = wave.global_position + Vector3.UP * 0.03
	check(wave.start_run() and wave.skill_draft.initial_choice.is_open, "Normal World startup opens the initial skill draft")
	if wave.skill_draft.initial_choice.is_open:
		var draft := wave.skill_draft
		draft.initial_choice.reveal_now()
		draft.initial_choice.select_option(draft._initial_cards[0].id)
		draft.initial_choice.confirm_selection()
		check(wave.phase == WavePrototype.Phase.BATTLE and growth.active and not wave.combat_frozen, "Confirming the initial skill starts normal combat and experience collection")
		growth._grant_experience(growth.rules.required_for(1) - 1)
		check(growth.state.level == 1, "Experience below the first threshold cannot upgrade early")
		growth._grant_experience(1)
		check(growth.state.level == 2 and growth.state.pending_choices == 1 and growth.choice_ui.is_open and wave.combat_frozen, "The configured first upgrade opens its choice and freezes combat")
		check(growth.choice_options.size() == 3 and growth.choice_options.any(func(option): return option.category in [GrowthChoiceOption.Category.LEARN_SKILL, GrowthChoiceOption.Category.UPGRADE_SKILL]) and growth.choice_options.any(func(option): return option.ricochet_growth), "The first upgrade retains both skill and ricochet growth candidates")
	wave.retreat()
	world.free()
	await frames()
	var city: Node3D = load("res://scenes/city/city.tscn").instantiate()
	city.get_node("LoadoutUI").save_enabled = false
	city.get_node("MapEffects/BGM").music_enabled = false
	city.get_node("MapEffects/Weather").rain_audio_enabled = false
	city.get_node("MapEffects/Weather").wind_audio_enabled = false
	city.get_node("MapEffects/CoreFeedbackAudio").enabled = false
	for audio in city.find_children("UIAudio", "", true, false): audio.enabled = false
	root.add_child(city)
	await frames(12)
	var city_profile := city.get_node("BattleConfiguration").configuration as SceneCombatConfiguration
	check((city.get_node("WavePrototype") as WavePrototype).terrain.obstacle_query_backend == Terrain.ObstacleQueryBackend.SCRIPT_CERTIFICATES, "City retains its independent query backend")
	check(city_profile != profile and city_profile.default_enemy != profile.default_enemy and city_profile.default_enemy.health == 200.0, "City keeps its independent combat profile and authored enemy balance")
	check(not city.get_node("MapEffects/Aurora").enabled and not city_profile.action_visuals.show_fire_trail and city_profile.sword_rules.effect_mode == PlayerSwordRules.SlashVisual.FRAME_ANIMATION, "World visual restoration leaves City's authored opt-ins unchanged")
	city.free()
	await frames()
	print(JSON.stringify({"suite":"world_startup", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
