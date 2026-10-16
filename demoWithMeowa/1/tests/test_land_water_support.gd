extends "res://tests/test_creature_flat_chase.gd"

func split_checks() -> void:
	var floor_body := terrain.ground_collision_body()
	var water_body := terrain._water_collision_body
	check(floor_body.get_child_count() == 1 and water_body != floor_body and water_body.get_child_count() == 2, "sheet and unchanged per-cell water boxes have independent bodies")
	var raw := PackedVector3Array()
	for name in ["Top", "Walls"]:
		var visual := terrain._generated.get_node(name) as MeshInstance3D
		var arrays := visual.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: Variant = arrays[Mesh.ARRAY_INDEX]
		if indices == null or indices.is_empty():
			for vertex in vertices: raw.append(visual.transform * vertex)
		else:
			for index in indices: raw.append(visual.transform * vertices[index])
	check(raw.to_byte_array() == floor_body.get_child(0).shape.get_faces().to_byte_array(), "split retains every original basin, shore and land triangle")
	var field := terrain.obstacle_field()
	check(field._support == floor_body and not field._static.has(floor_body) and field._static.has(water_body), "only the water boxes enter the fixed obstacle raster")
	check(path._query.exclude.has(floor_body.get_rid()) and not path._query.exclude.has(water_body.get_rid()), "navigation excludes the sheet but always sweeps water blockers")
	check(path.can_walk_direct(Vector3(-3,0,0), Vector3(3,0,0)) and path._segment_certified, "dry pursuit receives the shared empty-space proof")
	check(not path.can_walk_direct(Vector3(7,0,9.6), Vector3(13,0,9.6)), "pursuit cannot cross the pond")
	check(not path._query_certified_clear(Vector3(7,0,9.6), Vector3(13,0,9.6)), "water also rejects geometric sweep certificates")
	terrain.query_diagnostics_enabled = true
	terrain.reset_query_metrics()
	for x in range(-5, 5):
		var from := Vector3(x,1,-3)
		var to := from + Vector3(0.4,0,0.2)
		check(terrain.ray_clear(from,to,1,[]) and world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1)).is_empty(), "dry ray proof agrees with native ray %d" % x)
	check(terrain.get_query_metrics().ray_certified == 10 and terrain.get_query_metrics().ray_native == 0, "dry rays perform no native queries")
	check(not terrain.ray_clear(Vector3(7,1,9.6),Vector3(13,1,9.6),1,[]), "water remains a real ray blocker")
	check(not terrain.ray_clear(Vector3(-3,1,0),Vector3(-3,-1,0),1,[]), "downward rays still hit the sheet")
	terrain.query_diagnostics_enabled = false
	# Compare the split with the previous single body, including native swept
	# motion. The old body lives far away and is excluded from no real query.
	var reference := StaticBody3D.new()
	for body in [floor_body, water_body]:
		for child in body.get_children():
			var collider := CollisionShape3D.new()
			collider.shape = child.shape
			collider.transform = child.transform
			reference.add_child(collider)
	var offset := Vector3(80,0,0)
	reference.position = offset
	world.add_child(reference)
	await settle()
	var cases := [
		[Vector3(7,1,9.6),Vector3(13,1,9.6)],
		[Vector3(9.6,1,7),Vector3(9.6,1,12)],
		[Vector3(7,1,7),Vector3(12,1,12)],
		[Vector3(9.6,4,9.6),Vector3(9.6,-2,9.6)],
		[Vector3(7,-0.3,9.6),Vector3(11,-0.3,9.6)],
		[Vector3(-3,1,-3),Vector3(-3,-1,-3)]]
	var actor := mob(Vector3(-3,0,0))
	for pair in cases:
		var actual := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pair[0],pair[1],1))
		var expected := world.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pair[0]+offset,pair[1]+offset,1))
		check(not actual.is_empty() and not expected.is_empty() and actual.position.distance_to(expected.position-offset) < 0.0001 and actual.normal.distance_to(expected.normal) < 0.0001, "split preserves original ray contact and normal")
		var parameters := PhysicsTestMotionParameters3D.new()
		parameters.from = Transform3D(Basis.IDENTITY,pair[0])
		parameters.motion = pair[1]-pair[0]
		parameters.recovery_as_collision = true
		var result := PhysicsTestMotionResult3D.new()
		var old_result := PhysicsTestMotionResult3D.new()
		var hit := PhysicsServer3D.body_test_motion(actor.get_rid(),parameters,result)
		parameters.from.origin += offset
		var old_hit := PhysicsServer3D.body_test_motion(actor.get_rid(),parameters,old_result)
		var same := hit == old_hit and result.get_travel().distance_to(old_result.get_travel()) < 0.0001
		if hit and old_hit: same = same and result.get_collision_normal().distance_to(old_result.get_collision_normal()) < 0.0001
		check(same, "split preserves original native body sweep")
	clear_actors()
	reference.free()
	await settle()

