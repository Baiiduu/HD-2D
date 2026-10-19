extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		push_error(label)

func run() -> void:
	var world: Node = load("res://scenes/world/world.tscn").instantiate()
	var presentation = world.get_node_or_null("WavePresentation")
	check(presentation != null, "World has independent endless-wave presentation")
	if not presentation:
		world.free()
		finish()
		return
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("GameSettingsUI").save_graphics_settings = false
	world.get_node("MapEffects/BGM").music_enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	world.get_node("MapEffects/CoreFeedbackAudio").enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(world)
	for index in 12: await physics_frame
	var wave: WavePrototype = world.get_node("WavePrototype")
	var hud: CanvasLayer = wave.get_node("WaveHUD")
	wave.player.set_physics_process(false)
	wave.set_physics_process(false)
	wave.player.global_position = wave.global_position + Vector3.UP * 0.03
	check(presentation.session == wave and presentation.wave_hud == hud, "Presentation listens to the actual World wave state and HUD")
	check(presentation.settings.animated_opening_enabled and not WavePresentationSettings.new().animated_opening_enabled, "World explicitly enables B opening while shared presentation defaults stay unchanged")
	check(not presentation.is_processing() and presentation.current_cue == presentation.Cue.NONE, "Idle presentation does no frame work")
	check(wave.start_run() and wave.phase == WavePrototype.Phase.READY, "Initial skill selection precedes the actual battle")
	check(presentation.current_cue == presentation.Cue.NONE, "Opening cards do not announce a wave that has not started")
	var choice := wave.skill_draft.initial_choice
	choice.reveal_now()
	choice.select_option(choice._options[0].id)
	choice.confirm_selection()
	presentation.set_process(false)
	check(wave.phase == WavePrototype.Phase.BATTLE and presentation.current_cue == presentation.Cue.OPENING, "First actual endless battle plays the opening cue")
	check(presentation.displayed_wave == 1 and hud.presentation_active and hud.visible, "Opening replaces the duplicate heading without changing menu-owned CanvasLayer visibility")
	var pending := wave._pending
	var generation := wave.get_combat_generation()
	presentation.advance(0.35)
	check(not paused and Engine.time_scale == 1.0 and not wave.combat_frozen and wave._pending == pending and wave.get_combat_generation() == generation, "Visual progression never pauses, delays spawning or changes the combat generation")
	check(get_first_node_in_group(&"gameplay_input_blockers") == null, "Wave titles do not capture gameplay input")
	var age: float = presentation.age
	wave.phase_changed.emit(wave.phase)
	check(is_equal_approx(presentation.age, age), "Repeated battle notifications do not replay the same opening")
	presentation.advance(5.0)
	check(presentation.current_cue == presentation.Cue.NONE and not presentation.is_processing() and not hud.presentation_active, "Opening completes and restores the wave HUD without idle processing")
	wave._spawn_state.clear()
	wave.set_combat_frozen(true)
	wave._clear_wave()
	check(wave.phase == WavePrototype.Phase.BATTLE and presentation.current_cue == presentation.Cue.NONE, "Last-kill upgrades finish before the real wave-clear celebration")
	wave.set_combat_frozen(false)
	wave._clear_wave()
	presentation.set_process(false)
	check(wave.phase == WavePrototype.Phase.REST and presentation.current_cue == presentation.Cue.CLEAR and presentation.displayed_wave == 1, "Real wave completion plays a clear cue during safe rest")
	check(presentation.subtitle_text.contains("2") and presentation.subtitle_text.contains(OS.get_keycode_string(wave.interact_key)), "Clear feedback names the real next wave and configured continue key")
	presentation.advance(0.4)
	age = presentation.age
	wave.wave_cleared.emit(1)
	check(is_equal_approx(presentation.age, age), "Duplicate clear events do not replay a celebration")
	check(wave.start_next_wave(), "The player can continue while the clear cue is playing")
	presentation.set_process(false)
	check(presentation.current_cue == presentation.Cue.NEXT_WAVE and presentation.displayed_wave == 2, "A new wave replaces stale clear feedback immediately")
	check(presentation.cue_duration < presentation.settings.opening_seconds, "Later wave starts are shorter than the first opening")
	presentation.advance(0.2)
	age = presentation.age
	wave.set_combat_frozen(true)
	presentation.advance(2.0)
	check(is_equal_approx(presentation.age, age) and not presentation.content_visible, "Upgrade choice suspends and hides the presentation without advancing it")
	wave.set_combat_frozen(false)
	presentation.advance(0.1)
	check(presentation.age > age and presentation.content_visible, "Presentation resumes after upgrade choice")
	var blocker := Node.new()
	root.add_child(blocker)
	blocker.add_to_group(&"gameplay_input_blockers")
	age = presentation.age
	presentation.advance(1.0)
	check(is_equal_approx(presentation.age, age) and not presentation.content_visible, "Management menus remain unobstructed and do not consume the feedback")
	blocker.free()
	presentation.advance(0.1)
	check(presentation.content_visible, "Closing a management menu resumes the cue")
	presentation.enabled = false
	check(presentation.current_cue == presentation.Cue.NONE and not hud.presentation_active and not presentation.is_processing(), "Disabling presentation releases its HUD ownership immediately")
	presentation.enabled = true
	check(presentation.current_cue == presentation.Cue.NONE, "Enabling mid-wave does not fabricate another wave start")
	wave._spawn_state.clear()
	wave._clear_wave()
	presentation.set_process(false)
	check(presentation.current_cue == presentation.Cue.CLEAR and presentation.displayed_wave == 2, "Subsequent real clears have independent feedback")
	wave.retreat()
	check(presentation.current_cue == presentation.Cue.NONE and not hud.presentation_active, "Run end cancels wave feedback without adding an out-of-scope results animation")
	wave.reset_for_menu()
	check(not presentation.is_processing() and presentation.current_cue == presentation.Cue.NONE, "Returning to the menu leaves no active wave effects")
	check(wave.start_run(), "A reset run can request its first wave again")
	choice.reveal_now()
	choice.select_option(choice._options[0].id)
	choice.confirm_selection()
	presentation.set_process(false)
	check(presentation.current_cue == presentation.Cue.OPENING and presentation.displayed_wave == 1, "A fresh run gets its own opening rather than stale deduplication")
	wave._run_endless = false
	wave.phase_changed.emit(wave.phase)
	check(presentation.current_cue == presentation.Cue.NONE, "Finite challenge modes keep their existing presentation")
	wave._run_endless = true
	var simulation := WavePopulationRules.new()
	simulation.simulation_mode = true
	wave._run_population = simulation
	wave.wave = 3
	wave.phase_changed.emit(wave.phase)
	check(presentation.current_cue == presentation.Cue.NONE and not presentation.is_processing(), "Horde simulations do not add presentation work")
	wave.reset_for_menu()
	var pulse: MeshInstance3D = presentation.pulse
	presentation.free()
	for index in 3: await process_frame
	check(not is_instance_valid(pulse), "Removing the presenter disposes its reusable world pulse")
	world.free()
	for index in 3: await process_frame
	await create_timer(0.35, true, false, true).timeout
	finish()

func finish() -> void:
	print(JSON.stringify({"suite":"wave_presentation", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
