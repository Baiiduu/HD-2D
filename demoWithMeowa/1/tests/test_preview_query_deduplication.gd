extends "res://tests/test_preview_query_view.gd"
const ObstacleBatch = preload("res://scripts/combat/preview_obstacle_batch.gd")

func neighbor_checks() -> void:
	var view := View.new(session._spatial_index, session)
	check(view.get("memoize_neighbors") != null, "A prediction can opt into a local neighbor candidate cache")
	if view.get("memoize_neighbors") == null: return
	view.set("memoize_neighbors", true)
	var result: Array[int] = []
	var expected: Array[int] = []
	var point := session.enemies[1].global_position
	view.nearby_slots_into(point, 2.0, {}, result)
	var excluded: Dictionary[int, bool] = {session.enemies[1].get_instance_id():true}
	var fresh := View.new(session._spatial_index, session)
	fresh.nearby_slots_into(point, 2.0, excluded, expected)
	view.nearby_slots_into(point, 2.0, excluded, result)
	check(result == expected, "Reused candidates apply the latest BFS visited set in the same order")
	view.nearby_slots_into(point, 2.0, {}, result)
	fresh.nearby_slots_into(point, 2.0, {}, expected)
	check(result == expected, "An earlier visited set never removes candidates from a later traversal")

func volume_checks() -> void:
	wall.position.x = 20.0
	await settle()
	var points := PackedVector3Array([Vector3(0, 0.6, -2), Vector3(4, 0.6, 2), Vector3(0, 0.6, 2), Vector3(4, 0.6, -2)])
	var batch := ObstacleBatch.new(terrain, [player.get_rid()])
	batch.cover(points)
	check(batch.empty_volumes == 1 and batch.proves(Vector3(0, 0.6, 0), Vector3(4, 0.6, 0)), "One empty live volume proves contained rays without another physics query")
	check(not batch.proves(Vector3(-1, 0.6, 0), Vector3(4, 0.6, 0)), "Rays leaving the proven volume always use native fallback")
	wall.position = Vector3(2, 0.5, 0)
	wall.get_child(0).shape.size = Vector3(0.025, 1.0, 0.3)
	await settle()
	batch.cover(points)
	check(not batch.proves(Vector3(0, 0.6, 0), Vector3(4, 0.6, 0)), "Thin wall bounds cannot prove a blocked ray clear")
	check(batch.proves(Vector3(0, 0.6, 1.5), Vector3(4, 0.6, 1.5)), "One live obstacle candidate list also proves rays that miss the obstacle")
	var collider: CollisionShape3D = wall.get_child(0)
	var original_shape := collider.shape
	var convex := ConvexPolygonShape3D.new()
	var vertices := PackedVector3Array()
	for corner in 8: vertices.append(AABB(Vector3(-0.02, -0.5, -0.2), Vector3(0.04, 1.0, 0.4)).get_endpoint(corner))
	convex.points = vertices
	collider.shape = convex
	await settle()
	batch.cover(points)
	check(batch._bounded, "A live convex prop keeps the synchronous preview bounds proof available")
	check(not batch.proves(Vector3(0, 0.6, 0), Vector3(4, 0.6, 0)), "Convex prop bounds never certify a ray through its wall")
	check(batch.proves(Vector3(0, 0.6, 1.5), Vector3(4, 0.6, 1.5)), "Convex prop bounds allow rays missing the prop without another native ray")
	var native_shape := PhysicsServer3D.body_get_shape(wall.get_rid(), 0)
	var expanded := PackedVector3Array()
	for corner in 8: expanded.append(AABB(Vector3(-0.02, -0.5, -1.8), Vector3(0.04, 1.0, 3.6)).get_endpoint(corner))
	PhysicsServer3D.shape_set_data(native_shape, expanded)
	batch.cover(points)
	check(batch._bounded and not batch.proves(Vector3(0, 0.6, 1.5), Vector3(4, 0.6, 1.5)), "Same-step native convex edits are read live before accepting an empty ray")
	PhysicsServer3D.shape_set_data(native_shape, vertices)
	var pose := Transform3D(Basis(Vector3.UP, 0.57).scaled(Vector3(1.2, 0.8, 1.6)), Vector3(0.1, 0, 0.1))
	PhysicsServer3D.body_set_shape_transform(wall.get_rid(), 0, pose)
	batch.cover(points)
	var proved := 0
	for index in 33:
		var z := lerpf(-1.7, 1.7, float(index) / 32.0)
		var from := Vector3(0, 0.6, z)
		var to := Vector3(4, 0.6, z)
		if not batch.proves(from, to): continue
		proved += 1
		var ray := PhysicsRayQueryParameters3D.create(from, to, 1, [player.get_rid()])
		check(terrain.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "Rotated and nonuniform convex bounds never omit an actual native ray hit")
	check(proved > 0, "Rotated convex props still prove genuinely clear rays")
	PhysicsServer3D.body_set_shape_transform(wall.get_rid(), 0, collider.transform)
	collider.shape = original_shape
	await settle()
	wall.collision_layer = ProjectileCollision.MIRROR_SURFACE.COLLISION_LAYER
	await settle()
	batch.cover(points)
	check(not batch.proves(Vector3(0, 0.6, 0), Vector3(4, 0.6, 0)), "Moving mirror layer participates in the same conservative proof")
	wall.collision_layer = 1
	terrain.prepare_obstacle_change(wall)
	var shape_rid := PhysicsServer3D.body_get_shape(wall.get_rid(), 0)
	PhysicsServer3D.shape_set_data(shape_rid, Vector3(0.0125, 0.5, 1.8))
	batch.cover(points)
	check(not batch.proves(Vector3(0, 0.6, 1.5), Vector3(4, 0.6, 1.5)), "Unsignalled native shape edits are read from the server, not old Node resources")
	wall.position.x = 20.0
	var extra: Array[StaticBody3D] = []
	for index in 17:
		extra.append(box(Vector3(0.15 + index * 0.21, 0.5, 0), Vector3(0.02, 1, 0.02)))
	await settle()
	batch.cover(points)
	check(not batch.proves(Vector3(0, 0.6, 1.5), Vector3(4, 0.6, 1.5)), "Saturated native candidate buffers reject the proof instead of omitting bodies")
	for object in extra: object.queue_free()
	await settle()

