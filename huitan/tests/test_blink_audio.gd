extends SceneTree

func _initialize() -> void:
	create_timer(15.0).timeout.connect(func(): quit(2))
	_run.call_deferred()

func frames(count: int) -> void:
	for frame in count:
		await physics_frame
	await process_frame

func box(parent: Node3D, point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = point
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body

func press_blink() -> void:
	Input.action_press(&"blink")
	await frames(1)
	Input.action_release(&"blink")

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	box(world, Vector3(0, -0.1, 0), Vector3(20, 0.2, 20))
	var player := Player.new()
	player.bounds = Rect2(-9, -9, 18, 18)
	player.animations = load("res://assets/meowa/player/animations.tres")
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.height = 1.066
	shape.radius = 0.24
	collision.shape = shape
	collision.position.y = shape.height * 0.5
	player.add_child(collision)
	var audio: PlayerMovementAudio = load("res://scenes/audio/player_movement_audio.tscn").instantiate()
	player.add_child(audio)
	world.add_child(player)
	await frames(35)
	assert(audio.blink_sound is AudioStreamWAV)
	assert(audio.blink_sound.get_length() > 0.05 and audio.blink_sound.get_length() <= 0.6)
	assert((audio.blink_sound as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED)
	assert(audio._voice_cursor == 0, "Spawn must be silent")
	await press_blink()
	assert(audio._voice_cursor == 0, "Anticipation must be silent")
	await frames(5)
	assert(audio._voice_cursor == 1, "Actual teleport starts exactly one sound")
	assert(audio._voices[0].stream == audio.blink_sound)
	assert(is_equal_approx(audio._voices[0].volume_db, audio.volume_db + audio.blink_volume_db))
	assert(is_equal_approx(audio._voices[0].pitch_scale, audio.blink_pitch))
	assert(audio._voices[0].bus == audio.audio_bus)
	await frames(35)
	assert(audio._voice_cursor == 1, "Recovery must not repeat sound")
	var wall := box(world, player.position + Vector3(0.27, 1, 0), Vector3(0.05, 2, 4))
	await frames(2)
	await press_blink()
	await frames(35)
	assert(audio._voice_cursor == 1, "Fully blocked blink must be silent")
	wall.free()
	var blocker := Node.new()
	blocker.add_to_group(&"gameplay_input_blockers")
	world.add_child(blocker)
	await press_blink()
	await frames(35)
	assert(audio._voice_cursor == 1, "UI-blocked blink must be silent")
	blocker.free()
	await press_blink()
	world.add_to_group(&"gameplay_input_blockers")
	await frames(35)
	assert(audio._voice_cursor == 1, "Cancelled anticipation must be silent")
	world.remove_from_group(&"gameplay_input_blockers")
	audio.blink_sound_enabled = false
	await press_blink()
	await frames(35)
	assert(audio._voice_cursor == 1, "Blink-specific sound toggle works")
	audio.blink_sound_enabled = true
	audio.enabled = false
	await press_blink()
	await frames(35)
	assert(audio._voice_cursor == 1, "Movement sound master toggle works")
	world.free()
	print("PASS: blink sound resource, exact teleport timing, single trigger, gain/pitch/bus, collision/UI cancellation and both toggles")
	quit()
