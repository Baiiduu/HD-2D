extends SceneTree

const FIXTURE := preload("res://tests/fixtures/combat_scene_fixture.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(55.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	# 隔离用户开启的人工演出；此用例只检查界面与即时计分，演出另有独立覆盖。
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("WavePresentation").enabled = false
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("GameSettingsUI").save_graphics_settings = false
	world.get_node("MapEffects/BGM").music_enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	world.get_node("MapEffects/CoreFeedbackAudio").enabled = false
	for ui_audio in world.find_children("*", "UIAudio", true, false): ui_audio.enabled = false
	var profile := FIXTURE.isolate_profile(world)
	profile.population_rules = null
	profile.waves = []
	profile.endless_mode = false
	FIXTURE.enable_legacy_skills(world)
	var wave: WavePrototype = world.get_node("WavePrototype")
	wave.population_rules = null
	wave.waves.clear()
	wave.total_waves = 1
	wave.endless_mode = false
	wave.first_wave_enemies = 5
	wave.spawn_interval = 0.1
	root.add_child(world)
	current_scene = world
	for frame in 8: await process_frame
	var settings: GameSettingsUI = world.get_node("GameSettingsUI")
	var audio: AudioMixUI = world.get_node("AudioMixUI")
	var orbit = world.get_node("OrbitDebugUI")
	check(not settings._fps_label.visible and settings._fps_timer.is_stopped(), "Live FPS defaults off without periodic updates")
	check(settings._fps_label.get_theme_color("font_color") == Color.BLACK and settings._fps_label.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Live FPS uses black text and never intercepts gameplay clicks")
	check(not audio._launcher.visible and not orbit._launcher.visible and not orbit._details_button.visible, "Only the unified settings launcher remains")
	settings.open_menu()
	settings._fps_toggle.button_pressed = true
	check(settings._fps_label.visible and not settings._fps_timer.is_stopped() and settings._fps_label.text == "FPS: %d" % Engine.get_frames_per_second(), "Settings checkbox enables the engine FPS display immediately")
	for frame in 4: await process_frame
	check(settings.get_viewport().get_visible_rect().encloses(settings._panel.get_global_rect()), "Settings panel fits the current viewport")
	check(settings.menu_open and audio.menu_open and get_first_node_in_group(&"gameplay_input_blockers") == settings, "Settings owns player input and opens the embedded audio page")
	check(paused and not wave.combat_frozen, "Settings pauses the world independently of upgrade combat freeze")
	settings.select_page(2)
	check(settings._graphics_page.visible and not audio.menu_open and not orbit._panel.visible, "Graphics page shares the unified settings without keeping audio or diagnostics open")
	settings.select_page(0)
	audio.play_selected()
	check(audio._preview.playing, "Embedded audio page retains audition playback")
	settings.select_page(1)
	for frame in 4: await process_frame
	check(settings.get_viewport().get_visible_rect().encloses(settings._panel.get_global_rect()), "Diagnostic page stays inside the same settings frame")
	check(not audio._preview.playing and not audio.menu_open and orbit._panel.visible, "Changing page stops audition and exposes diagnostics")
	settings._orbit_host.get_child(0).button_pressed = true
	check(orbit.debug_enabled and orbit.player.body_ricochet.orbit_debug_enabled and not orbit._details_button.visible, "Embedded diagnostic controls keep the real debug implementation without another launcher")
	settings.close_menu()
	check(settings._fps_label.is_visible_in_tree() and not settings._fps_timer.is_stopped(), "FPS stays visible and refreshing after settings closes")
	check(not settings.menu_open and orbit.debug_enabled and not orbit._panel.visible and get_first_node_in_group(&"gameplay_input_blockers") == null, "Closing settings releases input and allows observing enabled world diagnostics")
	orbit.set_debug_enabled(false)
	var skills := wave.run_skill_manager
	var draft := wave.skill_draft
	draft.initial_cards_per_draw = 100
	check(wave.start_run(), "Real combat can start after closing settings")
	if draft.initial_choice.is_open:
		draft.initial_choice.reveal_now()
		check(draft.initial_choice.select_option(&"initial:fan_slash"), "Initial skill remains selectable")
		draft.initial_choice.confirm_selection()
	for component: Node in skills._components.values(): component.process_mode = Node.PROCESS_MODE_DISABLED
	var growth := wave.get_node("RunGrowth")
	growth.process_mode = Node.PROCESS_MODE_DISABLED
	# No level-up during this lifecycle check; death, wave and score use real objects.
	for enemy in wave.enemies: enemy.experience_reward = 0
	wave.player.set_physics_process(false)
	wave.set_physics_process(false)
	settings.open_menu()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await process_frame
	check(not settings.menu_open and wave.phase == WavePrototype.Phase.BATTLE, "ESC closes settings without retreating from combat")
	for step in 80:
		wave._physics_process(0.1)
		for enemy in wave.enemies:
			enemy.set_physics_process(false)
			enemy.experience_reward = 0
		if wave.enemies.size() == 5: break
		await physics_frame
	for enemy in wave.enemies:
		enemy.set_physics_process(false)
		enemy.experience_reward = 0
	var score: RunScore = wave.get_node("RunScore")
	check(score.state.active and not score.state.simulation, "Real run enables scoring")
	var expected := 0
	var body: PlayerRicochet = wave.player.body_ricochet
	body.flight_serial += 1
	body.launched.emit(Vector3.RIGHT, 10.0, 1.0)
	var count := wave.enemies.size()
	check(count == 5, "Controlled wave spawns the complete planned population")
	var batch = score.begin_attack()
	for enemy in wave.enemies.duplicate():
		expected += score.state.rules.points_for(enemy.definition)
		enemy.take_damage(10000.0, {"source": &"flight_sword", "flight_id": body.flight_serial, "score_batch": batch})
	check(score.state.kills == count and score.state.kill_score == expected, "Only real lethal damage pays the registered enemy points")
	check(score.state.burst_score == 25 and score.state.combo_score == 0, "One attack earns its fixed burst tier once with a shared multiplier")
	wave.player.take_damage(1.0)
	check(score.state.combo_kills == count, "Player damage does not lower the kill streak")
	wave._clear_wave()
	check(wave.outcome == WavePrototype.Outcome.VICTORY and not score.state.active, "Final wave completes through the existing lifecycle")
	check(score.state.total == expected + 25 + 100 and score.state.wave_score == 100, "Last kills, fixed burst and final wave are present exactly once")
	var hud: ScoreHUD = wave.get_node("ScoreHUD")
	for frame in 30: await process_frame
	hud._process(1.0)
	check(hud._display == score.state.total and hud._pending == 0, "HUD converges to the real score and flushes final pending points")
	check(hud._root.visible, "Final score remains visible when the result state blocks character input")
	check(not hud._hint.text.contains("连杀") and not hud._hint.text.contains("一片倒下"), "New score bonuses do not add combat labels to the HUD")
	settings.open_menu()
	check(settings.menu_open, "Settings can also open from the result screen")
	var original_size := root.size
	var original_scale := root.content_scale_size
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(640, 480)
	settings.select_page(2)
	for frame in 6: await process_frame
	check(settings.get_viewport().get_visible_rect().encloses(settings._panel.get_global_rect()), "Unified settings stays inside a small viewport with scrolling")
	check(settings.get_viewport().get_visible_rect().encloses(settings._fps_label.get_global_rect()), "FPS stays inside the viewport after resizing")
	settings._fps_toggle.button_pressed = false
	check(not settings._fps_label.visible and settings._fps_timer.is_stopped(), "Disabling FPS hides the display and stops periodic work")
	settings.close_menu()
	root.size = original_size
	root.content_scale_size = original_scale
	world.queue_free()
	for frame in 3: await process_frame
	await create_timer(0.1).timeout
	print("SCORE_SETTINGS_TEST ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
