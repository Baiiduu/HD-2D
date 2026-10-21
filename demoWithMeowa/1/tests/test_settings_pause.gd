extends SceneTree
## Headless world/input/audio-state checks; listening and visuals remain manual.
class ClockProbe extends Node:
	var idle := 0
	var physics := 0
	func _process(_delta: float) -> void: idle += 1
	func _physics_process(_delta: float) -> void: physics += 1

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(40.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func frames(count := 4) -> void:
	for frame in count: await process_frame

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var world := load("res://scenes/world/world.tscn").instantiate() as Node3D
	world.get_node("WorldMainMenu").show_on_world_start = false
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("GameSettingsUI").save_graphics_settings = false
	world.get_node("MapEffects/GameAudio").load_local_mix = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	world.get_node("MapEffects/CoreFeedbackAudio").enabled = false
	var music: BackgroundMusic = world.get_node("MapEffects/BGM")
	music.music_enabled = true
	root.add_child(world)
	current_scene = world
	var clock := ClockProbe.new()
	world.add_child(clock)
	await frames(12)
	await create_timer(0.12).timeout
	var settings: GameSettingsUI = world.get_node("GameSettingsUI")
	var wave: WavePrototype = world.get_node("WavePrototype")
	var player: Player = world.get_node("Player")
	var body := player.body_ricochet
	var audio: GameAudio = world.get_node("MapEffects/GameAudio")
	var leaderboard := root.get_node("LeaderboardClient")
	var blocker := Node.new()
	world.add_child(blocker)
	blocker.add_to_group(&"gameplay_input_blockers")
	settings.open_menu()
	check(not settings.menu_open and not paused, "Rejected opening does not acquire a pause")
	blocker.free()
	var clip := AudioStreamWAV.new()
	clip.mix_rate = 8000
	clip.format = AudioStreamWAV.FORMAT_8_BITS
	var samples := PackedByteArray()
	samples.resize(16000)
	samples.fill(128)
	clip.data = samples
	var voice := audio.request({"source": player, "position": player.global_position, "cue": &"settings_pause_probe", "clips": [clip], "kind": GameAudio.Kind.ATTACK})
	check(voice != null, "Combat audio probe starts through the existing pool")
	settings.open_menu()
	settings.open_menu()
	check(paused and settings.menu_open and settings.can_process(), "Settings pauses the tree and remains interactive; duplicate opening is harmless")
	var original := Vector2i(clock.idle, clock.physics)
	var transform := player.global_transform
	var combat_clock := audio._clock
	var tracks: Array = music._players.map(func(track): return track.stream)
	await create_timer(0.18).timeout
	check(Vector2i(clock.idle, clock.physics) == original and player.global_transform == transform and not player.can_process() and not body.can_process(), "World, character and combat callbacks stop while settings is open")
	check(audio._clock == combat_clock and voice != null and voice.stream_paused, "Existing combat voices and their timing pause with gameplay")
	check(music.can_process() and music._players.all(func(track): return track.can_process() and not track.stream_paused) and music._players.any(func(track): return track.playing), "Existing BGM keeps playing and processing during pause")
	check(music._players.map(func(track): return track.stream) == tracks, "Opening settings does not restart or replace the music tracks")
	check(settings._ui_audio.play_action(&"confirm") and settings._ui_audio.can_process(), "UI feedback can play while the world is paused")
	check(leaderboard.can_process() and leaderboard._http.can_process(), "Settings leaderboard requests remain processable during pause")
	settings.select_page(6)
	check(paused and settings._character_page == null and settings._tabs[6] == null, "World attributes have an independent entry and no settings page")
	check(settings._selected != 6, "Selecting a removed page cannot leave settings on an empty page")
	settings.select_page(4)
	settings._controls_page.begin_capture(&"move_left", 0)
	key(KEY_ESCAPE)
	check(settings.menu_open and paused and not settings._controls_page.is_capturing(), "Esc cancels rebinding before closing the paused settings")
	var held: int = settings._controls.movement_mask()
	body._movement_keys = ~held & 255
	body._press_pending = true
	body._release_pending = true
	body._attack_pending = true
	body._aim_pending = true
	player._blink._buffer_remaining = 0.1
	key(KEY_ESCAPE)
	check(not paused and not settings.menu_open, "A second Esc closes settings and resumes the world")
	check(body._movement_keys == held and not body._press_pending and not body._release_pending and not body._attack_pending and not body._aim_pending and player._blink._buffer_remaining == 0.0, "Resume absorbs paused movement edges and discards queued combat/dash requests")
	await create_timer(0.12).timeout
	check(clock.idle > original.x and clock.physics > original.y and player.can_process(), "World process and physics resume after closing")
	check(voice != null and not voice.stream_paused, "Closing resumes the existing combat voice without replacing it")
	check(music._players.map(func(track): return track.stream) == tracks, "Closing settings preserves the current BGM tracks")
	paused = true
	settings.open_menu()
	settings.close_menu(false)
	check(paused, "Closing preserves a pause that existed before settings opened")
	paused = false
	wave.set_combat_frozen(true)
	settings.open_menu()
	settings.close_menu(false)
	check(not paused and wave.combat_frozen, "Menu pause restoration does not remove an independent combat freeze")
	wave.set_combat_frozen(false)
	settings.open_menu()
	settings._tabs[2].pressed.emit()
	check(paused and settings._selected == 2, "Mouse page navigation cannot release the pause")
	settings.close_menu(false)
	check(not paused, "Attributes closes through the same pause owner")
	settings.open_menu()
	world.remove_child(settings)
	check(not paused and get_first_node_in_group(&"gameplay_input_blockers") == null, "Removing an open settings component releases its own pause and input lock")
	settings.free()
	world.free()
	await frames()
	print("Settings pause: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
