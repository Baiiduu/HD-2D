extends SceneTree

const WORK := "D:/.codexfile/work/audio-preferences-20261020"
const MIX_PATH := WORK + "/restart.cfg"
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL: ", message)

func verify_mix(mix: AudioMixSettings, expected: Array, message: String) -> void:
	for index in AudioMixSettings.BUSES.size():
		var bus: StringName = AudioMixSettings.BUSES[index]
		check(is_equal_approx(mix.bus_volume_percent(bus), expected[index]), message + ": " + String(bus))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(WORK)
	AudioServer.set_bus_mute(0, true)
	var expected := [35.0, 62.0, 0.0, 44.0, 75.0]
	var saved := AudioMixSettings.new()
	for index in AudioMixSettings.BUSES.size():
		saved.set_bus_volume_percent(AudioMixSettings.BUSES[index], expected[index])
	var clip_path := "res://assets/meowa/audio/combat/hit_01.wav"
	saved.set_clip_gain(clip_path, -7.0)
	check(saved.save_to_path(MIX_PATH) == OK, "Fixture saves only into task scratch")
	var world := Node3D.new()
	root.add_child(world)
	var audio := GameAudio.new()
	audio.mix_save_path = MIX_PATH
	world.add_child(audio)
	verify_mix(audio.mix, expected, "Startup restores the existing local mix")
	var feedback: CoreFeedbackAudio = load("res://scenes/audio/core_feedback_audio.tscn").instantiate()
	feedback.enabled = false
	feedback.sounds = load("res://data/audio/core_sound_bank.tres")
	world.add_child(feedback)
	var panel := AudioMixUI.new()
	panel.audio = audio
	panel.feedback = feedback
	world.add_child(panel)
	var host := VBoxContainer.new()
	world.add_child(host)
	panel.embed_in(host, Theme.new())
	panel.set_embedded_visible(true)
	await process_frame
	for index in AudioMixSettings.BUSES.size():
		check(is_equal_approx(panel._bus_sliders[index].value, expected[index]), "The game settings page displays the restored group volume")
	# F8 can stop the process without another frame, timer timeout, or exit callback.
	# Check the file synchronously after the real embedded slider's change signal.
	var chosen := [0.0, 27.0, 83.0, 0.0, 100.0]
	for index in AudioMixSettings.BUSES.size():
		panel._bus_sliders[index].value = chosen[index]
		expected[index] = chosen[index]
		var on_disk := AudioMixSettings.new()
		check(on_disk.load_from_path(MIX_PATH) == OK, "Slider adjustment leaves a readable mix file")
		verify_mix(on_disk, expected, "A stop immediately after slider adjustment preserves every group")
		check(is_equal_approx(float(on_disk.clip_gains.get(clip_path, 0.0)), -7.0), "Saving groups preserves the existing per-clip mix")
	check(not panel._dirty and panel._save_timer.is_stopped(), "Group volume persistence does not wait for shutdown or a scaled timer")
	var time_scale := Engine.time_scale
	Engine.time_scale = 0.01
	audio.mix.set_clip_gain(clip_path, -5.0)
	await create_timer(0.55, true, false, true).timeout
	Engine.time_scale = time_scale
	var detailed := AudioMixSettings.new()
	check(detailed.load_from_path(MIX_PATH) == OK and is_equal_approx(float(detailed.clip_gains.get(clip_path, 0.0)), -5.0), "Detailed-mix autosave persists after real elapsed time even during slow motion")
	# A new audio manager follows exactly the same load path as the next F5 run.
	world.free()
	var restarted := GameAudio.new()
	restarted.mix_save_path = MIX_PATH
	root.add_child(restarted)
	verify_mix(restarted.mix, expected, "Restart restores the last chosen group volumes")
	for index in AudioMixSettings.BUSES.size():
		var bus: StringName = AudioMixSettings.BUSES[index]
		var bus_index := AudioServer.get_bus_index(bus)
		check(AudioServer.is_bus_mute(bus_index) == (expected[index] == 0.0), "Restart applies actual bus mute state: " + String(bus))
		if expected[index] > 0.0:
			check(is_equal_approx(AudioServer.get_bus_volume_db(bus_index), linear_to_db(expected[index] / 50.0)), "Restart applies actual bus gain: " + String(bus))
	restarted.free()
	print("Audio preferences: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
