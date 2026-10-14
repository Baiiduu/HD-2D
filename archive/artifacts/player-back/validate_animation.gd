extends SceneTree

var world: Node3D
var player: Player
var frames_seen: Dictionary = {}
var failures: Array[String] = []
var output_dir := "D:/Project/HD-2DMap/artifacts/player-back/"

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, description: String) -> void:
	print(("PASS: " if condition else "FAIL: ") + description)
	if not condition:
		failures.append(description)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func advance(count: int) -> void:
	for tick in count:
		await physics_frame
		await process_frame
		frames_seen[player.sprite.texture.resource_path] = true

func capture(filename: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output_dir + filename)

func count_frames(prefix: String) -> int:
	return frames_seen.keys().filter(func(path: String) -> bool: return prefix in path).size()

func _run() -> void:
	world = load("res://scenes/four_realms.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	player = world.get_node("Player")
	await advance(80)
	check(player.animations.get_animation_names().size() == 4 and not player.animations.has_animation(&"idle_front") and not player.animations.has_animation(&"run_front"), "Only side and back idle/run slots exist")
	check(player._animation == &"idle" and frames_seen.size() == 8, "Original side idle loops all eight frames")
	check(player.sprite.texture.get_size() == Vector2(80, 80), "Native 80px canvas remains unchanged")
	await capture("game-idle.png")
	frames_seen.clear()
	var start := player.position
	key(KEY_D, true)
	await advance(48)
	check(player.position.x > start.x + 1.0 and player._animation == &"run" and not player.sprite.flip_h and count_frames("/run_") == 8, "Right movement loops original side run without mirroring")
	await capture("game-run-right.png")
	key(KEY_D, false)
	key(KEY_A, true)
	await advance(38)
	check(player.sprite.flip_h and player._animation == &"run", "Left movement mirrors side run")
	await capture("game-run-left.png")
	key(KEY_A, false)
	key(KEY_S, true)
	await advance(30)
	check(player._animation == &"run" and player.sprite.flip_h, "Down movement keeps the last side facing")
	await capture("game-run-down.png")
	key(KEY_S, false)
	await advance(8)
	check(player._animation == &"idle" and player.sprite.flip_h, "Stopping downward movement keeps side idle")
	key(KEY_W, true)
	frames_seen.clear()
	await advance(48)
	check(not player.sprite.flip_h and player._animation == &"run_back" and count_frames("/run_back_") == 8, "Up movement loops eight new back run frames")
	await capture("game-run-back.png")
	key(KEY_W, false)
	frames_seen.clear()
	await advance(80)
	check(player._animation == &"idle_back" and count_frames("/idle_back_") == 2, "Stopping upward movement loops the two curated back idle poses")
	await capture("game-idle-back.png")
	key(KEY_S, true)
	await advance(8)
	check(player._animation == &"run" and player.sprite.flip_h, "Down after back restores the remembered left side")
	key(KEY_S, false)
	key(KEY_W, true)
	key(KEY_A, true)
	await advance(8)
	check(player._animation == &"run" and player.sprite.flip_h, "Diagonal movement prefers horizontal facing")
	key(KEY_W, false)
	key(KEY_A, false)
	await advance(8)
	check(player._animation == &"idle" and player.sprite.flip_h, "Stopping diagonal movement keeps left side idle")
	var old_bounds := player.bounds
	player.bounds = Rect2(player.position.x, player.position.z, 0.4, 0.4)
	key(KEY_A, true)
	await advance(12)
	check(player._animation == &"idle", "Holding movement into the map boundary stays idle")
	key(KEY_A, false)
	player.bounds = old_bounds
	var wall := StaticBody3D.new()
	wall.position = player.position + Vector3(0.8, 0.8, 0)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 2.0, 2.0)
	collision.shape = box
	wall.add_child(collision)
	world.add_child(wall)
	key(KEY_D, true)
	await advance(60)
	check(player._animation == &"idle", "Holding movement into a physical wall stays idle")
	key(KEY_D, false)
	var mirrors: PlanarWaterReflection = world.get_node("WaterReflection")
	var reflected := false
	for pair in mirrors.sprites:
		if pair.source == player.sprite:
			var material: ShaderMaterial = pair.proxy.material_override
			reflected = material.get_shader_parameter("sprite_texture") == player.sprite.texture and pair.proxy.mesh.size == Vector2(1.875, 1.875)
	check(reflected, "Water reflection tracks current frame and native canvas")
	print("Animation validation finished: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
