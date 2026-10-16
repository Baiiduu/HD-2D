extends SceneTree

class FlatPath extends RefCounted:
	func ground_position(point: Vector3) -> Vector3: return Vector3(point.x, 0, point.z)

class SessionProbe extends Node3D:
	signal changed
	signal run_started
	signal run_ended(reason: String)
	signal enemy_defeated_at(position: Vector3, experience: int)
	signal wave_clearing
	signal phase_changed(phase: int)
	enum Phase { READY, BATTLE, REST, RESULT }
	var player := Node3D.new()
	var _path := FlatPath.new()
	var combat_frozen := false
	func set_combat_frozen(value: bool) -> void: combat_frozen = value

class SkillProbe extends Node:
	var definition: CombatSkillDefinition
	var applied := 0
	func get_skill_definition() -> CombatSkillDefinition: return definition
	func apply_skill_level(level: int) -> bool:
		if level != 0 and not definition.level_data(level): return false
		applied = level
		return true
	func describe_skill_upgrade(from: int, to: int) -> String: return "%d → %d" % [from, to]

var checks := 0
var failures := 0
var world: Node3D
var wave: WavePrototype
var growth: RunGrowth
var skills: RunSkillManager
var fan: FanAutoAttack
var player: Player

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func enemy_at(offset: Vector3) -> WaveEnemy:
	assert(wave._spawn_enemy())
	var enemy := wave.enemies[-1]
	enemy.set_physics_process(false)
	enemy.spawn_delay = 0.0
	enemy.health = 10000.0
	enemy.global_position = player.global_position + offset
	return enemy

func settle(frames := 5) -> void:
	for frame in frames: await physics_frame

func sweep_damage(level: int, count: int) -> void:
	fan.apply_skill_level(level)
	fan._cooldown = 0.0
	var enemy := wave.enemies[0]
	var before := enemy.health
	var stats := fan.get_attack_stats()
	check(fan.start_swing(), "A multi-segment attack starts")
	var duration: float = fan.windup_time + count * (fan.sweep_time + fan.fade_time) + (count - 1) * stats.gap
	for frame in ceili(duration * 60.0): fan._physics_process(1.0 / 60.0)
	check(is_equal_approx(before - enemy.health, stats.damage * count), "Each visible segment has exactly one hit per target")
	check(not fan._mesh.visible, "The finished combo leaves no active slash visual")

