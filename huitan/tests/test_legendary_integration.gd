extends SceneTree
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func run() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("WorldMainMenu").show_on_world_start = false
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("MapEffects/BGM").music_enabled = false
	# 只验证成长逻辑，避免退出时仍在 Dummy 音频线程中播放开牌／升级声音。
	world.get_node("MapEffects/CoreFeedbackAudio").enabled = false
	world.get_node("MapEffects/GameAudio").enabled = false
	var binding := world.get_node("BattleConfiguration")
	var configuration: SceneCombatConfiguration = binding.configuration.duplicate()
	configuration.population_rules = configuration.population_rules.duplicate()
	configuration.population_rules.simulation_mode = false
	configuration.spawn_shadow_settings = null
	binding.configuration = configuration
	root.add_child(world)
	var wave: WavePrototype = world.get_node("WavePrototype")
	var growth: RunGrowth = wave.get_node("RunGrowth")
	var draft := wave.skill_draft
	while not wave._path_ready: await physics_frame
	for index in 10: await physics_frame
	wave.set_physics_process(false)
	growth.set_physics_process(false)
	draft.initial_choice.open_duration = 0.0
	draft.initial_choice._audio.enabled = false
	growth.choice_ui.open_duration = 0.0
	growth.choice_ui._audio.enabled = false
	check(wave.start_run() and draft.initial_choice.is_open, "World opens the real starting draft")
	check(draft._initial_cards.any(func(option): return option.id == &"initial_buff:L01" and option.get_card_rarity() == 2), "The actual starting draw includes the legendary")
	draft.initial_choice.select_option(&"initial_buff:L01")
	draft.initial_choice.confirm_selection()
	check(wave.phase == WavePrototype.Phase.BATTLE and not draft.initial_choice.is_open, "A growth-only choice starts battle without another initial-skill dialog")
	check(wave.combat_modifiers.level_for(&"L01") == 1 and wave.run_skill_manager.get_slots().is_empty(), "Initial buff survives run reset without silently granting a skill")
	var mods := wave.combat_modifiers
	var player: Player = wave.player
	player.set_physics_process(false)
	var walking := player.get_movement_speed()
	check(wave._spawn_enemy(), "A real registered enemy can spawn for kill feedback")
	var enemy := wave.enemies[-1]
	enemy.spawn_delay = 0.0
	enemy.take_damage(100000.0)
	check(mods.haste_stacks() == 1, "A real fatal hit grants one haste stack")
	wave._enemy_defeated(enemy)
	check(mods.haste_stacks() == 1, "Repeated death callbacks cannot duplicate haste")
	check(is_equal_approx(player.get_movement_speed(), walking * 1.05), "Actual character movement reads the live haste multiplier")
	var body := player.body_ricochet
	body._settings = player.ricochet_rules.duplicate()
	body.state = PlayerRicochet.State.FLYING
	body.flight_speed = 12.0
	check(is_equal_approx(body.movement_speed, 12.6) and body.flight_speed == 12.0, "An active flight speeds up without refilling its remaining energy")
	wave.set_combat_frozen(true)
	wave._physics_process(20.0)
	check(mods.haste_stacks() == 1, "Upgrade freeze does not age temporary stacks")
	wave.set_combat_frozen(false)
	mods.advance_temporary(4.01)
	check(is_equal_approx(body.movement_speed, 12.0) and is_equal_approx(player.get_movement_speed(), walking), "Expiry restores both live movement channels")
	body.cancel()
	growth.rules = ExperienceRules.new()
	growth.rules.first_level_experience = 1
	growth.rules.per_level_increase = 0
	growth.rules.curve_increase = 0
	growth.state.rules = growth.rules
	growth.state.level = 9
	growth._grant_experience(2)
	check(growth.choice_ui.title.contains("10") and growth.choice_options.any(func(option): return option.id == &"L01"), "Pending level ten guarantees a real legendary upgrade")
	growth.choice_ui.request_reroll()
	check(growth.choice_options.any(func(option): return option.id == &"L01"), "A tenth-level reroll retains the legendary guarantee")
	growth.choice_ui.select_option(&"L01")
	growth.choice_ui.confirm_selection()
	check(mods.level_for(&"L01") == 2 and growth.choice_ui.title.contains("11"), "Legendary confirmation applies once and advances to pending eleven")
	check(growth._candidate_pool.any(func(option): return option.id == &"L01"), "Learned legendary upgrades enter the ordinary candidate pool")
	growth.choice_ui.select_option(growth.choice_options[0].id)
	growth.choice_ui.confirm_selection()
	var legendary: GrowthBuffDefinition = load("res://data/combat/scenes/world/growth/legendary/kill_haste.tres")
	for index in legendary.max_level: mods.apply_buff(legendary)
	check(mods.level_for(&"L01") == 5 and not draft.candidates().any(func(option): return option.id == &"L01"), "A fully learned legendary leaves the actual candidate pool")
	var skipped: Array[int] = []
	growth.growth_choice_skipped.connect(func(level: int): skipped.append(level))
	var rerolls := growth.rerolls_left
	growth.state.level = 19
	growth._grant_experience(2)
	check(skipped.is_empty() and growth.choice_ui.is_open and growth.choice_ui.title.contains("20") and growth.choice_ui.title.contains("史诗"), "World replaces an exhausted legendary milestone with valid epic choices without losing the reward")
	check(growth.rerolls_left == rerolls and not growth.choice_options.any(func(option): return option.id == &"L01"), "Fallback neither charges rerolls nor offers a capped legendary")
	growth.choice_ui.select_option(growth.choice_options[0].id)
	growth.choice_ui.confirm_selection()
	check(growth.choice_ui.is_open and growth.choice_ui.title.contains("21"), "The fallback reward applies before the next ordinary pending choice")
	wave.retreat()
	check(mods.level_for(&"L01") == 0 and mods.haste_stacks() == 0, "Run end clears the learned legendary and its temporary state")
	wave.return_home()
	draft.buffs.definitions = []
	for id in wave.run_skill_manager.get_registered_ids(): wave.run_skill_manager.set_skill_available(id, false)
	check(not draft.should_offer_initial_choice(), "No valid starting skill or growth skips the opening choice")
	check(wave.start_run() and wave.phase == WavePrototype.Phase.BATTLE and not draft.initial_choice.is_open, "An empty initial pool starts real battle without a blank dialog")
	wave.retreat()
	world.queue_free()
	await process_frame
	# 场景退出后给 Dummy 音频服务时间释放播放实例，再结束进程。
	await create_timer(0.5).timeout
	print("Legendary integration: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
