extends "res://tests/test_shared_clearance.gd"

## Small functional fixtures only: validate work reuse and revocation, no timings.
func prepared_query_checks(field: StaticObstacleField) -> void:
	var sphere := path._query.shape as SphereShape3D
	var excluded := path._query.exclude
	var positives := 0
	for radius in [0.24, 0.4]:
		sphere.radius = radius
		path._clearance = radius + 0.08
		for margin in [0.0, 0.11]:
			path._query.margin = margin
			path.invalidate_query_certificate()
			for x in range(-7,8,2):
				for z in range(-7,8,2):
					var from := Vector3(x * 0.91 - 0.07, 0.02, z * 0.93 + 0.13)
					var to := from + Vector3(0.31,0,-0.47)
					var parameters := query(from, to, radius)
					parameters.margin = margin
					parameters.exclude = excluded
					var original_proof := field.clear_query(parameters)
					path._segment_clear(from, to)
					check(path._segment_certified == original_proof, "prepared numeric bounds agree with the live native-parameter proof")
					if path._segment_certified:
						positives += 1
						var space := world.get_world_3d().direct_space_state
						check(space.cast_motion(parameters)[0] >= 0.999, "prepared positive agrees with a real native sphere sweep")
						parameters.motion = Vector3.ZERO
						check(space.intersect_shape(parameters, 1).is_empty(), "prepared positive has no real native origin overlap")
	sphere.radius = 0.32
	path._clearance = 0.4
	path._query.margin = 0.0
	path.invalidate_query_certificate()
	check(positives > 100, "prepared proof native-oracle coverage includes both radii and margins")
	print("PREPARED_QUERY native positives=", positives)

