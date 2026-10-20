extends SceneTree

var _jump_count := 0
var _land_count := 0

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	_run.call_deferred()

func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func _wait_frames(count: int) -> void:
	for index in count:
		await physics_frame
	await process_frame

func _floor(parent: Node3D, position: Vector3, size: Vector3, surface: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	body.set_meta("movement_surface", surface)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	return body

func _run() -> void:
	var bank: MovementSoundBank = load("res://data/audio/movement_sounds.tres")
	for surface in GroundAudioSampler.SURFACE_COUNT:
		assert(not bank.clips(surface).is_empty())
		for clip in bank.clips(surface):
			assert(clip.get_length() >= 0.1 and clip.get_length() <= 0.6)
			assert(clip is AudioStreamWAV and clip.loop_mode == AudioStreamWAV.LOOP_DISABLED)
	assert(bank.jump.size() == 2)
	_test_terrain_sampler()
	var world := Node3D.new()
	root.add_child(world)
	_floor(world, Vector3(-10, -0.1, 0), Vector3(20, 0.2, 20), GroundAudioSampler.Surface.GRASS)
	var cobble_floor := _floor(world, Vector3(10, -0.1, 0), Vector3(20, 0.2, 20), GroundAudioSampler.Surface.COBBLE)
	var player := Player.new()
	player.animations = load("res://assets/meowa/player/animations.tres")
	player.position = Vector3(-2, 0.25, 0)
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.24
	shape.height = 1.066
	collision.position.y = shape.height * 0.5
	collision.shape = shape
	player.add_child(collision)
	var audio: PlayerMovementAudio = load("res://scenes/audio/player_movement_audio.tscn").instantiate()
	player.add_child(audio)
	player.jumped.connect(func(): _jump_count += 1)
	player.landed.connect(func(_speed: float): _land_count += 1)
	world.add_child(player)
	await _wait_frames(60)
	assert(player.is_on_floor() and audio._initialized)
	assert(audio._voice_cursor == 0 and _land_count == 0, "Spawn settling must be silent")
	assert(audio._mix[GroundAudioSampler.Surface.GRASS] > 0.99)
	_key(KEY_D, true)
	var max_change := 0.0
	var previous := audio._mix[GroundAudioSampler.Surface.COBBLE]
	for frame in 90:
		await _wait_frames(1)
		var current := audio._mix[GroundAudioSampler.Surface.COBBLE]
		max_change = maxf(max_change, absf(current - previous))
		previous = current
	_key(KEY_D, false)
	assert(player.position.x > 3.5, "Physical input must move the actual Player")
	assert(max_change < 0.11, "Crossing a hard collision boundary must still ease audio")
	assert(audio._mix[GroundAudioSampler.Surface.COBBLE] > 0.99)
	assert(audio._last_clip.has(GroundAudioSampler.Surface.GRASS) and audio._last_clip.has(GroundAudioSampler.Surface.COBBLE))
	await _wait_frames(30)
	var idle_cursor := audio._voice_cursor
	await _wait_frames(30)
	assert(audio._voice_cursor == idle_cursor, "Idle must not emit steps")
	var floor_shape := cobble_floor.get_child(0) as CollisionShape3D
	floor_shape.set_meta("movement_surface", GroundAudioSampler.Surface.WOOD)
	await _wait_frames(45)
	assert(audio._mix[GroundAudioSampler.Surface.WOOD] > 0.98, "A shape-specific floor tag must override the body's tag")
	floor_shape.set_meta(&"collision_surface", &"metal")
	assert(audio._ground_weights()[GroundAudioSampler.Surface.METAL] > 0.99, "New shape material takes priority over legacy tags in real ground queries")
	floor_shape.set_meta(&"collision_surface", &"wood")
	assert(audio._ground_weights()[GroundAudioSampler.Surface.WOOD] > 0.99, "New material tags apply immediately without a stale surface cache")
	Input.action_press(&"jump")
	await _wait_frames(2)
	Input.action_release(&"jump")
	assert(_jump_count == 1 and not player.is_on_floor())
	var air_cursor := audio._voice_cursor
	await _wait_frames(10)
	assert(audio._voice_cursor == air_cursor, "No run footsteps in the air")
	await _wait_frames(48)
	assert(_jump_count == 1 and _land_count == 1 and player.is_on_floor())
	assert(audio._voice_cursor != air_cursor, "Landing must emit the ground material sound")
	assert(audio._mix[GroundAudioSampler.Surface.WOOD] > 0.99)
	_floor(world, Vector3(player.position.x + 0.6, 1.5, 0), Vector3(0.2, 3.0, 4), GroundAudioSampler.Surface.STONE)
	_key(KEY_D, true)
	await _wait_frames(45)
	var wall_cursor := audio._voice_cursor
	await _wait_frames(45)
	assert(player._movement_speed < 0.05 and audio._voice_cursor == wall_cursor, "Pushing a wall must be silent")
	_key(KEY_D, false)
	audio.enabled = false
	_key(KEY_A, true)
	await _wait_frames(45)
	_key(KEY_A, false)
	assert(audio._voice_cursor == wall_cursor, "Disabled audio must not start voices")
	world.free()
	print("PASS: six terrain sounds, atlas edge mixture, smooth transition (max frame change %.4f), shape-specific floor, idle, wall, jump, air, landing and disable" % max_change)
	quit()

func _test_terrain_sampler() -> void:
	var terrain := Terrain.new()
	var data := TerrainData.new()
	data.size = Vector2i(2, 2)
	data.biomes = PackedByteArray([3, 3, 3, 3])
	data.overlays = PackedByteArray([0, 0, 0, 0])
	data.heights = PackedByteArray([8, 8, 8, 8])
	terrain.data = data
	terrain.top_material = load("res://materials/world/spawn_ground.tres").duplicate()
	root.add_child(terrain)
	var sampler := GroundAudioSampler.new()
	var biomes := PackedInt32Array([1, 5, 0, 2])
	var center := Vector2.ONE * data.cell_size * 0.5
	assert(sampler.surface_at(terrain, center, biomes) == GroundAudioSampler.Surface.GRASS)
	data.overlays.fill(TerrainData.OVERLAY_DIRT)
	assert(sampler.surface_at(terrain, center, biomes) == GroundAudioSampler.Surface.SOIL)
	data.overlays.fill(TerrainData.OVERLAY_DIRT | TerrainData.OVERLAY_PATH)
	assert(sampler.surface_at(terrain, center, biomes) == GroundAudioSampler.Surface.COBBLE, "Path must override dirt")
	data.overlays.fill(TerrainData.OVERLAY_WATER | TerrainData.OVERLAY_BRIDGE)
	assert(sampler.surface_at(terrain, center, biomes) == GroundAudioSampler.Surface.WOOD)
	data.overlays = PackedByteArray([1, 0, 1, 0])
	var found_mixture := false
	for x in 100:
		var point := Vector3(float(x) / 100.0 * data.cell_size, 0, center.y)
		var weights := sampler.sample(terrain, point, 0.22, biomes)
		if weights[GroundAudioSampler.Surface.GRASS] > 0.0 and weights[GroundAudioSampler.Surface.COBBLE] > 0.0:
			found_mixture = true
	assert(found_mixture, "The real path atlas edge must blend both materials under the footprint")
	terrain.free()
