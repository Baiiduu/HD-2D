extends SceneTree

const Oracle = preload("res://tests/fixtures/capsule_wall_intrusion_oracle.gd")
const EPSILON := 0.003
const RADIUS := 0.35
const HEIGHT := 0.72
const STEP_TOP := 0.24
var checks := 0
var failures: Array[String] = []
var results: Array[Dictionary] = []
var output := ""
var world: Node3D
var actor: CharacterBody3D
var collider: CollisionShape3D
var wall: StaticBody3D

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func settle() -> void:
	await physics_frame
	await process_frame

func obstacle(shape: Shape3D, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	world.add_child(body)
	body.position = at
	return body

func record_case(kind: String, penetration: float, x: float) -> void:
	actor.position = Vector3(x, 0, 0)
	var excluded: Array[RID] = [actor.get_rid()]
	var result := Oracle.inspect(world.get_world_3d().direct_space_state, collider, excluded, EPSILON)
	var expected_pass := penetration < EPSILON
	check(result.supported and result.passed == expected_pass, "%s analytic %.1f mm: exact 3 mm inner verdict" % [kind, penetration * 1000.0])
	check(not result.outer_hits.is_empty(), "independent analytic positive overlap is present in the live backend")
	check(absf(result.inner_radius - (RADIUS - EPSILON)) <= 0.000001 and absf(result.inner_height - (HEIGHT - EPSILON * 2.0)) <= 0.000001, "erosion changes neither epsilon nor the center segment within 1 micrometer numeric error")
	var actual := collider.shape as CapsuleShape3D
	check(absf(actual.radius - RADIUS) <= 0.000001 and absf(actual.height - HEIGHT) <= 0.000001, "actual body shape remains unmodified")
	var pairs: Array = []
	for point: Vector3 in result.raw_pairs: pairs.append([point.x, point.y, point.z])
	results.append({"kind": kind, "analytic_depth": penetration, "epsilon": EPSILON,
		"passed": result.passed, "outer_hit_count": result.outer_hits.size(),
		"inner_hit_count": result.inner_hits.size(), "raw_max_pair_distance": result.raw_max_pair_distance,
		"raw_pairs": pairs, "actor": [actor.position.x, actor.position.y, actor.position.z]})

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	actor = CharacterBody3D.new()
	actor.collision_layer = 2
	actor.collision_mask = 1
	collider = CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	collider.shape = capsule
	collider.position.y = HEIGHT * 0.5
	actor.add_child(collider)
	world.add_child(actor)
	actor.set_physics_process(false)
	var plane_wall := BoxShape3D.new()
	plane_wall.size = Vector3(1, 10, 10)
	plane_wall.margin = 0.0
	wall = obstacle(plane_wall, Vector3(-0.5, 0, 0)) # exact face x=0
	await settle()
	for depth in [0.001, 0.0025, 0.0031, 0.005]:
		record_case("flat_wall_margin0", depth, RADIUS - depth)
	wall.free()
	await settle()
	var step := ConvexPolygonShape3D.new()
	var points := PackedVector3Array()
	for x in [-2.0, 0.0]:
		for y in [-1.0, STEP_TOP]:
			for z in [-2.0, 2.0]: points.append(Vector3(x, y, z))
	step.points = points
	step.margin = 0.0
	wall = obstacle(step, Vector3.ZERO)
	await settle()
	# Capsule's lower sphere center is exactly (x, RADIUS, 0). For the
	# margin-zero step, closest point is its top edge (0, STEP_TOP, 0).
	# Choose x from distance=r-depth, independently of the tested query.
	var dy := RADIUS - STEP_TOP
	for depth in [0.001, 0.0025, 0.0031, 0.005]:
		var distance: float = RADIUS - depth
		record_case("low_step_convex_margin0", depth, sqrt(distance * distance - dy * dy))
	actor.scale = Vector3.ONE * 0.5
	var excluded: Array[RID] = [actor.get_rid()]
	var unsupported := Oracle.inspect(world.get_world_3d().direct_space_state, collider, excluded, EPSILON)
	check(not unsupported.supported and not unsupported.passed, "unproved scaled capsule fails conservatively")
	actor.scale = Vector3.ONE
	collider.shape = BoxShape3D.new()
	unsupported = Oracle.inspect(world.get_world_3d().direct_space_state, collider, excluded, EPSILON)
	check(not unsupported.supported and not unsupported.passed, "noncapsule fails conservatively")
	if not output.is_empty():
		FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify({"checks": checks, "failures": failures,
			"backend": ProjectSettings.get_setting("physics/3d/physics_engine"), "epsilon": EPSILON,
			"engine": Engine.get_version_info(), "results": results}, "\t"))
	world.queue_free()
	await settle()
	print("Capsule wall oracle controls: %d checks, %d failures; %s" % [checks, failures.size(), output])
	quit(1 if not failures.is_empty() else 0)