func overhead_checks() -> void:
	var unknown := wall(Vector3(-6,0,-6), Vector3(0.02,2,1))
	var script_body := wall(Vector3(7,0,-6), Vector3(0.02,2,1))
	var script_shape := wall(Vector3(6,0,-6), Vector3(0.02,2,1))
	var shifted := wall(Vector3(5,0,-6), Vector3(0.02,2,1))
	var native_edit := wall(Vector3(4,0,-6), Vector3(0.02,2,1))
	for body in [script_body, script_shape, shifted, native_edit]:
		body.set_meta(&"obstacle_layout_managed", true)
	var prop := RicochetProp.new()
	prop.kind = RicochetProp.Kind.IRON_FENCE
	prop.position = Vector3(6,0,6)
	world.add_child(prop)
	await settle()
	rebuild()
	var field := terrain.obstacle_field()
	var generated := prop._collision_body
	var binding_count := generated.get_child_count()
	check(binding_count > 10 and field._static.has(generated), "real procedural fence retains all compound collision pieces in the fixed raster")
	check(not field._polled.has(generated) and field._polled.size() == 1 and field._polled.has(unknown), "only unknown binding owners require per-step native polling")
	prepared_query_checks(field)
	var from := Vector3(-3,0.02,4)
	var to := from + Vector3.RIGHT * 0.2
	var native_transform := path._query.transform
	var native_motion := path._query.motion
	check(path._segment_clear(from, to) and path._segment_certified, "prepared query obtains a real empty-space certificate")
	check(path._query.transform == native_transform and path._query.motion == native_motion, "successful proof avoids native query transform/motion writes")
	var prepared_frame := path._query_config_frame
	for offset in 8:
		check(path._segment_clear(from + Vector3.RIGHT * offset * 0.03, to) and path._segment_certified, "multiple lookaheads reuse prepared configuration")
	check(path._query_config_frame == prepared_frame, "query configuration remains valid throughout the same physics step")
	# Occupied cells reject before even the unknown-owner validation batch.
	await settle(1)
	var checked_frame := field._checked_frame
	check(not field.clear_query(query(Vector3(6,0,6), Vector3(6,0,6))), "fence cells retain conservative native fallback")
	check(field._checked_frame == checked_frame, "a known raster miss performs no binding polling")
	check(path._segment_clear(from, to) and field._checked_frame == Engine.get_physics_frames(), "an empty candidate still validates unknown bindings before acceptance")
	# Configuration changes are infrequent, but they must not use old bounds.
	path._query.margin = 12.0
	path.invalidate_query_certificate()
	path._segment_clear(from, to)
	check(not path._segment_certified, "same-step native margin edits revoke the prepared query explicitly")
	path._query.margin = 0.0
	path.invalidate_query_certificate()
	check(path._segment_clear(from, to) and path._segment_certified, "restoring query margin restores empty-space eligibility")
	var sphere := path._query.shape as SphereShape3D
	sphere.radius = 12.0
	path._segment_clear(from, to)
	check(not path._segment_certified, "Shape resource growth automatically revokes prepared bounds in the same step")
	sphere.radius = 0.32
	check(path._segment_clear(from, to) and path._segment_certified, "Shape resource shrink refreshes prepared bounds")
	var excluded := path._query.exclude
	path._query.exclude = []
	path.invalidate_query_certificate()
	path._segment_clear(from, to)
	check(not path._segment_certified, "omitting the current floor exclusion disables the prepared proof")
	path._query.exclude = excluded
	path._query.collision_mask = 2
	path.invalidate_query_certificate()
	path._segment_clear(from, to)
	check(not path._segment_certified, "prepared queries for omitted enemy bodies retain native checks")
	path._query.collision_mask = 1
	path._query.collide_with_areas = true
	path.invalidate_query_certificate()
	path._segment_clear(from, to)
	check(not path._segment_certified, "prepared area queries retain native checks")
	path._query.collide_with_areas = false
	path.invalidate_query_certificate()
	check(path._segment_clear(from, to) and path._segment_certified, "ordinary bodies-only query can be prepared again")
	path._query.margin = 12.0
	await settle(1)
	path._segment_clear(from, to)
	check(not path._segment_certified, "native query configuration is refreshed on the next physics step")
	path._query.margin = 0.0
	path.invalidate_query_certificate()
	# Floor qualification remains live rather than entering the per-step cache.
	var support := terrain.ground_collision_body()
	support.position.y = 0.1
	path._segment_clear(from, to)
	check(not path._segment_certified, "same-step unsupported floor transform cannot reuse prepared eligibility")
	support.position.y = 0.0
	support.force_update_transform()
	check(path._segment_clear(from, to) and path._segment_certified, "verified floor eligibility is read live after restoration")
	var late := wall(Vector3(-2.9,0,4), Vector3(0.02,2,1))
	late.force_update_transform()
	path._segment_clear(from, to)
	check(not path._segment_certified, "prepared configuration never caches late dynamic obstacle results")
	late.free()
	# Removal of either watch script revokes managed fixed geometry immediately.
	script_body.set_script(null)
	check(not field._static.has(script_body) and field._dynamic.has(script_body), "body script replacement immediately revokes a managed raster")
	(script_shape.get_child(0) as CollisionShape3D).set_script(null)
	check(not field._static.has(script_shape) and field._dynamic.has(script_shape), "shape script replacement immediately revokes a managed raster")
	shifted.position.x = -2.9
	shifted.position.z = 4
	shifted.force_update_transform()
	check(not field._static.has(shifted), "managed body transforms still revoke immediately")
	check(not field.clear_query(query(from, to)), "moved managed geometry is checked at its current transform")
	shifted.free()
	var collider := generated.get_child(0) as CollisionShape3D
	(collider.shape as BoxShape3D).size = Vector3(40,2,40)
	check(not field._static.has(generated), "managed Shape resource changes still revoke without polling")
	check(not field.clear_query(query(from, to)), "grown managed geometry blocks outside its original cells")
	prop.build()
	check(not field._dynamic.has(generated) and not field._static.has(generated), "generator rebuild removes the old collision record")
	check(prop._collision_body.get_child_count() == binding_count and field._dynamic.has(prop._collision_body), "rebuilt fence preserves every physical shape and becomes a live guard")
	# Unknown owners preserve the old next-step shape replacement safety net.
	var replacement := BoxShape3D.new()
	replacement.size = Vector3(40,2,40)
	(unknown.get_child(0) as CollisionShape3D).shape = replacement
	await settle(1)
	check(not field.clear_query(query(from, to)) and not field._polled.has(unknown), "unknown native shape replacement is detected before an empty proof next step")
	unknown.free()
	check(field._static.has(native_edit), "unchanged managed bindings remain fixed until explicitly revoked")
	field.make_dynamic(native_edit)
	(native_edit.get_child(0) as CollisionShape3D).shape = replacement
	check(not field.clear_query(query(from, to)), "explicit revocation before managed native binding edits preserves same-step collision")
	for body in [script_body, script_shape, native_edit]: body.free()
	prop.free()
	await settle()
	check(field._static.is_empty() and field._polled.is_empty(), "all fixed and polled records are removed with their owners")
	check(path._segment_clear(from, to) and path._segment_certified, "empty proof recovers after all edited obstacles are removed")

func formal_overhead_checks() -> void:
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(world)
	current_scene = world
	await settle(12)
	var wave := world.get_node("WavePrototype") as WavePrototype
	check(wave.enemies.is_empty(), "formal inspection does not start a horde")
	wave.set_physics_process(false)
	wave.player.set_physics_process(false)
	wave.player.sword.set_physics_process(false)
	terrain = wave.terrain
	path = wave._path
	var field := terrain.obstacle_field()
	var all_bindings := 0
	var polled_bindings := 0
	var generated_bodies := 0
	for body in field._static:
		all_bindings += field._static[body].nodes.size()
		if body.get_meta(&"obstacle_layout_managed", false):
			generated_bodies += 1
			check(not field._polled.has(body), "formal generated compound body is not polled")
	for body in field._polled: polled_bindings += field._polled[body].nodes.size()
	check(generated_bodies > 30 and polled_bindings < all_bindings / 4, "actual map removes most native shape binding polls")
	print("CLEARANCE_BINDINGS ", JSON.stringify({"fixed_bodies":field._static.size(), "all_shapes":all_bindings,
		"managed_bodies":generated_bodies, "polled_bodies":field._polled.size(), "polled_shapes":polled_bindings}))
	(world.get_node("MapEffects/GameAudio") as GameAudio).stop_all()
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
	await overhead_checks()
	world.queue_free()
	await settle()
	await formal_overhead_checks()
	print("CLEARANCE_OVERHEAD ", JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
