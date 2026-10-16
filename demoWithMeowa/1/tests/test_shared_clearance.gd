extends "res://tests/test_creature_flat_chase.gd"

## Functional proofs only; no crowd population or timing branches.
var positive_queries := 0

class CustomPath extends TerrainPath:
	func _point_blocked(_point: Vector3) -> bool:
		return true

func sparse_empty(field: StaticObstacleField, first: Vector2i, last: Vector2i) -> bool:
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			if field._occupied.has(Vector2i(x,z)): return false
	return true

func grid_checks() -> void:
	var field := StaticObstacleField.new()
	var random := RandomNumberGenerator.new()
	random.seed = 2026101604
	for cell in [Vector2i(-8,-7), Vector2i(8,7), Vector2i(-1,0), Vector2i(3,-2)]: field._occupied[cell] = true
	field._build_grid()
	check(not field._prefix.is_empty() and field._grid.size() == 17 * 15, "bounded fixed layout builds continuous occupancy and a prefix table")
	for sample in 350:
		var first := Vector2i(random.randi_range(-12,12), random.randi_range(-12,12))
		var last := first + Vector2i(random.randi_range(0,10), random.randi_range(0,10))
		check(field._static_clear(first, last) == sparse_empty(field, first, last), "dense/prefix rectangle result matches the original occupied-cell set")
	check(not field._static_clear(Vector2i(-8,-7), Vector2i(-8,-7)), "inclusive negative boundary retains a single occupied cell")
	check(field._static_clear(Vector2i(100,100), Vector2i(200,200)), "a long rectangle outside all baked geometry is empty")
	field._occupied[Vector2i(-1000,-1000)] = true
	field._build_grid()
	check(field._grid.is_empty() and field._prefix.is_empty(), "widely separated geometry does not allocate a huge dense table")
	check(field._static_clear(Vector2i(-10,-10), Vector2i(-8,-7)) == sparse_empty(field, Vector2i(-10,-10), Vector2i(-8,-7)), "sparse fallback retains exact bounded rectangle checks")
	check(not field._static_clear(Vector2i(100,100), Vector2i(200,200)), "large sparse requests retain conservative native fallback")
	field._occupied.clear()
	field._build_grid()
	check(field._grid.is_empty() and field._prefix.is_empty() and field._static_clear(Vector2i(-100,-100), Vector2i(100,100)), "removing the last fixed obstacle releases dense storage")
	field.free()

func query(from: Vector3, to: Vector3, radius := 0.32) -> PhysicsShapeQueryParameters3D:
	var parameters := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	parameters.shape = sphere
	parameters.transform = Transform3D(Basis.IDENTITY, from + Vector3.UP * (radius + 0.08))
	parameters.motion = to - from
	parameters.collision_mask = 1
	parameters.exclude = [terrain.ground_collision_body().get_rid()]
	return parameters

func compare_positive(field: StaticObstacleField, parameters: PhysicsShapeQueryParameters3D) -> void:
	if not field.clear_query(parameters): return
	positive_queries += 1
	var space := world.get_world_3d().direct_space_state
	check(space.cast_motion(parameters)[0] >= 0.999, "every positive navigation proof agrees with the original sphere sweep")
	var motion := parameters.motion
	parameters.motion = Vector3.ZERO
	check(space.intersect_shape(parameters, 1).is_empty(), "a positive swept proof also proves no initial overlap")
	parameters.motion = motion

func compare_routes(label: String) -> void:
	for native in [false, true]:
		path.native_chase_enabled = native
		for pair in [[Vector3(-6,0,4), Vector3(6,0,4)], [Vector3(-6,0,-4), Vector3(6,0,-4)],
				[Vector3(-4.51,0,-4), Vector3(-7,0,-1)], [Vector3(6,0,-1), Vector3(4,0,-4)]]:
			terrain.obstacle_certificates_enabled = false
			var original := path.chase_route(pair[0], pair[1])
			var direct := path.can_walk_direct(pair[0], pair[1])
			terrain.obstacle_certificates_enabled = true
			check(path.chase_route(pair[0], pair[1]) == original, label + ": full chase route preserves original points, native=" + str(native))
			check(path.can_walk_direct(pair[0], pair[1]) == direct, label + ": shortcut eligibility preserves wall/ground rules")