func rebuild_checks() -> void:
	var field := terrain.obstacle_field()
	var shape_count := field._bound_shapes.size()
	var body_count := field._body_shapes.size()
	for iteration in 5:
		var old_floor := terrain._collision_body.get_rid()
		var old_water := terrain._water_collision_body.get_rid()
		terrain.data.changed.emit()
		await settle()
		rebuild()
		check(terrain._collision_body.get_rid() != old_floor and terrain._water_collision_body.get_rid() != old_water, "rebuild replaces both generated bodies")
		check(field._support == terrain.ground_collision_body() and field._static.has(terrain._water_collision_body), "rebuild restores certificates for new generator bodies")
		check(terrain.ray_clear(Vector3(-3,1,-3),Vector3(3,1,-3),1,[]) and field.clear_ray(Vector3(-3,1,-3),Vector3(3,1,-3),1,[]), "rebuilt terrain retains dry ray proof")
		check(field._bound_shapes.size() == shape_count and field._body_shapes.size() == body_count, "rebuild releases obsolete shape resources and owner records")
	var water := terrain._water_collision_body
	terrain.prepare_obstacle_change(water)
	water.position = Vector3(-12,0,-9.6)
	water.force_update_transform()
	await settle()
	check(terrain.ground_collision_body() != null and field._dynamic.has(water), "water mutation keeps independent dry support but revokes its fixed raster")
	check(not terrain.ray_clear(Vector3(-5,1,0),Vector3(2,1,0),1,[]), "moved water blocker is checked live")
	check(not path._query_certified_clear(Vector3(-5,0,0),Vector3(2,0,0)), "moved water blocker cannot use a stale sweep certificate")
	terrain.prepare_obstacle_shape_change(terrain._collision_body.get_child(0).shape)
	check(terrain.ground_collision_body() == null and not field.clear_ray(Vector3(-3,1,-3),Vector3(3,1,-3),1,[]), "native floor edit revokes dry support and its ray certificate")
	terrain.data.changed.emit()
	await settle()
	rebuild()
	check(terrain.ground_collision_body() == field._support and field._bound_shapes.size() == shape_count, "generator rebuild restores bindings after explicit invalidation")

func eligibility_checks() -> void:
	var saved := terrain.data
	var cases: Array[TerrainData] = []
	for overlay in [TerrainData.OVERLAY_BRIDGE,TerrainData.OVERLAY_RAMP]:
		var marked := saved.duplicate(true) as TerrainData
		marked.set_overlay(Vector2i(6,6),overlay,true)
		cases.append(marked)
	for cell in [Vector2i.ZERO,Vector2i(6,6)]:
		var raised := saved.duplicate(true) as TerrainData
		raised.set_level(cell,1)
		cases.append(raised)
	var all_water := TerrainData.new()
	all_water.size = Vector2i.ZERO
	all_water.resize(Vector2i.ZERO,Vector2i.ONE)
	all_water.set_overlay(Vector2i.ZERO,TerrainData.OVERLAY_WATER,true)
	cases.append(all_water)
	for edited in cases:
		terrain.data = edited
		await settle()
		check(terrain.ground_collision_body() == null, "slopes, bridges, raised land/basins and all-water maps retain native fallback")
	terrain.data = saved
	await settle()
	rebuild()
	check(terrain.obstacle_field()._support == terrain.ground_collision_body() and terrain.ground_collision_body() != null, "restoring dry land with lower water restores qualification")

func run() -> void:
	world = Node3D.new()
	terrain = Terrain.new()
	terrain.data = TerrainData.new()
	terrain.data.size = Vector2i.ZERO
	terrain.data.resize(Vector2i(-10,-10),Vector2i(21,21))
	for cell in [Vector2i(6,6),Vector2i(7,6)]:
		terrain.data.set_overlay(cell,TerrainData.OVERLAY_WATER,true)
		terrain.data.set_level(cell,-1)
	world.add_child(terrain)
	root.add_child(world)
	current_scene = world
	player = Player.new()
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	world.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	await settle()
	check(terrain.ground_collision_body() != null,"lower corner water retains qualified dry-land support")
	if terrain.ground_collision_body() == null:
		world.queue_free()
		await settle()
		print("LAND_WATER_SUPPORT ",JSON.stringify({"checks":checks,"failures":failures}))
		quit(1)
		return
	rebuild()
	await split_checks()
	player.position = Vector3(3,0,0)
	for id in ["leaf_charger", "lantern_spitter", "pot_brood", "bell_frog", "mini_slime"]:
		var actor := creature(id)
		actor.separation_strength = 0.0
		actor._move_chase(DELTA,0.5)
		check(actor._ground_moved and actor._flat_motion._certified_clear, id + ": lower water does not force dry chase into native motion")
		check(absf(actor.position.x + 3.0 - actor.effective_move_speed()*DELTA) < 0.00001, id + ": exact chase speed retained")
		reset_actor(actor,Vector3(7,0.001,9.6),true)
		motion(actor,Vector3.RIGHT,300.0)
		check(actor.position.x < 8.81-actor.body_radius, id + ": high-speed movement cannot tunnel through water")
		intact(actor,id + ": water edge")
		clear_actors()
	await rebuild_checks()
	await eligibility_checks()
	world.queue_free()
	await settle()
	print("LAND_WATER_SUPPORT ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