func compare_short(label: String) -> void:
	var expected := AimPathData.new()
	var actual := AimPathData.new()
	var before := state_bytes()
	body.call("predict_path", query, expected, 8.0, 1, 1.0, false)
	body.call("predict_path", query, actual, 8.0, 1, 1.0, true)
	check(route_bytes(expected) == route_bytes(actual), "Exact short prediction including timing and contacts: " + label)
	check(state_bytes() == before, "Prediction never changes actors, HP, masks or sword clocks: " + label)
	check(player.sword.preview_target(expected) == player.sword.preview_target(actual), "The same first sword target is retained: " + label)

func run() -> void:
	await fixture()
	check(player.action_visuals.get("deduplicate_charge_preview") != null, "Independent preview deduplication switch exists")
	if failures:
		world.queue_free(); await settle(); quit(1); return
	await volume_checks()
	for count in COUNTS:
		await populate(count)
		neighbor_checks()
		await reset()
		check(body.begin_charge(Vector3.FORWARD), "Grounded charge starts")
		body.advance(0.8, Vector3.ZERO, false)
		for heading in [Vector3.FORWARD, Vector3(-0.3, 0, -1).normalized(), Vector3(0.4, 0, -1).normalized()]:
			body.aim(heading)
			compare_short("%d actors, %s" % [count, heading])
		wall.position = Vector3(0, 0.5, -1.2)
		wall.get_child(0).shape.size = Vector3(8, 1, 0.025)
		await settle()
		compare_short("dynamic wall blocks the current prediction")
		wall.position.x = 20.0
		await settle()
		compare_short("dynamic wall moved away")
		var actor := session.enemies[0]
		actor.global_position += Vector3.RIGHT * 0.2
		actor.commit_spatial_state()
		compare_short("same-step external movement committed")
		actor.take_damage(actor.health)
		compare_short("same-step lethal removal")
		body.cancel(true)
	clear_enemies()
	world.queue_free()
	await settle()
	print("Preview query deduplication: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
