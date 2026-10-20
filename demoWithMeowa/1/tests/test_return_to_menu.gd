extends SceneTree

const WORLD := "res://scenes/world/world.tscn"
const MENU := "res://scenes/ui/main_menu.tscn"
const REQUEST = preload("res://scripts/world/world_entry_request.gd")
var checks := 0
var failures: Array[String] = []
var world_instances := 0
var entry_plays := 0

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	# Isolate local preferences and sound before each real scene's children become ready.
	node_added.connect(_quiet_scene)
	run.call_deferred()

func _quiet_scene(node: Node) -> void:
	if node.scene_file_path == MENU:
		node.save_preferences = false
		node.audio_enabled = false
	elif node.scene_file_path == WORLD:
		world_instances += 1
		node.get_node("LoadoutUI").save_enabled = false
		node.get_node("GameSettingsUI").save_graphics_settings = false
		node.get_node("MapEffects/BGM").music_enabled = false
		node.get_node("MapEffects/Weather").rain_audio_enabled = false
		node.get_node("MapEffects/Weather").wind_audio_enabled = false
		node.get_node("MapEffects/CoreFeedbackAudio").enabled = false
		node.get_node("WorldMainMenu").prewarm_entry = true
		for audio in node.find_children("UIAudio", "", true, false): audio.enabled = false
	elif node.name == "TemporaryEntryLighting":
		entry_plays += 1

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func frames(count := 4) -> void:
	for index in count: await process_frame

func wait_for_scene(path: String) -> bool:
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
		if not current_scene or current_scene.scene_file_path != WORLD: continue
		var startup := current_scene.get_node_or_null("WorldMainMenu")
		if not startup: continue
		if (path == MENU and startup.game_ready and startup.menu != null) or (path == WORLD and startup.started):
			await frames(12)
			return true
	return false

