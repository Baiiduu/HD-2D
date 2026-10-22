extends SceneTree
## Run with Forward+ to cover the real city terrain, combat bindings, HUD and night compositor.
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func frames(count: int) -> void:
	for index in count: await physics_frame

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var world_profile := load("res://data/combat/scenes/world/configuration.tres") as SceneCombatConfiguration
	var city_profile := load("res://data/combat/scenes/city/configuration.tres") as SceneCombatConfiguration
	check(world_profile != city_profile and world_profile.ricochet_rules != city_profile.ricochet_rules, "Player balance is isolated per scene")
	check(world_profile.enemy_catalog != city_profile.enemy_catalog and world_profile.population_rules != city_profile.population_rules, "Enemy and population configuration is isolated")
	check(world_profile.enemy_catalog.enemies[0] != city_profile.enemy_catalog.enemies[0], "Nested enemy definitions are isolated")
	check(world_profile.waves[0] != city_profile.waves[0] and world_profile.skill_definitions[0] != city_profile.skill_definitions[0], "Wave and skill resources are isolated")
	check(world_profile.growth_definitions[0] != city_profile.growth_definitions[0] and world_profile.number_styles[0] != city_profile.number_styles[0], "Growth and feedback styles are isolated")
	var world_speed := world_profile.ricochet_rules.maximum_launch_speed
	var city_speed := city_profile.ricochet_rules.maximum_launch_speed
	city_profile.ricochet_rules.maximum_launch_speed += 1.0
	check(world_profile.ricochet_rules.maximum_launch_speed == world_speed, "Changing city balance does not alter world balance")
	city_profile.ricochet_rules.maximum_launch_speed = city_speed
	var hashes := {}
	for path in ["res://data/world/world_terrain.tres", "res://data/world/world_surface.res", world_profile.resource_path]: hashes[path] = FileAccess.get_sha256(path)
	var city: Node3D = load("res://scenes/city/city.tscn").instantiate()
	city.get_node("LoadoutUI").save_enabled = false
	root.add_child(city)
	current_scene = city
	await frames(45)
	var terrain := city.get_node("Ground") as Terrain
	var player := city.get_node("Player") as Player
	var wave := city.get_node("WavePrototype") as WavePrototype
	var growth := wave.get_node("RunGrowth") as RunGrowth
	var skills := wave.get_node("RunSkillManager") as RunSkillManager
	var ui := city.get_node("LoadoutUI") as LoadoutUI
	var character_skills := player.skill_manager
	check(wave.run_skill_manager == skills and character_skills != skills, "City keeps character skills separate from run skills")
	check(character_skills.get_registered_ids().size() == 2 and skills.get_registered_ids().size() == 5, "Two innate abilities and five learnable components use separate registries")
	check(character_skills.get_skill(CharacterSkillManager.BODY_RICOCHET) == player.body_ricochet and character_skills.get_skill(CharacterSkillManager.DASH) == player._blink, "Character registry owns the actual ricochet and dash components")
	check(not skills.has_learned_skill() and skills.get_slots().is_empty(), "Innate abilities do not mark a run learned or occupy learned slots")
	check(character_skills.set_skill_enabled(CharacterSkillManager.BODY_RICOCHET, false) and not character_skills.begin_charge(Vector3.FORWARD), "Character manager disables charging")
	character_skills.set_skill_enabled(CharacterSkillManager.BODY_RICOCHET, true)
	check(character_skills.set_skill_enabled(CharacterSkillManager.DASH, false) and player.blink_enabled, "Character manager controls dash without rewriting its configured default")
	character_skills.set_skill_enabled(CharacterSkillManager.DASH, true)
	check(skills.get_skill(&"ricochet_storm").damage == city_profile.storm_damage and skills.get_skill(&"ricochet_storm").skill_definition in city_profile.skill_definitions, "Manager applies city storm and skill configuration")
	check(terrain.data.resource_path == "res://data/city/terrain.tres" and terrain.surface_data.resource_path == "res://data/city/surface.tres", "City owns independent terrain and painted surface")
	check(terrain.get_world_rect().encloses(wave.battle_area), "Combat bounds are covered by translated terrain")
	check(terrain.top_material.shader.resource_path == "res://shaders/terrain/terrain.gdshader" and terrain.surface_data.chunks.size() > 0, "World ground art and hand-painted surface are present")
	check(player.sword != null and player.ricochet_rules == city_profile.ricochet_rules, "Sword and body ricochet use city configuration")
	check(wave.population_rules == city_profile.population_rules and wave.terrain == terrain, "Combat session uses city balance and real terrain")
	check(city.get_node("NightAtmosphere").bokeh != null and is_equal_approx(player.movement_camera.distance, 28.0), "City night effects and authored camera are preserved")
	ui._bottom_toggle.pressed.emit()
	check(ui.bottom_bars_collapsed and not ui._hud.visible and not ui._item_bar.visible, "Button hides both bottom bars")
	check(not ui.menu_open and get_first_node_in_group(&"gameplay_input_blockers") == null and not wave.combat_frozen, "Hiding bars does not block input or freeze combat")
	ui.open_menu()
	await frames(3)
	ui._finish_close()
	check(ui.bottom_bars_collapsed and not ui._hud.visible and not ui._item_bar.visible, "Menu round trip preserves collapsed state")
	ui._bottom_toggle.pressed.emit()
	check(ui._hud.visible and ui._item_bar.visible, "Button restores bottom bars")
	check(wave.can_start_run() and wave.start_run() and wave.skill_draft.initial_choice.is_open, "City opens the real initial skill choice")
	wave.skill_draft.initial_choice.reveal_now()
	check(wave.skill_draft.initial_choice.select_option(wave.skill_draft._initial_cards[0].id), "Initial card can be selected")
	wave.skill_draft.initial_choice.confirm_selection()
	await frames(3)
	if wave.phase != WavePrototype.Phase.BATTLE: print("CITY_START_REASON ", wave.result_reason)
	check(wave.phase == WavePrototype.Phase.BATTLE and growth.active, "City enters battle and activates growth")
	for index in 180:
		if not wave.enemies.is_empty(): break
		await physics_frame
	check(not wave.enemies.is_empty(), "Enemies spawn at valid city street locations")
	check(player.sword.request_manual(Vector3.FORWARD), "The basic sword accepts manual attack independently of both skill registries")
	check(skills.begin_charge(Vector3.FORWARD), "RunSkillManager accepts body charge")
	skills.aim_charge(Vector3.RIGHT)
	check(player.body_ricochet.direction.is_equal_approx(Vector3.RIGHT), "RunSkillManager forwards external charge aiming")
	player.body_ricochet.advance(0.5, Vector3.ZERO, false)
	check(skills.release_charge(), "RunSkillManager launches the player")
	await frames(8)
	player.body_ricochet.cancel(true)
	if not wave.enemies.is_empty():
		var enemy := wave.enemies[0]
		enemy.spawn_delay = 0.0
		enemy.take_damage(100000)
		check(not growth._drops.is_empty(), "Real enemy death drops experience in city")
	growth.drop_experience(player.global_position, 20)
	growth.collect_all()
	check(wave.combat_frozen and growth.choice_ui.is_open, "Experience triggers upgrade selection and battle freeze")
	check(skills.get_registered_ids().all(func(id: StringName): return skills.get_skill(id).process_mode == Node.PROCESS_MODE_DISABLED), "All registered skill components participate in battle freeze")
	var weather := city.get_node("MapEffects/Weather")
	var clock: float = weather._clock
	await frames(5)
	check(weather._clock > clock, "Weather continues during upgrade choice")
	for index in 8:
		if not growth.choice_ui.is_open: break
		growth.choice_ui.reveal_now()
		growth.choice_ui.select_option(growth.choice_options[0].id)
		growth.choice_ui.confirm_selection()
	check(not wave.combat_frozen, "Confirming upgrades resumes combat")
	wave._finish("city integration check", WavePrototype.Outcome.RETREAT)
	wave.retry()
	check(wave.phase == WavePrototype.Phase.READY and wave.skill_draft.initial_choice.is_open and wave.enemies.is_empty(), "Retry clears enemies and returns to initial choice")
	wave.skill_draft.initial_choice.cancel()
	await frames(30)
	if RenderingServer.get_rendering_device():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/city-combat-verified.png")
	city.free()
	await frames(3)
	check(get_first_node_in_group(&"gameplay_input_blockers") == null, "Leaving city clears modal input locks")
	for path in hashes: check(FileAccess.get_sha256(path) == hashes[path], "Source resource remains unchanged: " + path)
	print(JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