func run() -> void:
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	# 隔离技能成长；正式场景的增益配置保持原样，叠加另行验证。
	world.get_node("BattleConfiguration").configuration.growth_definitions.clear()
	# A01 已在正式玩法停用；此兼容原型测试显式开启，不修改正式默认值。
	world.get_node("WavePrototype/FanAutoAttack").enabled = true
	world.get_node("WavePrototype/RunSkillManager").skill_paths.clear()
	world.get_node("WavePrototype/RunSkillManager").skill_paths.append(NodePath("../FanAutoAttack"))
	# 独立验证攻击成长，挡墙在下方显式加入，不依赖可移动地编的摆放。
	var props := world.get_node("WorldDetails")
	world.remove_child(props)
	props.free()
	for prop in world.get_children():
		if prop is PlazaProp:
			world.remove_child(prop)
			prop.free()
	root.add_child(world)
	current_scene = world
	await settle(12)
	wave = world.get_node("WavePrototype")
	growth = wave.get_node("RunGrowth")
	skills = wave.get_node("RunSkillManager")
	fan = wave.get_node("FanAutoAttack")
	player = world.get_node("Player")
	player.set_physics_process(false)
	wave.set_physics_process(false)
	fan.set_physics_process(false)
	growth.set_physics_process(false)
	growth.choice_ui.open_duration = 0.0
	growth.cards_per_draw = 100
	wave.skill_draft.initial_choice.open_duration = 0.0
	growth.choice_ui.hover_duration = 0.0
	fan.knockback_distance = 0.0
	fan.audio_enabled = false
	player.global_position = wave._path.ground_position(wave.global_position) + Vector3.UP * 0.03
	check(wave.start_run(), "The existing challenge starts with skill progression")
	check(skills.get_slots().is_empty() and wave.skill_draft.initial_choice.is_open, "A01 is not granted before initial choice")
	wave.skill_draft.initial_choice.select_option(&"initial:fan_slash")
	wave.skill_draft.initial_choice.confirm_selection()
	fan.set_physics_process(false)
	wave._spawn_queue.clear()
	player.global_position = world.get_node("BattleArea").global_position + Vector3.UP * 0.03
	check(skills.get_level(&"fan_slash") == 1 and fan.skill_level == 1, "Each run starts with actual level-one A01")
	check(skills.candidates().size() == 1 and skills.candidates()[0].icon != null, "Only one real upgrade is offered, using existing Meowa art")
	check(fan.get_attack_stats().damage == 10.0 and fan.get_attack_stats().range == 2.4, "The first level preserves the former attack baseline")
	var health := player.current_health
	growth.drop_experience(player.global_position, 10)
	growth.collect_all()
	check(wave.combat_frozen and growth.choice_ui.is_open, "Experience opens the existing upgrade UI before effects apply")
	growth.choice_ui.select_option(&"skill:fan_slash:2")
	var option := growth.choice_ui.get_selected_option()
	check(option.id == &"skill:fan_slash:2" and option.description.contains("10") and option.description.contains("12"), "Card shows the real next level and damage values")
	check(skills.get_level(&"fan_slash") == 1, "Previewing a card does not grant it")
	growth.choice_ui.confirm_selection()
	check(skills.get_level(&"fan_slash") == 2 and fan.get_attack_stats().damage == 12.0 and fan.get_attack_stats().range > 2.4, "Confirmation applies the upgrade to actual attack parameters")
	check(not wave.combat_frozen and player.current_health == health, "Upgrade restores combat without invented healing")
	wave.skill_draft._choose(2, option.id)
	check(skills.get_level(&"fan_slash") == 2, "A stale or duplicate selection cannot grant another level")
	# 总计 210 经验，完成从人物 1 到 8 级的七次选择。
	growth.drop_experience(player.global_position, 200)
	growth.collect_all()
	check(growth.state.pending_choices == 6, "A large pickup preserves each pending choice")
	for next_level in range(3, 9):
		growth.choice_ui.select_option(StringName("skill:fan_slash:%d" % next_level))
		check(growth.choice_ui.get_selected_option().id == StringName("skill:fan_slash:%d" % next_level), "Each consecutive card uses the updated skill level")
		growth.choice_ui.confirm_selection()
		check(skills.get_level(&"fan_slash") == next_level and wave.combat_frozen == (next_level < 8), "Skills apply before the next card, with no combat gap")
	check(skills.candidates().is_empty() and fan.get_attack_stats().rotation and fan.get_attack_stats().blades == 2, "The final level reaches continuous dual-blade rotation and leaves the upgrade pool")
	growth.drop_experience(player.global_position, 100)
	growth.collect_all()
	check(growth.state.pending_choices == 0 and not growth.choice_ui.is_open and not wave.combat_frozen, "An exhausted pool consumes no fake reward and cannot trap combat in a modal")
	await settle()
	var hud: SkillHUD = world.get_node("LoadoutUI")._hud
	check(hud.get_child(0).get_node("Level").text == "MAX" and hud.get_child(0).has_node("Icon"), "The actual skill and maximum level reach the existing HUD")
	wave._set_phase(WavePrototype.Phase.REST)
	check(skills.get_level(&"fan_slash") == 8, "Wave rest preserves skill levels")
	wave._set_phase(WavePrototype.Phase.BATTLE)
	growth.enabled = false
	var enemy := enemy_at(Vector3(0, 0, -1.5))
	sweep_damage(4, 2)
	sweep_damage(5, 3)
	# 固定目标与六秒战斗窗口，防止连斩进化为旋转后实际输出反而降低。
	var previous_damage := 0.0
	var progression: Array[float] = []
	for level in range(1, 9):
		fan.apply_skill_level(level)
		fan._cooldown = 0.0
		enemy.health = 100000.0
		for frame in 360: fan._physics_process(1.0 / 60.0)
		var total := 100000.0 - enemy.health
		progression.append(total)
		check(total > previous_damage, "Each successive level increases actual stationary-target output")
		previous_damage = total
	print("A01 six-second damage by level: ", progression)
	var behind := enemy_at(Vector3(0, 0, 1.5))
	var left := enemy_at(Vector3(-1.5, 0, 0))
	var right := enemy_at(Vector3(1.5, 0, 0))
	var far := enemy_at(Vector3(0, 0, -6.0))
	var raised := enemy_at(Vector3(0.4, 1.1, -1.2))
	fan.apply_skill_level(8)
	fan._cooldown = 0.0
	var before := enemy.health
	var seamless := true
	for frame in 120:
		fan._physics_process(1.0 / 120.0)
		seamless = seamless and fan._mesh.visible and fan._extra_meshes[0].visible
	check(seamless, "High-level rotation has no blank gap between frames")
	check(enemy.health < before and behind.health < 10000.0 and left.health < 10000.0 and right.health < 10000.0, "Rotation damages all world directions")
	check(far.health == 10000.0 and raised.health == 10000.0, "Rotation keeps the actual radius and terrain-height boundaries")
	var at_120 := before - enemy.health
	fan.cancel_current()
	before = enemy.health
	for frame in 30: fan._physics_process(1.0 / 30.0)
	check(absf(before - enemy.health - at_120) <= fan.get_attack_stats().damage, "30 and 120 Hz stay within one discrete hit, without frame-based damage multiplication")
	var rotation := fan._spin_time
	var basis := fan._mesh.global_basis
	wave.set_combat_frozen(true)
	await settle()
	check(fan._spin_time == rotation and fan._mesh.global_basis == basis, "Growth freeze retains the exact rotation animation and clock")
	wave.set_combat_frozen(false)
	fan._physics_process(1.0 / 60.0)
	check(fan._spin_time > rotation, "The same continuous animation resumes after a choice")
	var blink_start := player.global_position
	var spin_time := fan._spin_time
	var spin_audio_clock := fan._spin_audio_clock
	var spin_basis := fan._mesh.global_basis
	var spin_hits := fan._spin_hits.duplicate()
	var cooldown := fan._cooldown
	before = enemy.health
	player._blink._direction = Vector3.RIGHT
	player._blink._teleport()
	check(player.global_position.distance_to(blink_start) > 2.0, "The real PlayerBlink collision sweep performs a teleport")
	check(fan._spinning and fan._mesh.visible and fan._extra_meshes[0].visible and fan._spin_time == spin_time and fan._spin_audio_clock == spin_audio_clock and fan._cooldown == cooldown, "Real blink preserves both rotating blades, their timers and cooldown")
	check(fan._mesh.global_position.distance_to(wave._ground_target()) < 0.01 and fan._extra_meshes[0].global_position.distance_to(wave._ground_target()) < 0.01 and fan._mesh.global_basis == spin_basis, "Both blades immediately follow the destination without resetting rotation phase")
	check(fan._spin_hits == spin_hits and enemy.health == before, "Blink preserves target protection and produces no immediate extra damage")
	fan._physics_process(0.01)
	check(fan._spin_time > spin_time and enemy.health == before, "Rotation continues after landing without bypassing the target hit interval")
	var blink_destination := player.global_position
	player.global_position = blink_start
	player.blink_travelled.emit(blink_destination, blink_start)
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.5, 2.0, 0.15)
	collision.shape = box
	wall.add_child(collision)
	world.add_child(wall)
	wall.global_position = player.global_position + Vector3(0, 0.5, -0.7)
	await settle()
	before = enemy.health
	fan._cooldown = 0.0
	for frame in 60: fan._physics_process(1.0 / 60.0)
	check(enemy.health == before, "Final-level rotation cannot damage through a wall")
	fan._locked_basis = Basis.IDENTITY
	check(fan._surface_limit(wave._ground_target(), 0.0) < 0.7, "Final-level effect is clipped at the same wall")
	wall.free()
	# 同一等级叠加通用增益，基础配置不会被改写或重复乘算。
	var damage_buff: GrowthBuffDefinition = load("res://data/growth/damage.tres")
	var range_buff: GrowthBuffDefinition = load("res://data/growth/range.tres")
	wave.combat_modifiers.apply_buff(damage_buff)
	wave.combat_modifiers.apply_buff(range_buff)
	check(is_equal_approx(fan.get_attack_stats().damage, 100.0 * wave.combat_modifiers.damage_multiplier()), "Skill damage and shared damage bonuses compose once")
	check(is_equal_approx(fan.get_attack_stats().range, 5.04 * wave.combat_modifiers.range_multiplier()), "Skill radius and shared range bonuses use the same visual and damage values")
	check(fan.damage == 10.0 and fan.attack_range == 2.4, "Growth never rewrites the base inspector parameters")
	wave._finish("test retry", WavePrototype.Outcome.RETREAT)
	check(not fan._spinning and not fan._mesh.visible, "Result clears ongoing continuous attacks")
	wave.retry()
	check(skills.get_level(&"fan_slash") == 0 and wave.skill_draft.initial_choice.is_open, "Retry clears A01 and asks for the initial skill again")
	wave.skill_draft.initial_choice.select_option(&"initial:fan_slash")
	wave.skill_draft.initial_choice.confirm_selection()
	fan.set_physics_process(false)
	check(skills.get_level(&"fan_slash") == 1 and fan.skill_level == 1 and fan.get_attack_stats().damage == 10.0, "Retry restores the baseline rather than multiplying it again")
	check(fan._mesh.transform == Transform3D.IDENTITY, "Returning from rotation leaves no rotated child transform")
	wave._finish("test home", WavePrototype.Outcome.RETREAT)
	wave.return_home()
	check(skills.get_level(&"fan_slash") == 0, "Returning home clears all local skill learning")
	world.free()
	await settle()
	await multiple_skills()
	await create_timer(0.3).timeout
	print("PASS: run skills and A01 levels, %d checks" % checks)
	quit(1 if failures else 0)

