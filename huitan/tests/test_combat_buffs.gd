extends SceneTree

class ProjectileProbe extends Node3D:
	func get_combat_stats(modifiers: RunCombatModifiers) -> Dictionary:
		return {"name": "直线投射", "damage": 5.0 * modifiers.damage_multiplier(), "interval": modifiers.interval_multiplier()}

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(55.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func near(actual: float, expected: float, message: String) -> void:
	check(is_equal_approx(actual, expected), message)

func choose(growth: RunGrowth, id: StringName) -> void:
	check(growth.choice_ui.select_option(id), "Requested real buff is offered")
	growth.choice_ui.confirm_selection()

func run() -> void:
	# 此用例继续验证旧的有限、线性配置；持续成长与专精另有完整专项。
	var damage: GrowthBuffDefinition = load("res://data/growth/damage.tres").duplicate()
	var cooldown: GrowthBuffDefinition = load("res://data/growth/cooldown.tres").duplicate()
	var coverage: GrowthBuffDefinition = load("res://data/growth/range.tres").duplicate()
	for item in [damage, cooldown, coverage]:
		item.max_level = 3
		item.breakthrough_every = 0
	cooldown.attribute = GrowthBuffDefinition.Attribute.COOLDOWN
	cooldown.bonus_per_level = 0.1
	cooldown.bonus_cap = 0.5
	var modifiers := RunCombatModifiers.new()
	var preview := modifiers.preview_after(damage)
	near(preview.damage_multiplier(), 1.2, "Preview shows next coefficient")
	near(modifiers.damage_multiplier(), 1.0, "Preview does not award the buff")
	for level in 3:
		check(modifiers.apply_buff(damage), "Damage level accepted")
		check(modifiers.apply_buff(cooldown), "Cooldown level accepted")
		check(modifiers.apply_buff(coverage), "Range level accepted")
	near(modifiers.damage_multiplier(), 1.6, "Damage stacks additively against the base")
	near(modifiers.interval_multiplier(), 0.7, "Cooldown uses base reductions rather than repeated multiplication")
	near(modifiers.range_multiplier(), 1.45, "Range has three additive levels")
	check(not modifiers.apply_buff(damage) and not modifiers.apply_buff(cooldown) and not modifiers.apply_buff(coverage), "Max level rejects further awards")
	var capped := cooldown.duplicate() as GrowthBuffDefinition
	capped.max_level = 20
	capped.bonus_per_level = 0.3
	modifiers.reset()
	check(modifiers.apply_buff(capped) and modifiers.apply_buff(capped), "Partial gain can reach the cap")
	near(modifiers.interval_multiplier(), 0.5, "Cooldown respects configured total cap")
	check(not modifiers.can_apply(capped), "Capped entries have no further benefit")

	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("WorldMainMenu").show_on_world_start = false
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("LoadoutUI").save_enabled = false
	# 此用例验收数值和冻结，声音由专项用例验收，避免退出时留下播放线程。
	world.get_node("MapEffects/BGM").music_enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	for node in world.find_children("*", "Node", true, false):
		if node is UIAudio or node is CoreFeedbackAudio: node.enabled = false
	var profile := world.get_node("BattleConfiguration").configuration as SceneCombatConfiguration
	profile = profile.duplicate() as SceneCombatConfiguration
	profile.experience_rules = ExperienceRules.new()
	profile.sword_rules = null
	profile.growth_rules = null
	profile.population_rules = null
	profile.spawn_shadow_settings = null
	profile.growth_definitions.assign([damage, cooldown, coverage])
	world.get_node("BattleConfiguration").configuration = profile
	world.get_node("WavePrototype/RunGrowth").enabled = true
	world.get_node("WavePrototype/FanAutoAttack").enabled = true
	# 数值用例独立于正式地图美术摆放，保留真实地形与战斗组件。
	var details := world.get_node("WorldDetails")
	world.remove_child(details)
	details.free()
	for prop in world.get_children():
		if prop is PlazaProp:
			world.remove_child(prop)
			prop.free()
	root.add_child(world)
	current_scene = world
	for frame in 12: await physics_frame
	var wave: WavePrototype = world.get_node("WavePrototype")
	var growth: RunGrowth = wave.get_node("RunGrowth")
	var buffs: RunBuffs = wave.get_node("RunBuffs")
	buffs.definitions[0] = buffs.definitions[0].duplicate() as GrowthBuffDefinition
	var fan: FanAutoAttack = wave.get_node("FanAutoAttack")
	var skills: RunSkillManager = wave.get_node("RunSkillManager")
	var player: Player = world.get_node("Player")
	var definition := fan.skill_definition
	player.set_physics_process(false)
	wave.set_physics_process(false)
	fan.set_physics_process(false)
	growth.set_physics_process(false)
	fan.knockback_distance = 0.0
	fan.audio_enabled = false
	growth.choice_ui.open_duration = 0.0
	growth.cards_per_draw = 100
	wave.skill_draft.initial_choice.open_duration = 0.0
	wave.skill_draft.initial_cards_per_draw = 100
	player.global_position = wave._path.ground_position(wave.global_position) + Vector3.UP * 0.03
	check(wave.start_run(), "Real challenge starts")
	check(wave.skill_draft.initial_choice.select_option(&"initial:fan_slash"), "Choose actual initial A01 before buff checks")
	wave.skill_draft.initial_choice.confirm_selection()
	fan.set_physics_process(false)
	player.global_position = wave._path.ground_position(wave.global_position) + Vector3.UP * 0.03
	(world.get_node("MapEffects/Camera3D") as FollowCamera).snap_to_target()
	for frame in 8: await process_frame
	wave._spawn_queue.clear()
	var spawned := wave._spawn_enemy()
	check(spawned, "Real monster spawns")
	if not spawned:
		world.free()
		quit(1)
		return
	var enemy := wave.enemies[-1]
	enemy.spawn_delay = 0.0
	enemy.set_physics_process(false)
	enemy.health = 500.0
	enemy.global_position = player.global_position + Vector3(0, 0, -2.6)
	wave._spatial_index.update(enemy)
	check(not fan.start_swing(), "Base attack cannot reach a monster at 2.6 meters")
	var weather: Node3D = world.get_node("MapEffects/Weather")
	var weather_clock: float = weather._clock
	growth._grant_experience(10)
	check(growth.choice_ui.is_open and wave.combat_frozen and growth.choice_options.size() >= 5, "Learning other skills, upgrading A01 and all three buffs share the actual level-up pool")
	var descriptions := {}
	for option in growth.choice_options: descriptions[option.id] = option.description
	check(descriptions.has(&"skill:fan_slash:2"), "Weapon upgrade stays available alongside buffs")
	check("×1.00 → ×1.20" in descriptions[&"P01"], "Damage card shows actual coefficient transition")
	check("0% → 10%" in descriptions[&"P02"], "Cooldown card shows the actual shared reduction")
	check("×1.00 → ×1.15" in descriptions[&"P03"], "Range card shows the actual shared coverage gain")
	for frame in 3: await process_frame
	check(not paused and weather._clock > weather_clock, "World and weather run behind frozen combat")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("D:/.codexfile/work/combat-buffs-20261013/choices.png")
	buffs.definitions[0].bonus_per_level = 0.5
	choose(growth, &"P01")
	near(wave.combat_modifiers.damage_multiplier(), 1.2, "Editing configuration cannot change an already presented award")
	buffs.definitions[0].bonus_per_level = 0.2
	# Remaining lifecycle checks isolate buffs after validating the real combined pool.
	growth.candidate_provider = buffs.candidates
	near(fan.get_combat_stats().damage, 12.0, "Choosing a card changes real attack damage")
	growth._grant_experience(15)
	choose(growth, &"P02")
	near(fan.get_combat_stats().interval, 0.72, "Choosing cooldown changes real start interval")
	growth._grant_experience(20)
	choose(growth, &"P03")
	near(fan.get_combat_stats().range, 2.76, "Choosing range changes real target coverage")
	check(fan.start_swing(), "Expanded coverage reaches the previously unreachable enemy")
	near(fan._cooldown, 0.72, "Swing timer uses modified interval")
	growth._grant_experience(25)
	choose(growth, &"P01")
	near(fan.get_combat_stats().damage, 14.0, "Card reads current upgraded damage")
	near(fan.get_attack_stats().damage, 12.0, "Already-started sweep keeps its original damage")
	fan._physics_process(fan.windup_time + fan.sweep_time)
	near(enemy.health, 488.0, "Actual monster loses the snapshotted damage once")
	near(fan._surface_limit(wave._ground_target(), 0.0), 2.76, "Visible slash uses exactly the increased hit radius")
	fan.cancel_current()
	fan._cooldown = 0.0
	check(fan.start_swing(), "Next swing starts normally")
	fan._physics_process(fan.windup_time + fan.sweep_time)
	near(enemy.health, 474.0, "Next actual hit applies the upgraded damage")
	near(fan.damage, 10.0, "Base damage is never cumulatively overwritten")
	near(fan.attack_range, 2.4, "Base coverage stays editable")
	near(fan.attack_interval, 0.8, "Base interval stays editable")
	var retained := wave.combat_modifiers.levels.duplicate()
	wave._set_phase(WavePrototype.Phase.REST)
	check(wave.combat_modifiers.levels == retained, "Safe rest preserves all local buff levels")
	wave._set_phase(WavePrototype.Phase.BATTLE)
	fan.cancel_current()
	check(fan.apply_skill_level(2), "Existing weapon levels remain supported")
	near(fan.get_combat_stats().damage, 16.8, "Weapon damage multiplier and global coefficient each apply once")
	near(fan.get_combat_stats().range, 3.174, "Weapon coverage and global range each apply once")
	check(fan.apply_skill_level(6), "Continuous attack remains compatible")
	near(fan.get_combat_stats().interval, 0.36, "Continuous attack cooldown adjusts contact interval once")
	near(fan.get_attack_stats().rotation_speed, 210.0, "Cooldown does not also multiply rotation speed")
	fan.apply_skill_level(1)
	fan.enabled = false
	var projectile := ProjectileProbe.new()
	wave.add_child(projectile)
	wave.register_combat_node(projectile)
	var projectile_choices := buffs.candidates()
	check(not projectile_choices.any(func(option: GrowthChoiceOption): return option.id == &"P03"), "Pure projectile does not receive an unsupported area card")
	check(projectile_choices.any(func(option: GrowthChoiceOption): return option.id == &"P01") and projectile_choices.any(func(option: GrowthChoiceOption): return option.id == &"P02"), "Future weapon can inherit damage and cooldown through the common interface")
	projectile.free()
	fan.enabled = true
	fan.attack_interval = 0.4
	check(not buffs.candidates().any(func(option: GrowthChoiceOption): return option.id == &"P02"), "Animation-limited attack rejects cooldown with no actual benefit")
	fan.attack_interval = 0.8
	for item in buffs.definitions:
		while wave.combat_modifiers.can_apply(item): wave.combat_modifiers.apply_buff(item)
	check(buffs.candidates().is_empty(), "All maxed buffs leave the pool")
	growth._grant_experience(100)
	check(not growth.choice_ui.is_open and not wave.combat_frozen and growth.state.pending_choices == 0, "Exhausted pool cannot block a level gain or wave clear")
	wave.retreat()
	near(wave.combat_modifiers.damage_multiplier(), 1.0, "Run end clears global damage")
	near(wave.combat_modifiers.range_multiplier(), 1.0, "Run end clears global coverage")
	near(wave.combat_modifiers.interval_multiplier(), 1.0, "Run end clears global cooldown")
	wave.retry()
	check(growth.state.level == 1 and wave.combat_modifiers.levels.is_empty(), "Retry resets both experience and buff levels")
	check(fan.skill_definition == definition and damage.bonus_per_level == 0.2, "Shared skill and buff resources are untouched")
	world.free()
	await create_timer(0.1).timeout
	print("Combat buffs: %d checks, %d failures" % [checks, failures])
	quit.call_deferred(1 if failures else 0)