func navigation_checks() -> void:
	var first := wall(Vector3(-4,0,-4), Vector3(0.03,2,3))
	var second := wall(Vector3(4,0,-4), Vector3(0.03,2,3))
	(second.get_child(0) as CollisionShape3D).shape = (first.get_child(0) as CollisionShape3D).shape
	await settle()
	rebuild()
	check(not is_instance_valid(terrain._obstacle_field), "navigation graph construction retains native queries and does not bake the runtime world early")
	var field := terrain.obstacle_field()
	check(field._static.has(first) and field._static.has(second), "runtime callers share a single fixed obstacle raster")
	check(not field._prefix.is_empty(), "real fixed colliders populate the prefix table")
	for x in range(-7,8):
		for z in range(-6,7):
			var from := Vector3(x * 0.87 - 0.13, 0.02, z * 0.87 + 0.19)
			for heading: Vector3 in [Vector3.RIGHT, Vector3.FORWARD, Vector3(1,0,1).normalized()]:
				compare_positive(field, query(from, from + heading * 1.3, 0.24 if x % 2 else 0.4))
	check(positive_queries > 100, "native sweep/origin oracle covers many positive samples with both navigation radii")
	var from := Vector3(-3,0.02,4)
	var to := Vector3(3,0.02,4)
	var origin_checks: Array = []
	check(path._pursuit_start_clear_local(from, to, origin_checks) and path._segment_certified and origin_checks.is_empty(), "one whole-segment proof skips both cast and initial-overlap work")
	check(path.can_walk_direct(from, to) and path._segment_certified, "path lookahead actually consumes the shared empty proof")
	check(not path._segment_clear(Vector3(-6,0,-4), Vector3(6,0,-4)) and not path._segment_certified, "a sub-cell thin fixed wall keeps the native sweep")
	check(not field.clear_query(query(Vector3(-6,0,-4), Vector3(6,0,-4))), "clear endpoints cannot certify a segment crossing a wall")
	compare_routes("fixed walls")
	# Same-step dynamic insertion/transform/layer/exclusion changes remain live.
	var late := wall(Vector3(-2,0,4), Vector3(0.02,2,1.2))
	late.force_update_transform()
	check(not field.clear_query(query(from, to)), "a late wall revokes an earlier empty route in the same step")
	await settle()
	check(not path.can_walk_direct(from, to), "the actual lookahead cannot cross a newly inserted wall")
	compare_routes("late wall")
	var actor := creature("leaf_charger", Vector3(-2.5,0.001,4))
	check(field.clear_motion(actor, terrain.ground_collision_body(), Vector3.ZERO), "the actual smaller capsule can have room beside a live wall")
	var parameters := query(Vector3(-2.5,0,4), Vector3(-2.5,0,4), 0.6)
	check(not field.clear_query(parameters), "a larger navigation sphere cannot borrow the capsule's empty proof")
	parameters = query(Vector3(-2.5,0,4), Vector3(-2.5,0,4), 0.2)
	check(field.clear_query(parameters), "a smaller query uses its own actual radius")
	parameters.margin = 0.35
	check(not field.clear_query(parameters), "query margin expands the complete swept volume")
	parameters = query(Vector3(-2,0,4), Vector3(-2,0,4))
	check(not field.clear_query(parameters) and not path._pursuit_start_clear(Vector3(-2,0,4), to), "initial full overlap is rejected instead of relying on cast_motion alone")
	parameters.exclude = [terrain.ground_collision_body().get_rid(), late.get_rid()]
	check(field.clear_query(parameters), "the shared service respects navigation's own excluded dynamic RIDs")
	parameters.exclude = []
	check(not field.clear_query(parameters), "a query that includes the omitted terrain cannot use its proof")
	parameters = query(from, to)
	late.collision_layer = 4
	check(field.clear_query(parameters), "reflection-only layers preserve ordinary navigation")
	parameters.collision_mask = 4
	check(not field.clear_query(parameters), "the query's actual mask is honored")
	parameters.collision_mask = 2
	check(not field.clear_query(parameters), "a query for omitted enemy bodies retains native physics")
	parameters.collision_mask = 1
	parameters.collide_with_areas = true
	check(not field.clear_query(parameters), "area queries are not certified by a bodies-only service")
	parameters.collide_with_areas = false
	late.collision_layer = 1
	late.position.x = 7
	late.force_update_transform()
	check(field.clear_query(parameters), "current native dynamic transforms restore an empty route without a frame cache")
	clear_actors()
	# The real yielding function uses the same path service, preserving its force.
	player.position = Vector3.ZERO
	var back := mob(Vector3(0,0,4.8))
	mob(Vector3(0,0,4))
	back._yield_side = 1.0
	terrain.obstacle_certificates_enabled = false
	var expected := back._pursuit_crowd_direction(Vector3.FORWARD)
	back._yield_side = 1.0
	terrain.obstacle_certificates_enabled = true
	check(back._pursuit_crowd_direction(Vector3.FORWARD).is_equal_approx(expected) and path._segment_certified, "wall-side yielding obtains the shared proof and preserves the original chosen direction")
	clear_actors()
	late.free()
	await settle()
	# A shared Shape resource has one subscription and invalidates all owners.
	var shared := (first.get_child(0) as CollisionShape3D).shape as BoxShape3D
	var subscriptions := 0
	for connection in shared.changed.get_connections():
		if connection.callable.get_object() == field: subscriptions += 1
	check(subscriptions == 1, "one resource shared by two bodies has one invalidation subscription")
	shared.size = Vector3(12,2,12)
	check(not field._static.has(first) and not field._static.has(second), "a resource edit revokes every static body using it immediately")
	check(not field.clear_query(query(Vector3(0,0,-4), Vector3(1,0,-4))), "shared shape growth blocks a formerly clear region in the same step")
	first.free()
	second.free()
	await settle()
	check(field.clear_query(query(from, to)) and field._prefix.is_empty(), "removing all fixed blockers rebuilds and releases the shared prefix")
	var custom := CustomPath.new()
	custom.prefetch_enabled = false
	custom.build(terrain, 0.32, [])
	check(not custom._pursuit_start_clear(from, to) and not custom._segment_certified, "custom navigation collision overrides retain their original semantics")
	check(not path.can_walk_direct(Vector3(-40,0,4), to), "empty obstacle space cannot certify missing ground beyond the terrain")
	terrain.data.changed.emit()
	await settle()
	rebuild()
	check(path.can_walk_direct(from, to) and path._segment_certified, "terrain rebuild refreshes the navigation proof's excluded support RID")
	terrain.data.set_overlay(Vector2i(6,6), TerrainData.OVERLAY_BRIDGE, true)
	await settle()
	rebuild()
	check(path.can_walk_direct(from, to) and not path._segment_certified, "complex terrain retains native obstacle checks even for a clear ordinary segment")
	terrain.data.set_overlay(Vector2i(6,6), TerrainData.OVERLAY_BRIDGE, false)
	await settle()
	rebuild()
	check(path.can_walk_direct(from, to) and path._segment_certified, "restoring compact flat ground restores runtime query proofs")

