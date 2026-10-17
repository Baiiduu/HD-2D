extends "res://tests/test_creature_flat_chase.gd"
var native_kernel: RefCounted

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
	var player_collision := CollisionShape3D.new()
	player_collision.name = "Collision"
	var player_capsule := CapsuleShape3D.new()
	player_capsule.radius = 0.24
	player_capsule.height = 1.06592
	player_collision.shape = player_capsule
	player_collision.position.y = 0.532959
	player.add_child(player_collision)
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	await settle()
	rebuild()
	var monument := ArmillaryMonument.new()
	monument.flowers_enabled = false
	monument.garden_lights_enabled = false
	monument.scale = Vector3.ONE * 0.5
	world.add_child(monument)
	await settle(8)
	player.position = Vector3(-0.633353710174561, 0.0000957031734287739, -1.7511220568848)
	# Captured approach to the actual octagonal foot; repeatedly pressing INTO
	# its bevel exercises a case the old outward-moving fixture never reached.
	for id in ["leaf_charger", "pot_brood", "wave_slime"]:
		var actor: SlimeEnemy = mob(Vector3.ZERO) if id == "wave_slime" else creature(id)
		actor._native_swarm = native_kernel
		reset_actor(actor, Vector3(-1.03391551971436, 0.00121884641703218, -1.43049675170898), true)
		for frame in 120:
			await settle(1)
			motion(actor, Vector3(-0.281902,0,2.484056), 1.0)
			var excluded: Array[RID] = [actor.get_rid(), player.get_rid(), terrain.ground_collision_body().get_rid()]
			var result := Oracle.inspect(world.get_world_3d().direct_space_state, actor.get_node("Collision"), excluded)
			check(result.supported and result.passed, "%s: inward low-foot contact frame %d" % [id, frame])
			if not result.passed:
				print("LOW_FOOT_FAILURE ", actor.position, " velocity=",actor.velocity," flat=",actor._ground_moved)
				break
		check(not actor.get_collision_exceptions().has(player), id + ": ordinary motion leaves no collision exception")
		var edge := actor.position
		for frame in 30:
			await settle(1)
			motion(actor, Vector3(-1,0,-1).normalized(), 2.5)
		check(actor.position.distance_to(edge) > 0.8, id + ": reverses away from foot without sticking")
		clear_actors()
	var charger := creature("leaf_charger", Vector3(-4,0.001,-4)) as LeafChargerEnemy
	charger._native_swarm = native_kernel
	player.position = charger.position
	await settle()
	var start := charger.position
	motion(charger, Vector3.ZERO)
	check(TerrainPath.horizontal_distance(start, charger.position) < 0.00001, "Ordinary overlap does not physically push a monster out of the player")
	charger.add_collision_exception_with(player)
	charger.ground_movement_enabled = false
	motion(charger, Vector3.ZERO)
	check(charger.get_collision_exceptions().has(player), "An externally owned player exception is preserved")
	charger.remove_collision_exception_with(player)
	charger.ground_movement_enabled = true
	reset_actor(charger, Vector3(-4,0.001,-4), true)
	player.position = Vector3(-2,0.001,-4)
	await settle()
	var damage := {"hits":0}
	charger.damage_player = func(_amount): damage.hits += 1
	charger.can_damage_player = func(_amount): return true
	charger.attack_phase = LeafChargerEnemy.AttackPhase.CHARGE
	charger._charge_direction = Vector3.RIGHT
	charger._charge_plane = 0.0
	charger._charge_travel = 0.0
	for frame in 90:
		await settle(1)
		charger._advance_charge(DELTA)
		if charger.attack_phase != LeafChargerEnemy.AttackPhase.CHARGE: break
	check(damage.hits == 1, "Lock-line charge still collides with and damages the real player once")
	check(charger.attack_phase == LeafChargerEnemy.AttackPhase.RECOVERY, "Charge retains its contact stop and recovery")
	clear_actors()
	world.queue_free()
	await settle()
	print(JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