func run() -> void:
	REQUEST.clear()
	# Keep the resource fixture alive while checking scene-instance ownership.
	# Uncached threaded loading is covered separately by test_main_menu.gd.
	var world_fixture: PackedScene = load(WORLD)
	var world: Node = world_fixture.instantiate()
	# Do not change the user's direct-run preview flag in the saved map.
	world.get_node("WorldEntry").preview_on_direct_run = false
	root.add_child(world)
	current_scene = world
	await frames(12)
	var settings = world.get_node("GameSettingsUI")
	check(settings.has_method("return_to_main_menu"), "Gameplay settings expose a return-to-main-menu action")
	if not settings.has_method("return_to_main_menu"):
		world.free()
		finish()
		return
	for cycle in 4:
		settings = world.get_node("GameSettingsUI")
		settings.return_to_main_menu()
		await frames()
		check(current_scene == world, "Hidden settings cannot accidentally leave the run")
		if cycle > 0:
			var battle := world.get_node("WavePrototype") as WavePrototype
			battle.skill_draft.enabled = false
			battle.player.global_position = battle.global_position + Vector3.UP * 0.03
			check(battle.start_run(), "The return fixture starts a real battle with pending spawns")
			await frames(6)
			check(battle.phase == WavePrototype.Phase.BATTLE and battle._pending + battle.enemies.size() > 0, "Battle work exists before leaving the map")
			var growth := battle.get_node("RunGrowth") as RunGrowth
			growth.state.add_experience(3)
			var score := battle.get_node("RunScore") as RunScore
			score.state.record_kill(1234, 10, false)
			var available := battle.run_skill_manager.get_registered_ids().filter(battle.run_skill_manager.is_skill_available)
			check(not available.is_empty() and battle.run_skill_manager.set_skill_level(available[0], 1), "The returning run has a learned skill")
			check(battle.combat_modifiers.apply_buff(battle.get_node("RunBuffs").definitions[0]), "The returning run has shared growth")
			if cycle == 2:
				battle._spawn_state.clear()
				for enemy in battle.enemies.duplicate(): enemy.cancel()
				await frames()
				battle._clear_wave()
				check(battle.phase == WavePrototype.Phase.REST, "Return also exercises the safe rest phase")
			elif cycle == 3:
				battle.retreat()
				check(battle.phase == WavePrototype.Phase.RESULT, "Return also exercises the result input blocker")
		settings.open_menu()
		check(settings.menu_open and not paused and Engine.time_scale == 1.0, "Settings keeps the world running until return is selected")
		var buttons: Array = settings.find_children("*", "Button", true, false).filter(func(button): return button.text == "返回主菜单")
		check(buttons.size() == 1, "Settings contains one visible return-to-main-menu button")
		if buttons.is_empty(): break
		var old_world: WeakRef = weakref(world)
		var old_audio: WeakRef = weakref(world.get_node("MapEffects/GameAudio"))
		var old_entry: WeakRef = weakref(world.get_node("WorldEntry"))
		var old_navigation: int = world.get_node("WavePrototype")._path.get_instance_id()
		var previous_entry_plays := entry_plays
		var returned_at := Time.get_ticks_msec()
		REQUEST.request() # A stale request must not leak into the next menu visit.
		buttons[0].pressed.emit()
		buttons[0].pressed.emit()
		check(buttons[0].disabled and current_scene == world, "Return locks repeat clicks and defers work outside the button callback")
		check(await wait_for_scene(MENU), "Return presents the embedded main menu")
		print("RETURN_READY_MS: ", Time.get_ticks_msec() - returned_at)
		if not current_scene or current_scene.scene_file_path != WORLD: break
		check(current_scene == old_world.get_ref() and current_scene.get_node("MapEffects/GameAudio") == old_audio.get_ref() and current_scene.get_node("WorldEntry") == old_entry.get_ref(), "Return keeps the already-loaded map, audio owner and entry controller")
		check(world_instances == 1 and current_scene.get_node("WavePrototype")._path.get_instance_id() == old_navigation, "Return does not instantiate another World or rebuild navigation")
		check(entry_plays == previous_entry_plays, "Return does not replay entry warmup behind the menu")
		var startup = current_scene.get_node("WorldMainMenu")
		check(get_nodes_in_group(&"gameplay_input_blockers") == [startup] and not REQUEST.consume(), "Prepared menu owns input without inheriting old blockers or an intro request")
		var menu = startup.menu
		check(not menu.flow.busy and not menu.buttons[0].disabled, "Returned menu is ready to start again")
		var prepared: WavePrototype = current_scene.get_node("WavePrototype")
		check(prepared.phase == WavePrototype.Phase.READY and prepared._pending == 0 and prepared.enemies.is_empty() and not prepared.combat_frozen, "Returning clears live enemies, pending spawns and combat freeze")
		check(prepared.wave == 0 and prepared.kills == 0 and prepared.completed_waves == 0 and prepared.combat_modifiers.levels.is_empty(), "Returned game clears wave counters and shared growth")
		check(not prepared.run_skill_manager.has_learned_skill() and prepared.get_node("RunGrowth").state.total_experience == 0 and prepared.get_node("RunScore").state.total == 0, "Returned game clears learned skills, experience and score")
		check(is_instance_valid(settings) and not settings.menu_open and not settings._returning_to_menu, "Gameplay settings release return state for the next visit")
		check(Vector2(prepared.player.velocity.x, prepared.player.velocity.z).is_zero_approx() and prepared.player.current_health == prepared.player.max_health and not prepared.player.body_ricochet.flying, "Returning resets player health, momentum and active movement")
		menu.start_feedback_seconds = 0.3
		menu.start_game()
		menu.start_game()
		check(await wait_for_scene(WORLD), "Start returns to the real formal map")
		if not current_scene or current_scene.scene_file_path != WORLD: break
		world = current_scene
		var entry = world.get_node("WorldEntry")
		var wave := world.get_node("WavePrototype") as WavePrototype
		check(entry.active and not REQUEST.consume(), "Each new visit plays and consumes a fresh intro request")
		check(wave.phase == WavePrototype.Phase.READY and wave.enemies.is_empty() and not wave.combat_frozen, "New map starts prepared, without leftover enemies or combat freeze")
		entry.skip()
		await frames()
		check(not entry.active and get_nodes_in_group(&"gameplay_input_blockers").is_empty(), "Finishing the replay restores control for another return")
	if current_scene:
		current_scene.free()
	await frames()
	await create_timer(0.2).timeout
	REQUEST.clear()
	finish()

func finish() -> void:
	print("RETURN_TO_MENU: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
