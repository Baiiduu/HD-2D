extends SceneTree

var failures: Array[String] = []
var checks := 0
var world: Node3D
var player: Player

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("FAIL: ", message)

func ticks(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func box(point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = point
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	return body

func reset(point: Vector3) -> void:
	player.position = point
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	await ticks(18)
	check(player.is_on_floor(), "Player begins on the floor")

func walk(code: Key, count: int) -> float:
	var peak := player.position.y
	key(code, true)
	for index in count:
		await ticks(1)
		peak = maxf(peak, player.position.y)
	key(code, false)
	return peak

func _run() -> void:
	# Read the formal map's settings and exact capsule without loading a World.
	var map: SceneState = load("res://scenes/world/world.tscn").get_state()
	player = Player.new()
	var collision := CollisionShape3D.new()
	for index in map.get_node_count():
		var path := String(map.get_node_path(index)).trim_prefix("./")
		for property in map.get_node_property_count(index):
			var name := map.get_node_property_name(index, property)
			var value: Variant = map.get_node_property_value(index, property)
			if path == "Player" and name in [&"auto_step_enabled", &"floor_max_angle", &"jump_enabled"]:
				player.set(name, value)
			elif path == "Player/Collision" and name in [&"shape", &"transform"]:
				collision.set(name, value)
	player.add_child(collision)
	check(collision.shape is CapsuleShape3D, "Fixture uses the exact World player capsule")
	check(not player.auto_step_enabled, "World disables automatic climbing of building steps")
	check(not player.jump_enabled, "World temporarily disables manual jumping")
	world = Node3D.new()
	root.add_child(world)
	box(Vector3(0, -0.1, 0), Vector3(40, 0.2, 40))
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	world.add_child(player)
	# Small lips matter too: a rounded capsule can climb them even without auto-step.
	for height: float in [0.01, 0.02, 0.05, 0.10, 0.20, 0.25]:
		var ledge := box(Vector3(1.5, height * 0.5, 0), Vector3(2, height, 6))
		await reset(Vector3(-1, 0.03, 0))
		var peak := await walk(KEY_D, 50)
		print("LEDGE ", height, " position=", player.position, " peak=", peak)
		check(player.position.x < 0.5 and peak < 0.015, "Walking cannot climb a %.2f m building lip" % height)
		key(KEY_D, true)
		key(KEY_S, true)
		await ticks(16)
		key(KEY_D, false)
		key(KEY_S, false)
		check(player.position.z > 0.5 and player.position.y < 0.015, "Diagonal input slides along the blocked lip")
		var edge := player.position
		await walk(KEY_A, 12)
		check(player.position.x < edge.x - 0.6, "Player can immediately walk away from the lip")
		ledge.free()
		await ticks(2)
	var fence: Node3D = load("res://scenes/buildings/ricochet/iron_fence.tscn").instantiate()
	fence.scale = Vector3.ONE * 0.5
	world.add_child(fence)
	await reset(Vector3(0, 0.03, 1.5))
	var fence_peak := await walk(KEY_W, 40)
	check(fence_peak < 0.015 and player.position.z > 0.15, "Scaled real fence base blocks without lifting the player")
	fence.free()
	await ticks(2)
	var planter: TreePlanter = load("res://scenes/buildings/tree_planter.tscn").instantiate()
	planter.scale = Vector3.ONE * 0.5
	world.add_child(planter)
	await reset(Vector3(planter.width * 0.25 + 1.3, 0.03, 0))
	var planter_peak := await walk(KEY_A, 42)
	check(planter_peak < 0.015 and player.position.x > planter.width * 0.25, "Scaled real planter blocks without lifting the player")
	planter.free()
	await reset(Vector3(-3, 0.03, 0))
	var start := player.position
	await walk(KEY_D, 12)
	check(absf(player.position.x - start.x - 0.8) < 0.09 and player.is_on_floor(), "Flat walking retains its speed and floor contact")
	Input.action_press(&"jump")
	await ticks(1)
	Input.action_release(&"jump")
	var peak := player.position.y
	for index in 48:
		await ticks(1)
		peak = maxf(peak, player.position.y)
	check(peak < 0.015 and player.is_on_floor(), "Jump input cannot lift the player while World jumping is disabled")
	world.free()
	print("Player ground obstacles: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
