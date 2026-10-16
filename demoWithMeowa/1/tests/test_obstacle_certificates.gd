extends "res://tests/test_creature_flat_chase.gd"

func reference_clear(actor: SlimeEnemy, motion: Vector3) -> bool:
	var parameters := PhysicsTestMotionParameters3D.new()
	parameters.from = actor.global_transform
	parameters.motion = motion
	parameters.margin = actor.safe_margin
	parameters.recovery_as_collision = true
	parameters.exclude_bodies = [terrain.ground_collision_body().get_rid()]
	var result := PhysicsTestMotionResult3D.new()
	return not PhysicsServer3D.body_test_motion(actor.get_rid(), parameters, result) and result.get_travel().distance_to(motion) < 0.00001

func certificate_checks() -> void:
	var barrier := wall(Vector3(0,0,0), Vector3(0.023,2,4))
	var angled := wall(Vector3(2,0,4), Vector3(3,2,0.025))
	var editable := wall(Vector3(-6,0,6), Vector3(0.02,2,1))
	var shifted := wall(Vector3(-6,0,-6), Vector3(0.02,2,1))
	var group := Node3D.new()
	world.add_child(group)
	var carried := wall(Vector3(7,0,-7), Vector3(0.02,2,1))
	carried.reparent(group, true)
	angled.rotation.y = PI * 0.25
	await settle()
	var actor := creature("leaf_charger", Vector3(-4,0.001,0))
	motion(actor, Vector3.RIGHT)
	var field := terrain.obstacle_field()
	check(actor._flat_motion._certified_clear, "empty ground actually bypasses body_test_motion")
	check(field._static.has(barrier) and field._static.has(angled), "fixed bodies are rasterized once")
	await settle()
	check(field._static.has(barrier) and field._static.has(angled), "unchanged fixed bodies retain their baked certificates")
	var positives := 0
	for x in range(-5,6):
		for z in range(-5,6):
			actor.global_position = Vector3(x * 0.83 - 0.031, 0.001, z * 0.83 - 0.017)
			for heading: Vector3 in [Vector3.RIGHT, Vector3.FORWARD, Vector3(1,0,1).normalized()]:
				var displacement := heading * 0.12
				if field.clear_motion(actor, terrain.ground_collision_body(), displacement):
					positives += 1
					check(reference_clear(actor, displacement), "every positive certificate agrees with the real capsule sweep")
	check(positives > 50, "conservative raster certifies a useful set of empty-ground samples")
	reset_actor(actor, Vector3(-2,0.001,0), true)
	check(not field.clear_motion(actor, terrain.ground_collision_body(), Vector3.RIGHT * 5), "whole swept volume includes a sub-cell thin wall even with clear endpoints")
	motion(actor, Vector3.RIGHT, 300)
	check(not actor._flat_motion._certified_clear and actor.position.x < -0.35, "high-speed crossing uses native collision and cannot tunnel")
	intact(actor, "certified thin-wall fallback")
	# A baked body's local transform invalidates synchronously, before another move.
	barrier.position.x = -3.0
	barrier.force_update_transform()
	reset_actor(actor, Vector3(-4,0.001,0), true)
	check(not field._static.has(barrier), "moving a baked body immediately demotes it to live checks")
	check(field._static.has(angled), "moving one body does not invalidate unrelated fixed geometry")
	check(not field.clear_motion(actor, terrain.ground_collision_body(), Vector3.RIGHT * 2), "same-step moved wall blocks a formerly empty certificate")
	motion(actor, Vector3.RIGHT, 120)
	check(actor.position.x < -3.35, "moved-wall fallback retains real body radius")
	var shifted_shape := shifted.get_child(0) as CollisionShape3D
	shifted_shape.position += Vector3(2,0,6)
	reset_actor(actor, Vector3(-4,0.001,0), true)
	check(not field._static.has(shifted), "local shape-transform edits revoke baked geometry synchronously")
	check(not field.clear_motion(actor, terrain.ground_collision_body(), Vector3.RIGHT * 0.1), "current shape-owner transform guards the shifted wall")
	group.position += Vector3(-11,0,7)
	carried.force_update_transform()
	check(not field._static.has(carried), "parent transform updates revoke the baked body's world bounds")
	# Shape-resource growth invalidates immediately, even without a new frame.
	var collision := angled.get_child(0) as CollisionShape3D
	(collision.shape as BoxShape3D).size = Vector3(12,2,12)
	check(not field._static.has(angled), "resource growth revokes old fixed bounds immediately")
	reset_actor(actor, Vector3(-2,0.001,2), true)
	check(not field.clear_motion(actor, terrain.ground_collision_body(), Vector3.RIGHT * 0.1), "grown live shape blocks movement outside its old footprint")
	# Native shape-reference replacement has no signal: revoke before direct edits.
	check(field._static.has(editable), "unchanged third body remains baked before explicit native edits")
	field.invalidate_layout()
	var replacement := BoxShape3D.new()
	replacement.size = Vector3(16,2,16)
	(editable.get_child(0) as CollisionShape3D).shape = replacement
	check(not field._static.has(editable), "explicit native-edit invalidation revokes a same-step static snapshot")
	check(not field.clear_motion(actor, terrain.ground_collision_body(), Vector3.RIGHT * 0.1), "same-step native shape replacement is guarded by current geometry")
	barrier.free()
	angled.free()
	editable.free()
	shifted.free()
	group.free()
	await settle()
	reset_actor(actor, Vector3(-4,0.001,0), true)
	motion(actor, Vector3.RIGHT)
	check(actor._flat_motion._certified_clear, "removing blockers permits empty-ground certificates again")
	# New bodies are always live guards, including raw scriptless StaticBody3D.
	var late := wall(Vector3(-3,0,0), Vector3(0.02,2,4))
	late.force_update_transform()
	check(not field.clear_motion(actor, terrain.ground_collision_body(), Vector3.RIGHT * 2), "late unbaked wall is checked in the same step")
	late.position.x = 6
	late.force_update_transform()
	check(field.clear_motion(actor, terrain.ground_collision_body(), Vector3.RIGHT * 0.1), "moving an unbaked wall away restores empty ground")
	late.collision_layer = 4
	late.position.x = -4
	late.force_update_transform()
	check(field.clear_motion(actor, terrain.ground_collision_body(), Vector3.RIGHT * 0.1), "mirror-only layer preserves ordinary walking eligibility")
	late.collision_layer = 1
	check(not field.clear_motion(actor, terrain.ground_collision_body(), Vector3.RIGHT * 0.1), "live collision-layer changes take effect without waiting")
	late.free()
	await settle()
	var unbounded := StaticBody3D.new()
	var unknown_shape := CollisionShape3D.new()
	unknown_shape.shape = WorldBoundaryShape3D.new()
	unknown_shape.position.y = -100
	unbounded.add_child(unknown_shape)
	world.add_child(unbounded)
	unbounded.force_update_transform()
	check(not field.clear_motion(actor, terrain.ground_collision_body(), Vector3.RIGHT * 0.1), "unbounded/unproved live shapes fail closed")
	unbounded.free()
	await settle()
	# All shapes in an owner must be accounted for, not only the named collider.
	var owner: int = actor.get_shape_owners()[0]
	var extra := BoxShape3D.new()
	actor.shape_owner_add_shape(owner, extra)
	check(not field.clear_motion(actor, terrain.ground_collision_body(), Vector3.RIGHT * 0.1), "extra native body geometry cannot use a single-capsule certificate")
	actor.shape_owner_remove_shape(owner, 1)
	# Compare the actual bypass with the previous flat mover, not timing/FPS.
	reset_actor(actor, Vector3(-4,0.001,-4), true)
	terrain.obstacle_certificates_enabled = false
	motion(actor, Vector3(1,0,1).normalized())
	var expected := actor.global_position
	check(not actor._flat_motion._certified_clear, "feature switch restores the existing horizontal sweep")
	reset_actor(actor, Vector3(-4,0.001,-4), true)
	terrain.obstacle_certificates_enabled = true
	motion(actor, Vector3(1,0,1).normalized())
	check(actor._flat_motion._certified_clear and actor.global_position.distance_to(expected) < 0.00001, "empty-ground bypass preserves the actual movement result")
	# Terrain bounds still apply before any obstacle certificate can be used.
	reset_actor(actor, Vector3(0,0.001,0), true)
	motion(actor, Vector3.RIGHT, 2000)
	check(not actor._ground_moved, "crossing the terrain boundary still falls back to full physics")
	clear_actors()
	print("Certificate positives checked against native sweeps: ", positives)

