extends SceneTree

var failures: Array[String] = []
var checks := 0
var jumps := 0
var landings := 0

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("FAIL: ", message)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func frames(count: int) -> void:
	for frame in count:
		await physics_frame
	await process_frame

func walk(player: Player, code: Key, count: int) -> int:
	var airborne := 0
	key(code, true)
	for frame in count:
		await frames(1)
		if not player.is_on_floor():
			airborne += 1
	key(code, false)
	return airborne

func walk_diagonal(player: Player, count: int) -> void:
	key(KEY_D, true)
	key(KEY_S, true)
	await frames(count)
	key(KEY_D, false)
	key(KEY_S, false)

func box(parent: Node3D, point: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = point
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)

func reset_player(player: Player, point: Vector3) -> void:
	player.position = point
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await frames(30)

func _run() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	root.add_child(world)
	var player: Player = world.get_node("Player")
	player.movement_camera = null
	player.jumped.connect(func(): jumps += 1)
	player.landed.connect(func(_impact: float): landings += 1)
	var home: Node3D = world.get_node("HouseSite/Home")
	await reset_player(player, home.global_position + Vector3(0, 0.3, home.depth * 0.5 + 3.4))
	var before_landings := landings
	var airborne := await walk(player, KEY_W, 45)
	print("Home ascent: ", home.to_local(player.global_position), "; airborne frames: ", airborne)
	check(player.global_position.y > home.global_position.y + 0.52 and home.to_local(player.global_position).z < home.depth * 0.5 + 1.1, "Walk up all actual home steps onto the porch")
	check(player.is_on_floor() and airborne == 0 and jumps == 0 and landings == before_landings, "Stairs keep walking, without jump/fall/landing events")
	var idle_y := player.position.y
	await frames(20)
	check(absf(player.position.y - idle_y) < 0.005 and player._movement_speed < 0.05, "Standing on the porch is stable")
	airborne = await walk(player, KEY_S, 45)
	print("Home descent: ", home.to_local(player.global_position), "; airborne frames: ", airborne)
	check(absf(player.global_position.y - home.global_position.y) < 0.02 and player.is_on_floor() and airborne == 0, "Walk back down the steps while grounded")
	var hut: Node3D = world.get_node("TrainingHut")
	await reset_player(player, hut.global_position + Vector3(-hut.width * 0.21, 0.3, hut.depth * 0.5 + hut.canopy_depth + 0.8))
	await walk(player, KEY_W, 36)
	check(absf(player.global_position.y - hut.global_position.y - hut.floor_height) < 0.01 and player.is_on_floor(), "Walk onto the actual training hut floor")
	world.free()
	await frames(2)
	# Isolated collision cases use the same capsule and Player script as the map.
	var fixture := Node3D.new()
	root.add_child(fixture)
	box(fixture, Vector3(0, -0.1, 0), Vector3(30, 0.2, 30))
	player = Player.new()
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = 1.06592
	collision.position.y = capsule.height * 0.5
	collision.shape = capsule
	player.add_child(collision)
	fixture.add_child(player)
	box(fixture, Vector3(1, 0.1, 0), Vector3(1, 0.2, 4))
	await reset_player(player, Vector3(-1, 0.3, 0))
	await walk(player, KEY_D, 34)
	print("20 cm step: ", player.position, "; floor: ", player.is_on_floor())
	check(player.position.x > 1.0 and absf(player.position.y - 0.2) < 0.02, "A 20 cm step is walkable")
	await reset_player(player, Vector3(-1, 0.3, -1))
	await walk_diagonal(player, 48)
	check(player.position.x > 1.0 and player.position.z > 1.0 and absf(player.position.y - 0.2) < 0.02, "Diagonal movement also climbs the low step")
	player.auto_step_enabled = false
	await reset_player(player, Vector3(-1, 0.3, 0))
	await walk(player, KEY_D, 40)
	check(player.position.x < 0.4 and player.position.y < 0.02, "Disabling automatic steps restores obstacle blocking")
	player.auto_step_enabled = true
	player.max_step_height = 0.1
	await reset_player(player, Vector3(-1, 0.3, 0))
	await walk(player, KEY_D, 40)
	check(player.position.x < 0.4 and player.position.y < 0.02, "The exposed step height limits which ledges are walkable")
	player.max_step_height = 0.25
	box(fixture, Vector3(1, 0.125, 12), Vector3(1, 0.25, 4))
	await reset_player(player, Vector3(-1, 0.3, 12))
	await walk(player, KEY_D, 34)
	check(player.position.x > 1.0 and absf(player.position.y - 0.25) < 0.02, "A step at the 25 cm limit is walkable")
	box(fixture, Vector3(1, 0.4, 6), Vector3(1, 0.8, 4))
	await reset_player(player, Vector3(-1, 0.3, 6))
	await walk(player, KEY_D, 45)
	check(player.position.x < 0.3 and player.position.y < 0.02, "An 80 cm ledge remains blocked")
	await reset_player(player, Vector3(1.0, 1.1, 6))
	var drop_frames := await walk(player, KEY_A, 38)
	check(drop_frames > 0 and player.is_on_floor() and player.position.y < 0.02, "Walking off a high ledge still falls normally")
	box(fixture, Vector3(1, 0.1, -6), Vector3(1, 0.2, 4))
	box(fixture, Vector3(0, 1.24, -6), Vector3(5, 0.2, 4))
	await reset_player(player, Vector3(-1, 0.03, -6))
	await walk(player, KEY_D, 45)
	check(player.position.x < 0.4 and player.position.y < 0.04, "Head clearance prevents stepping into a low ceiling")
	await reset_player(player, Vector3(-5, 0.3, 0))
	Input.action_press(&"jump")
	await frames(2)
	Input.action_release(&"jump")
	check(not player.is_on_floor() and player.velocity.y > 0.0, "Manual jump still leaves the ground")
	var peak := player.position.y
	for frame in 48:
		await frames(1)
		peak = maxf(peak, player.position.y)
	check(peak > 0.75 and peak < 0.85 and player.is_on_floor(), "Jump retains its 0.8 m height and normal landing")
	fixture.free()
	print("Player stairs: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
