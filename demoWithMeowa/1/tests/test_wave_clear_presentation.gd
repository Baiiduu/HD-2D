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
	var presentation: WavePresentation = world.get_node("WavePresentation")
	if not "compact_clear_enabled" in presentation.settings:
		check(false, "Compact clear presentation needs a map-owned style setting")
		world.free()
		finish()
		return
	check(presentation.settings.get("compact_clear_enabled") == true and WavePresentationSettings.new().get("compact_clear_enabled") == false, "Only World explicitly enables the new clear style")
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("GameSettingsUI").save_graphics_settings = false
	world.get_node("MapEffects/BGM").music_enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	world.get_node("MapEffects/CoreFeedbackAudio").enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(world)
	for frame in 12: await physics_frame
	var wave: WavePrototype = world.get_node("WavePrototype")
	var hud: WaveHUD = wave.get_node("WaveHUD")
	var score: RunScore = wave.get_node("RunScore")
	var score_hud: ScoreHUD = wave.get_node("ScoreHUD")
	wave.player.set_physics_process(false)
	wave.set_physics_process(false)
	wave.player.global_position = wave.global_position + Vector3.UP * 0.03
	check(wave.start_run(), "Start a real endless run")
	var choice := wave.skill_draft.initial_choice
	choice.reveal_now()
	choice.select_option(choice._options[0].id)
	choice.confirm_selection()
	presentation.set_process(false)
	presentation.advance(5.0)
	wave.interact_key = KEY_G
	wave._spawn_state.clear()
	wave.set_combat_frozen(true)
	wave._clear_wave()
	hud._refresh()
	check(wave.phase == WavePrototype.Phase.BATTLE and presentation.current_cue == presentation.Cue.NONE, "Clear confirmation still waits for upgrade selection")
	wave.set_combat_frozen(false)
	wave._clear_wave()
	presentation.set_process(false)
	hud._refresh()
	check(wave.phase == WavePrototype.Phase.REST and presentation.current_cue == presentation.Cue.CLEAR, "Actual safe rest starts the new confirmation")
	var hint: Control = hud.get("_rest_hint")
	check(hint != null and hint.visible and not hud._root.visible, "Rest has one continuation hint while the old upper heading stays hidden")
	check(String(hud.get("_rest_key").text) == "G" and String(hud.get("_rest_next").text).contains("02"), "Hint uses the real interaction key and real next wave")
	var frozen_age := presentation.age
	wave.set_combat_frozen(true)
	presentation.advance(1.0)
	hud._refresh()
	check(is_equal_approx(presentation.age, frozen_age) and not hint.visible, "Upgrade freeze hides both clear elements without consuming the confirmation")
	wave.set_combat_frozen(false)
	score_hud._commit()
	check(score.state.wave_score > 0 and score_hud._gain.text.begins_with("+") and score_hud._hint.text.is_empty(), "Clear awards keep their numeric feedback without a duplicate wave sentence")
	presentation.advance(5.0)
	hud._refresh()
	check(not presentation.is_processing() and presentation.current_cue == presentation.Cue.NONE and hint.visible, "The transient title ends but the continuation hint remains")
	check(hud._title.text.is_empty() and hud._hint.text.is_empty(), "Persistent upper text does not repeat completed-wave information")
	var blocker := Node.new()
	root.add_child(blocker)
	blocker.add_to_group(&"gameplay_input_blockers")
	hud._refresh()
	check(not hint.visible and wave.phase == WavePrototype.Phase.REST and not paused, "Settings hide the continuation hint without leaving safe rest")
	blocker.free()
	hud._refresh()
	check(hint.visible, "Closing settings restores the continuation hint")
	check(wave.start_next_wave(), "Continue without any additional presentation wait")
	presentation.set_process(false)
	hud._refresh()
	check(not hint.visible and presentation.current_cue == presentation.Cue.NEXT_WAVE and presentation.displayed_wave == 2, "The next real opening immediately replaces rest information")
	presentation.advance(5.0)
	wave._spawn_state.clear()
	wave._clear_wave()
	presentation.set_process(false)
	check(presentation.current_cue == presentation.Cue.CLEAR and wave.start_next_wave(), "The player can also continue during an unfinished clear title")
	presentation.set_process(false)
	hud._refresh()
	check(not hint.visible and presentation.current_cue == presentation.Cue.NEXT_WAVE, "Fast continuation leaves no stale clear or rest state")
	presentation.advance(5.0)
	wave._spawn_state.clear()
	wave._clear_wave()
	presentation.set_process(false)
	presentation.advance(5.0)
	presentation.settings.set("compact_clear_enabled", false)
	hud._refresh()
	check(not hint.visible and hud._root.visible and not hud._hint.text.is_empty(), "Turning off the new style preserves the original continuation instructions")
	presentation.settings.set("compact_clear_enabled", true)
	presentation.free()
	hud._refresh()
	check(not hint.visible and hud._root.visible, "Removing presentation releases its shared HUD styling")
	wave.retreat()
	world.free()
	for frame in 3: await process_frame
	finish()

func finish() -> void:
	print(JSON.stringify({"suite":"wave_clear_presentation", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
