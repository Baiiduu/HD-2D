extends SceneTree

var failures: Array[String] = []
var checks := 0
var travelled: Array[Dictionary] = []

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("FAIL: ", message)

func frames(count: int) -> void:
	for i in count:
		await physics_frame
	await process_frame

func box(world: Node3D, point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = point
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	return body

func reset(player: Player, point := Vector3.ZERO) -> void:
	player.position = point
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await frames(42)

func press_blink() -> void:
	Input.action_press(&"blink")
	await frames(1)
	Input.action_release(&"blink")

func same_pixels(left: Texture2D, right: Texture2D) -> bool:
	var a := left.get_image()
	var b := right.get_image()
	# 新动作只增加对称透明留白，比较时按 Sprite3D 的中心对齐。
	var size := Vector2i(mini(a.get_width(), b.get_width()), mini(a.get_height(), b.get_height()))
	a = a.get_region(Rect2i((a.get_size() - size) / 2, size))
	b = b.get_region(Rect2i((b.get_size() - size) / 2, size))
	for y in size.y:
		for x in size.x:
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if (ca.a > 0.0 or cb.a > 0.0) and ca != cb:
				return false
	return true

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	box(world, Vector3(0, -0.1, 0), Vector3(40, 0.2, 40))
	var player := Player.new()
	player.animations = load("res://assets/meowa/player/animations.tres")
	player.bounds = Rect2(-18, -18, 36, 36)
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	sprite.position.y = 0.75
	player.add_child(sprite)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.24
	shape.height = 1.06592
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = shape.height * 0.5
	player.add_child(collision)
	world.add_child(player)
	player.blink_travelled.connect(func(start: Vector3, destination: Vector3): travelled.append({"start": start, "end": destination}))
	await reset(player)
	check(player.is_on_floor(), "Fixture capsule is grounded")
	var start := player.position
	await press_blink()
	check(player._blink.active and same_pixels(player.sprite.texture, player.animations.get_frame_texture(&"idle", 0)), "Shift begins at the actual idle frame")
	await frames(1)
	check(player.position.distance_to(start) < 0.02, "No displacement during anticipation")
	await frames(3)
	check(absf(player.position.x - start.x - player.blink_distance) < 0.03, "Teleport executes once at the held pose")
	check(travelled.size() == 1 and travelled[0]["start"].is_equal_approx(start) and travelled[0]["end"].is_equal_approx(player.global_position), "Environment receives exactly the completed world-space path")
	check(same_pixels(player.sprite.texture, PlayerBlink.POSES.get_frame_texture(&"dodge", 3)), "Teleport holds the generated dodge pose")
	check(not player.sprite.flip_h and player._facing == &"side", "Facing is unchanged")
	var echoes := get_nodes_in_group(&"blink_echoes")
	check(echoes.size() == 2, "Two independent afterimages are spawned")
	var old_echo := echoes[0] as Sprite3D if not echoes.is_empty() else null
	if old_echo:
		var old_position := old_echo.global_position
		var opacity: float = old_echo.material_override.get_shader_parameter("opacity")
		player.position.z += 0.2
		await frames(3)
		check(old_echo.global_position.is_equal_approx(old_position), "Afterimage stays in its original world position")
		check(float(old_echo.material_override.get_shader_parameter("opacity")) < opacity, "Afterimage fades")
	await frames(25)
	check(not player._blink.active and get_nodes_in_group(&"blink_echoes").is_empty(), "Action completes and afterimages are freed")
	check(player._animation == &"idle" and same_pixels(player.sprite.texture, player.animations.get_frame_texture(&"idle", player._animation_frame)), "Action reconnects to the existing idle")
	await reset(player)
	await press_blink()
	await frames(8)
	check(player._blink.active and not player._blink.movement_locked, "Movement unlocks during recovery, before the whole animation ends")
	var walking_start := player.position
	var key := InputEventKey.new()
	key.physical_keycode = KEY_D
	key.pressed = true
	Input.parse_input_event(key)
	await frames(3)
	key = key.duplicate()
	key.pressed = false
	Input.parse_input_event(key)
	check(player.position.x > walking_start.x + 0.1, "Walking resumes immediately in the recovery phase")
	check(player._animation == &"run" and same_pixels(player.sprite.texture, player.animations.get_frame_texture(&"run", player._animation_frame)), "Recovery reconnects to running frames instead of sliding on idle")
	await reset(player)
	start = player.position
	await press_blink()
	await frames(12)
	await press_blink()
	await frames(14)
	check(player.position.x > start.x + player.blink_distance * 1.9, "Late buffered input starts a second blink when cooldown clears")
	await reset(player)
	var wall := box(world, Vector3(0.9, 1.0, 0), Vector3(0.05, 2.0, 4.0))
	await frames(2)
	await press_blink()
	await frames(12)
	check(player.position.x < 0.64 and player.position.x > 0.5, "Capsule stops before a thin wall and cannot tunnel through")
	check(travelled.back()["end"].is_equal_approx(player.global_position), "Environment path stops at the same thin-wall collision")
	await reset(player, Vector3(0.62, 0, 0))
	var before_count := travelled.size()
	await press_blink()
	await frames(12)
	check(travelled.size() == before_count, "A blocked blink does not create an environment impulse")
	wall.queue_free()
	await reset(player, Vector3(17.8, 0, 0))
	await press_blink()
	await frames(12)
	check(player.position.x <= 18.001, "Blink stays within map bounds")
	await reset(player)
	player.sprite.flip_h = true
	player._side_flip_h = true
	start = player.position
	await press_blink()
	await frames(12)
	check(player.position.x < start.x - 1.9 and player.sprite.flip_h, "Idle left-facing blink goes left without turning")
	await reset(player)
	player.sprite.flip_h = false
	player._side_flip_h = false
	var blocker := Node.new()
	blocker.add_to_group(&"gameplay_input_blockers")
	world.add_child(blocker)
	start = player.position
	before_count = travelled.size()
	await press_blink()
	await frames(15)
	check(not player._blink.active and player.position.distance_to(start) < 0.02, "UI blocks blink input")
	check(travelled.size() == before_count, "UI-blocked blink does not disturb the environment")
	blocker.queue_free()
	await frames(2)
	await press_blink()
	world.add_to_group(&"gameplay_input_blockers")
	await frames(12)
	check(not player._blink.active and player.position.distance_to(start) < 0.02, "Opening UI cancels a pending teleport")
	check(travelled.size() == before_count, "Cancelled anticipation does not disturb the environment")
	world.remove_from_group(&"gameplay_input_blockers")
	await reset(player)
	player.blink_enabled = false
	start = player.position
	await press_blink()
	await frames(15)
	check(player.position.distance_to(start) < 0.02, "Blink enable toggle works")
	player.blink_enabled = true
	await reset(player, Vector3(0, 3.0, 0))
	player.position.y = 3.0
	player.reset_physics_interpolation()
	await frames(1)
	await press_blink()
	check(not player._blink.active, "Airborne player cannot blink")
	await reset(player)
	player._facing = &"back"
	start = player.position
	await press_blink()
	await frames(12)
	check(player.position.z < start.z - 1.9 and player._facing == &"back", "Back-facing fallback preserves orientation")
	world.queue_free()
	await frames(2)
	print(JSON.stringify({"checks": checks, "failures": failures, "passed": failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