func multiple_skills() -> void:
	var session := SessionProbe.new()
	session.add_child(session.player)
	var local_growth: RunGrowth = load("res://scenes/growth/run_growth.tscn").instantiate()
	local_growth.name = "RunGrowth"
	local_growth.session = session
	session.add_child(local_growth)
	var controller := RunSkillManager.new()
	var draft := RunSkillDraft.new()
	draft.session = session
	draft.manager = controller
	draft.growth = local_growth
	for id in [&"first", &"second"]:
		var component := SkillProbe.new()
		component.name = String(id)
		component.definition = CombatSkillDefinition.new()
		component.definition.id = id
		component.definition.display_name = String(id)
		component.definition.levels = [CombatSkillLevel.new(), CombatSkillLevel.new()]
		session.add_child(component)
		controller.skill_paths.append(NodePath("../" + String(id)))
	session.add_child(controller)
	session.add_child(draft)
	root.add_child(session)
	local_growth.set_physics_process(false)
	local_growth.choice_ui.open_duration = 0.0
	check(controller.candidates().size() == 2, "A second component participates through the same framework")
	draft._choose(2, &"skill:first:1")
	check(controller.get_level(&"first") == 0, "Inactive runs cannot learn a previewed skill")
	session.run_started.emit()
	local_growth.state.add_experience(10)
	local_growth.choice_ui.select_option(&"skill:first:1")
	local_growth.choice_ui.confirm_selection()
	check(controller.get_level(&"first") == 1 and controller.get_level(&"second") == 0, "Learning grants only the selected skill")
	local_growth.state.add_experience(15)
	local_growth.choice_ui.select_option(&"skill:second:1")
	local_growth.choice_ui.confirm_selection()
	local_growth.state.add_experience(20)
	local_growth.choice_ui.select_option(&"skill:second:2")
	local_growth.choice_ui.confirm_selection()
	check(controller.get_level(&"first") == 1 and controller.get_level(&"second") == 2, "Choosing another skill upgrades only its component")
	check(controller.candidates().size() == 1 and controller.candidates()[0].id == &"skill:first:2", "A maxed skill is filtered while another still has upgrades")
	local_growth.state.add_experience(25)
	local_growth.choice_ui.select_option(&"skill:first:2")
	local_growth.choice_ui.confirm_selection()
	local_growth.state.add_experience(100)
	check(controller.candidates().is_empty() and local_growth.state.pending_choices == 0 and not session.combat_frozen, "An exhausted multi-skill pool also releases the existing choice flow")
	session.run_ended.emit("new preparation")
	session.phase_changed.emit(SessionProbe.Phase.READY)
	session.run_started.emit()
	local_growth.state.add_experience(10)
	session.run_ended.emit("cancel pending choice")
	draft._choose(2, &"skill:first:1")
	check(controller.get_level(&"first") == 0 and not session.combat_frozen, "Run end invalidates pending skill callbacks and releases the modal")
	var dynamic := SkillProbe.new()
	dynamic.name = "DynamicSkill"
	dynamic.definition = CombatSkillDefinition.new()
	dynamic.definition.id = &"dynamic"
	dynamic.definition.display_name = "Dynamic"
	dynamic.definition.levels = [CombatSkillLevel.new(), CombatSkillLevel.new()]
	session.add_child(dynamic)
	check(controller.register_skill(dynamic) and controller.register_skill(dynamic) and controller.get_registered_ids().size() == 3, "Runtime registration is idempotent and shares the registry")
	check(controller.get_level(&"dynamic") == 0 and dynamic.applied == 0, "Runtime skills start unlearned")
	check(controller.set_skill_level(&"dynamic", 2) and controller.get_level(&"dynamic") == 2 and dynamic.applied == 2, "Unified level API applies the component level")
	check(not controller.set_skill_level(&"dynamic", 3) and controller.get_level(&"dynamic") == 2, "Invalid level does not overwrite learned state")
	controller.unregister_skill(&"dynamic")
	check(controller.get_skill(&"dynamic") == null and dynamic.applied == 0 and controller.get_level(&"dynamic") == 0, "Unregister clears learning and disables the old component")
	check(controller.register_skill(dynamic), "A removed component can be registered again")
	dynamic.free()
	check(controller.get_skill(&"dynamic") == null and controller.get_registered_ids().size() == 2, "Freed skills remove their registration automatically")
	session.free()
	await settle()
