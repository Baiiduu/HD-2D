extends SceneTree

class CombatProbe extends Node3D:
	var ticks := 0
	func _physics_process(_delta: float) -> void: ticks += 1

var checks := 0

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	assert(value, message)

func run() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	root.add_child(world)
	current_scene = world
	var wave: WavePrototype = world.get_node("WavePrototype")
	var growth: RunGrowth = wave.get_node("RunGrowth")
	var player: Player = world.get_node("Player")
	var fan: FanAutoAttack = wave.get_node("FanAutoAttack")
	var weather: Node3D = world.get_node("MapEffects/Weather")
	for frame in 12: await physics_frame
	player.set_physics_process(false)
	wave.set_physics_process(false)
	fan.set_physics_process(false)
	growth.set_physics_process(false)
	growth.choice_ui.open_duration = 0.0
	growth.choice_ui.hover_duration = 0.0
	player.global_position = wave._path.ground_position(wave.global_position) + Vector3.UP * 0.03
	check(wave.start_run() and growth.active, "Actual wave start initializes local growth")
	check(wave._spawn_enemy(), "Actual configured enemy can spawn")
	var enemy := wave.enemies[0]
	enemy.spawn_delay = 0.0
	enemy.set_physics_process(false)
	enemy.take_damage(1000)
	check(growth._drops.size() == 1 and growth._drops[0].amount == wave.default_enemy.experience_reward, "Actual enemy death produces its configured experience drop")
	wave._enemy_defeated(enemy)
	check(growth._drops.size() == 1, "Repeated death notification does not duplicate experience")
	player.global_position = growth._drops[0].global_position + Vector3.UP * 0.03
	growth._physics_process(1.0)
	check(growth.state.total_experience == 3 and growth._drops.is_empty(), "Actual player position collects the drop")
	check(wave._spawn_enemy(), "A living enemy remains for freeze checks")
	enemy = wave.enemies[-1]
	enemy.process_mode = Node.PROCESS_MODE_PAUSABLE
	enemy.spawn_delay = 0.0
	var attack := CombatProbe.new()
	wave._attack_root.add_child(attack)
	var weapon := CombatProbe.new()
	weapon.process_mode = Node.PROCESS_MODE_ALWAYS
	wave.add_child(weapon)
	wave.register_combat_node(weapon)
	growth.drop_experience(player.global_position, 7)
	growth._physics_process(1.0)
	check(growth.choice_ui.is_open and growth.state.level == 2 and wave.combat_frozen, "Actual level gain opens the assembled choice UI")
	check(enemy.process_mode == Node.PROCESS_MODE_DISABLED and wave._attack_root.process_mode == Node.PROCESS_MODE_DISABLED and fan.process_mode == Node.PROCESS_MODE_DISABLED and weapon.process_mode == Node.PROCESS_MODE_DISABLED, "Enemy, hazards and registered player attacks freeze together")
	var health := player.current_health
	var position := enemy.global_position
	var wave_clock := wave._wave_clock
	var hazard_ticks := attack.ticks
	var weapon_ticks := weapon.ticks
	var weather_clock: float = weather._clock
	wave._hurt_clock = 0.0
	check(not wave._damage_player(20, wave._generation), "Late attack callbacks cannot hurt the player during a choice")
	var enemy_health := enemy.health
	enemy.take_damage(5)
	check(enemy.health == enemy_health, "Late player attack callbacks cannot damage frozen enemies")
	check(not wave._spawn_enemy() and not fan.start_swing(), "No new monster or player swing can start during a choice")
	wave._physics_process(10.0)
	await create_timer(0.15).timeout
	check(wave._wave_clock == wave_clock and enemy.global_position == position and attack.ticks == hazard_ticks and weapon.ticks == weapon_ticks, "Combat clocks, movement and hazards remain unchanged")
	check(not paused and weather._clock > weather_clock and player.current_health == health, "Weather keeps running while battle damage is rejected")
	growth.choice_ui.confirm_selection()
	check(not wave.combat_frozen and enemy.process_mode == Node.PROCESS_MODE_PAUSABLE and weapon.process_mode == Node.PROCESS_MODE_ALWAYS and fan.process_mode == Node.PROCESS_MODE_INHERIT, "Confirmation restores exact original node process modes")
	var registered_count := wave._combat_nodes.size()
	weapon.free()
	check(wave._combat_nodes.size() == registered_count - 1, "Removing a registered weapon leaves no stale freeze entry")
	check(wave._damage_player(1, wave._generation), "Battle damage returns after confirmation")
	enemy.set_physics_process(false)
	enemy.take_damage(1000)
	wave._spawn_queue.clear()
	growth.drop_experience(player.global_position + Vector3(8, 0, 0), 30)
	wave._physics_process(0.01)
	check(wave.phase == WavePrototype.Phase.BATTLE and wave.combat_frozen and growth._drops.is_empty(), "Wave boundary collects experience and waits for level choices")
	var pending := growth.state.pending_choices
	check(pending > 0 and wave.completed_waves == 0, "Wave completion cannot run ahead of pending upgrades")
	for choice in pending: growth.choice_ui.confirm_selection()
	wave._physics_process(0.01)
	check(wave.phase == WavePrototype.Phase.REST and wave.completed_waves == 1 and not wave.combat_frozen, "Cleared wave enters safe rest after all choices")
	check(wave.start_next_wave(), "Next wave starts normally after growth")
	check(growth.state.level > 1, "Growth persists across waves within one run")
	growth.drop_experience(player.global_position + Vector3(8, 0, 0), 100)
	player.take_damage(player.max_health)
	wave._physics_process(0.01)
	check(wave.phase == WavePrototype.Phase.RESULT and not growth.active and growth._drops.is_empty() and not wave.combat_frozen, "Defeat cleans up drops and growth input without awarding cancelled enemies")
	wave.retry()
	check(wave.phase == WavePrototype.Phase.BATTLE and growth.state.level == 1 and growth.state.total_experience == 0 and growth.state.pending_choices == 0, "Actual retry resets experience and level")
	growth.drop_experience(player.global_position, 30)
	growth.collect_all()
	var restarted: Array[bool] = []
	var on_result := func(phase: int):
		if phase == WavePrototype.Phase.RESULT:
			wave.retry()
			restarted.append(wave.phase == WavePrototype.Phase.BATTLE and not growth.choice_ui.is_open and growth.state.level == 1)
	wave.phase_changed.connect(on_result)
	wave._finish("callback retry", WavePrototype.Outcome.RETREAT)
	check(restarted == [true] and growth.active and not wave.combat_frozen, "A result callback can retry even when an upgrade modal was pending")
	world.free()
	await create_timer(0.1).timeout
	check(get_first_node_in_group(&"gameplay_input_blockers") == null, "World removal leaves no modal input lock")
	print("Growth/wave integration: %d checks passed" % checks)
	quit.call_deferred()