func formal_shared_checks() -> void:
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(world)
	current_scene = world
	await settle(12)
	var wave := world.get_node("WavePrototype") as WavePrototype
	terrain = wave.terrain
	player = wave.player
	player.set_physics_process(false)
	player.sword.set_physics_process(false)
	wave.set_physics_process(false)
	var field := terrain.obstacle_field()
	check(not field._prefix.is_empty(), "formal map uses a shared dense/prefix obstacle layout")
	for id in ["leaf_charger", "mini_slime"]:
		var definition: WaveEnemyDefinition = load("res://data/enemies/%s.tres" % id)
		path = wave._navigation_for(definition)
		var actor := creature(id)
		var point := Vector3.INF
		for candidate in path.graph.get_point_ids():
			var start := path.graph.get_point_position(candidate) + Vector3.UP * 0.001
			actor.global_position = start
			if path.can_walk_direct(start, start + Vector3.RIGHT * 2) and path._segment_certified and field.clear_motion(actor, terrain.ground_collision_body(), Vector3.RIGHT * 0.2):
				point = start
				break
		check(point.is_finite(), id + ": formal navigation radius supplies a shared-proof sample")
		if point.is_finite():
			player.global_position = point + Vector3.RIGHT * 2
			actor.separation_strength = 0.0
			actor._move_chase(DELTA, 0.5)
			check(path._segment_certified and actor._flat_motion and actor._flat_motion._certified_clear, id + ": one actual chase uses shared proofs for lookahead and body movement")
			intact(actor, id + ": formal shared proof")
		check(terrain.obstacle_field() == field, "different navigation radii retain the identical shared service")
		clear_actors()
	(world.get_node("MapEffects/GameAudio") as GameAudio).stop_all()
	world.queue_free()
	await settle()

func run() -> void:
	grid_checks()
	world = Node3D.new()
	terrain = Terrain.new()
	terrain.data = TerrainData.new()
	terrain.data.size = Vector2i.ZERO
	terrain.data.resize(Vector2i(-10,-10), Vector2i(21,21))
	world.add_child(terrain)
	root.add_child(world)
	current_scene = world
	player = Player.new()
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	await settle()
	await navigation_checks()
	world.queue_free()
	await settle()
	await formal_shared_checks()
	print("SHARED_CLEARANCE positive native-query comparisons=", positive_queries, "; ", JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
