extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("FAIL: ", message)

func total(definition: WaveDefinition) -> int:
	var count := 0
	for entry in definition.entries: count += entry.count
	return count

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)

func run() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	root.add_child(world)
	current_scene = world
	for frame in 12: await physics_frame
	var wave: WavePrototype = world.get_node("WavePrototype")
	var growth: RunGrowth = wave.get_node("RunGrowth")
	var fan: FanAutoAttack = wave.get_node("FanAutoAttack")
	var player: Player = world.get_node("Player")
	var hud: WaveHUD = wave.get_node("WaveHUD")
	wave.set_physics_process(false)
	player.set_physics_process(false)
	growth.set_physics_process(false)
	fan.set_physics_process(false)
	fan.audio_enabled = false
	growth.choice_ui.open_duration = 0.0
	player.global_position = wave._path.ground_position(wave.global_position) + Vector3.UP * 0.03
	check(wave.endless_mode and wave.start_run(), "Production starts an endless challenge")
	check(wave.is_endless() and wave.wave_count() == 0 and wave.get_run_state().endless, "State explicitly distinguishes an unbounded wave count")
	player.global_position = world.get_node("BattleArea").global_position + Vector3.UP * 0.03
	(world.get_node("MapEffects/Camera3D") as FollowCamera).snap_to_target()
	var saved_templates := wave.waves.duplicate()
	var original_last := wave._run_waves[-1]
	var fourth := wave._definition_for_wave(4)
	check(total(fourth) == 48 and total(original_last) == 40, "Fourth wave grows without changing the last template")
	check(fourth.entries[0].count == 12 and fourth.entries[1].count == 22 and fourth.entries[2].count == 14, "Additional enemies follow the original group proportions")
	for index in fourth.entries.size():
		var before := original_last.entries[index]
		var after := fourth.entries[index]
		check(before.enemy == after.enemy and before.spawn_zone_ids == after.spawn_zone_ids and before.warning_seconds == after.warning_seconds, "Generated group retains monster, zones and warning")
		check(is_equal_approx(after.interval, before.interval * 0.97), "Fourth wave uses configured interval reduction")
		if index > 0:
			var previous := original_last.entries[index - 1]
			var previous_after := fourth.entries[index - 1]
			var gap := before.start_delay - previous.start_delay - (previous.count - 1) * previous.interval
			var actual_gap := after.start_delay - previous_after.start_delay - (previous_after.count - 1) * previous_after.interval
			check(is_equal_approx(gap, actual_gap), "Group lulls survive increased counts")
	var late := wave._definition_for_wave(1000000000)
	check(total(late) == 160 and wave._run_waves.size() == 3, "Very late waves stay bounded without accumulating templates")
	check(late.entries.all(func(entry: WaveSpawnEntry): return entry.interval >= 0.18), "Late spawn rate keeps the configured minimum interval")
	check(original_last.entries[0].count == 10 and original_last.entries[1].count == 18, "Planning never mutates the source groups")
	# Inspector edits are reserved for the next run, including the mode itself.
	wave.endless_mode = false
	wave.endless_enemies_per_wave = 0
	wave.endless_max_enemies = 40
	wave.waves.clear()
	check(wave.is_endless() and total(wave._definition_for_wave(4)) == 48, "Current run keeps its mode and progression snapshot")
	var clears: Array[int] = []
	var endings: Array[String] = []
	wave.wave_cleared.connect(func(number: int): clears.append(number))
	wave.run_ended.connect(func(reason: String): endings.append(reason))
	var expected := [18, 28, 40, 48, 56, 64, 72]
	var killed := 0
	var picked := 0
	for index in expected.size():
		var number := index + 1
		check(wave.wave == number and wave._pending == expected[index], "Real wave registers every planned enemy")
		var clock := wave._wave_clock
		wave.set_combat_frozen(true)
		wave._physics_process(100.0)
		check(wave._wave_clock == clock and wave._pending == expected[index], "Endless queue and clocks respect combat freeze")
		wave.set_combat_frozen(false)
		var steps := 0
		while wave.phase == WavePrototype.Phase.BATTLE and steps < 400:
			steps += 1
			if wave.combat_frozen:
				check(growth.choice_ui.is_open and wave.completed_waves == number - 1, "Wave clear waits for every real experience choice")
				if not growth.choice_ui.is_open: break
				if growth.choice_ui.select_option(&"P01"): picked += 1
				growth.choice_ui.confirm_selection()
			else:
				wave._physics_process(0.4)
				for enemy in wave.enemies: enemy.set_physics_process(false)
				check(wave.enemies.size() <= 24, "Endless spawning never exceeds production population cap")
				# 固定不动的测试怪不会离开出生区，及时击杀以免模拟出人为堵点。
				if wave._pending == 0 or wave.enemies.size() >= 8:
					for enemy in wave.enemies.duplicate():
						enemy.spawn_delay = 0.0
						enemy.take_damage(10000.0)
			await physics_frame
		killed += expected[index]
		if wave.phase != WavePrototype.Phase.REST:
			print("Unexpected wave state: ", JSON.stringify({"expected_wave":number, "steps":steps, "state":wave.get_run_state(), "health":player.current_health}))
		check(wave.phase == WavePrototype.Phase.REST and wave.completed_waves == number and wave.outcome == WavePrototype.Outcome.NONE, "Every clear enters rest without a final victory")
		check(wave._spawned_this_wave == expected[index] and wave.kills == killed, "No pending enemy is silently lost")
		check(wave.enemies.is_empty() and wave._pending == 0 and wave._attack_root == null, "Wave rest cleans up enemies, queue and hazards")
		check(wave.combat_modifiers.level_for(&"P01") == picked and picked > 0, "Real upgrades persist through every endless wave")
		wave._physics_process(100.0)
		check(wave.wave == number and wave.phase == WavePrototype.Phase.REST, "Rest has no countdown or automatic next wave")
		hud._refresh()
		check("无尽" in hud._title.text and not "/" in hud._title.text and "F" in hud._hint.text, "HUD shows endless progress and the next-wave key")
		if number == 4 and DisplayServer.get_name() != "headless":
			for frame in 8: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("D:/.codexfile/work/endless-waves-20261013/rest-wave4.png")
		if index < expected.size() - 1:
			key(KEY_F)
			for frame in 5: await physics_frame
			check(wave.phase == WavePrototype.Phase.BATTLE and wave.wave == number + 1, "Actual F input advances beyond the original final wave")
	check(clears == [1, 2, 3, 4, 5, 6, 7] and endings.is_empty(), "Each wave clears once and no automatic run end occurs")
	check(wave._run_waves.size() == 3, "Seven real waves retain only the three opening templates")
	# Restore editor configuration and verify retreat, retry, failure and invalid settings.
	wave.waves.assign(saved_templates)
	wave.endless_mode = true
	wave.endless_enemies_per_wave = 8
	wave.endless_max_enemies = 160
	wave.retreat()
	check(wave.phase == WavePrototype.Phase.RESULT and wave.outcome == WavePrototype.Outcome.RETREAT and wave.completed_waves == 7, "Endless challenge can be ended by retreat")
	wave.retry()
	check(wave.is_endless() and wave.wave == 1 and wave._pending == 18 and wave.kills == 0 and growth.state.level == 1 and wave.combat_modifiers.levels.is_empty(), "Retry starts a clean endless run at wave one")
	player.take_damage(player.max_health)
	wave._physics_process(0.01)
	check(wave.outcome == WavePrototype.Outcome.DEFEAT and wave.enemies.is_empty() and wave._pending == 0, "Defeat cancels endless spawns")
	wave.return_home()
	wave.endless_max_enemies = 30
	player.global_position = wave.global_position + Vector3.UP * 0.03
	check(not wave.start_run() and wave.outcome == WavePrototype.Outcome.ERROR, "Invalid count cap fails before entering a broken run")
	check(wave._pending == 0 and not wave.combat_frozen, "Invalid config leaves no queue or freeze")
	wave.return_home()
	wave.waves.clear()
	wave.endless_max_enemies = 160
	wave.total_waves = 0 # 无尽不依赖有限总波数。
	player.global_position = wave.global_position + Vector3.UP * 0.03
	check(wave.start_run() and wave._pending == 5, "Empty opening list builds one fallback endless template")
	check(total(wave._definition_for_wave(2)) == 13 and wave._run_waves.size() == 1, "Fallback opening uses the same endless growth and bounded template storage")
	wave.retreat()
	world.free()
	await create_timer(0.1).timeout
	print("Endless waves: %d checks, %d failures" % [checks, failures.size()])
	quit.call_deferred(0 if failures.is_empty() else 1)