func formal_certificate_checks() -> void:
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
	check(not field._static.is_empty(), "formal map keeps a shared baked obstacle raster")
	var total := 0
	for id in ["leaf_charger", "lantern_spitter", "pot_brood", "bell_frog", "mini_slime"]:
		path = wave._navigation_for(load("res://data/enemies/%s.tres" % id))
		var actor := creature(id)
		var point := Vector3.INF
		for candidate in path.graph.get_point_ids():
			var start := path.graph.get_point_position(candidate) + Vector3.UP * 0.001
			actor.global_position = start
			if field.clear_motion(actor, terrain.ground_collision_body(), Vector3.RIGHT * 0.5) and path.can_walk_direct(start, start + Vector3.RIGHT * 2):
				point = start
				break
		check(point.is_finite(), id + ": actual map contains a certifiable movement sample")
		if point.is_finite():
			player.global_position = point + Vector3.RIGHT * 2
			for frame in 12:
				await settle(1)
				actor._move_chase(DELTA, 0.5)
				spatial.update(actor)
				if actor._flat_motion and actor._flat_motion._certified_clear: total += 1
				intact(actor, id + ": formal certificate")
		clear_actors()
	check(total > 0, "formal map really skips body sweeps in selected empty-ground moves")
	print("Formal map selected-sample certified moves: ", total, "; fixed=", field._static.size(), "; live=", field._dynamic.size())
	world.queue_free()
	await settle()

func run() -> void:
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
	rebuild()
	await certificate_checks()
	world.queue_free()
	await settle()
	await formal_certificate_checks()
	print(JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
