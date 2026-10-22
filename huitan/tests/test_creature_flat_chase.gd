extends "res://tests/test_slime_ground_movement.gd"

const Oracle = preload("res://tests/fixtures/capsule_wall_intrusion_oracle.gd")
const DELTA := 1.0 / 60.0

func creature(id: String, point := Vector3(-3, 0.001, 0)) -> CreatureEnemy:
	var definition: WaveEnemyDefinition = load("res://data/enemies/%s.tres" % id)
	var actor := definition.scene.instantiate() as CreatureEnemy
	actor.configure_wave({"player":player,"terrain":terrain,"camera":null,"navigation":path,"attack_root":world,
		"damage_player":func(_amount): return false,"can_damage_player":func(_amount): return false,
		"request_spawn":Callable(),"spatial_index":spatial}, definition, 0)
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.set_process(false)
	actors.append(actor)
	reset_actor(actor, point, true)
	return actor

func intact(actor: SlimeEnemy, label: String) -> void:
	var excluded: Array[RID] = [actor.get_rid()]
	var result := Oracle.inspect(world.get_world_3d().direct_space_state, actor.get_node("Collision"), excluded)
	check(result.supported and result.passed, label + ": actual capsule's 3 mm interior remains outside walls")

func chase_checks() -> void:
	player.position = Vector3(3,0,0)
	for id in ["leaf_charger", "lantern_spitter", "pot_brood", "bell_frog", "mini_slime"]:
		var actor := creature(id)
		actor.separation_strength = 0.0
		actor._move_chase(DELTA, 0.5)
		check(actor._ground_moved, id + ": ordinary chase bypasses grounded CharacterBody solver")
		check(absf(actor.position.x + 3.0 - actor.effective_move_speed() * DELTA) < 0.00001, id + ": original movement speed retained")
		for step in 30:
			await settle(1)
			actor._move_chase(DELTA, 0.5)
		check(actor._ground_moved and absf(actor.position.y - 0.001) < 0.00001, id + ": flat support persists without accumulating gravity")
		actor._move_local(Vector3.RIGHT, DELTA)
		check(not actor._ground_moved, id + ": local retreat/spacing uses original solver")
		actor._idle_motion(DELTA)
		check(not actor._ground_moved, id + ": telegraph/recovery standing uses original solver")
		reset_actor(actor, Vector3(-3,0.02,0), true)
		actor._move_chase(DELTA, 0.5)
		check(not actor._ground_moved and actor.position.y < 0.02, id + ": spawn offset falls naturally before opting in")
		reset_actor(actor, Vector3(-3,0.001,0), false)
		actor._move_chase(DELTA, 0.5)
		check(not actor._ground_moved, id + ": disabling restores original chase")
		clear_actors()

func obstacle_checks() -> void:
	var actor := creature("leaf_charger")
	var barrier := wall(Vector3.ZERO, Vector3(0.04,2,5))
	await settle()
	reset_actor(actor, Vector3(-2,0.001,0), true)
	motion(actor, Vector3.RIGHT, 300.0)
	check(actor.position.x < -0.36 and actor.position.x > -0.39, "thin-wall sweep retains real Creature radius at high speed")
	intact(actor, "thin wall")
	var before := actor.position
	for step in 60:
		await settle(1)
		motion(actor, Vector3(1,0,1).normalized())
	check(actor.position.z > before.z + 1.1 and actor.position.x < -0.36, "wall sliding preserves tangent motion")
	intact(actor, "sliding")
	barrier.position.x = -2.0
	await settle()
	reset_actor(actor, Vector3(-3,0.001,0), true)
	motion(actor, Vector3.RIGHT, 120.0)
	check(actor.position.x < -2.36, "moving walls are checked live after navigation was built")
	reset_actor(actor, Vector3(-2,0.001,0), true)
	motion(actor, Vector3.ZERO)
	check(absf(actor.position.x + 2.0) > 0.2, "idle body still recovers when a wall covers it")
	var fast_position := actor.position
	reset_actor(actor, Vector3(-2,0.001,0), false)
	motion(actor, Vector3.ZERO)
	check(actor.position.distance_to(fast_position) < 0.00001, "initial deep-overlap recovery matches the original solver's first step")
	actor.ground_movement_enabled = true
	actor.position = fast_position
	for frame in 6:
		await settle(1)
		motion(actor, Vector3.ZERO)
	intact(actor, "overlap recovery")
	barrier.free()
	await settle()
	var step := wall(Vector3.ZERO, Vector3(2,0.24,2))
	step.position.y = 0.12
	await settle()
	reset_actor(actor, Vector3(-1.3,0.001,0), true)
	motion(actor, Vector3.RIGHT)
	check(not actor._ground_moved, "low step returns to original solver instead of changing height or clipping")
	step.free()
	await settle()
	clear_actors()

func wall_yield_checks() -> void:
	player.position = Vector3(0,0,-3)
	var actor := creature("leaf_charger", Vector3(0,0.001,4.8))
	mob(Vector3(0,0,4))
	actor._yield_side = 1.0
	var barrier := wall(Vector3(-0.48,0,4.8), Vector3(0.2,2,1.4))
	await settle()
	check(actor._pursuit_crowd_direction(Vector3.FORWARD).x > 0.0, "blocked first yield side still switches to the open side")
	var before := actor.position
	for frame in 120:
		await settle(1)
		actor._move_chase(DELTA, 0.5)
		spatial.update(actor)
		intact(actor, "wall-side yield")
	check(actor.position.distance_to(before) > 0.7 and actor.position.z < before.z - 0.5, "real crowded pursuit leaves the wall instead of holding a blocked side")
	clear_actors()
	barrier.free()
	await settle()

func terrain_checks() -> void:
	var actor := creature("leaf_charger")
	motion(actor, Vector3.RIGHT)
	check(actor._ground_moved, "initial compact floor supports specialized motion")
	terrain.data.changed.emit()
	await settle()
	reset_actor(actor, Vector3(-3,0.001,0), true)
	motion(actor, Vector3.RIGHT)
	check(actor._ground_moved and actor._flat_motion._floor_rid == terrain.ground_collision_body().get_rid(), "terrain rebuild replaces the excluded support RID")
	terrain.data.set_overlay(Vector2i(6,6), TerrainData.OVERLAY_BRIDGE, true)
	await settle()
	check(terrain.ground_collision_body() == null, "terrain containing bridge railings cannot be excluded as a flat floor")
	reset_actor(actor, Vector3(-3,0.001,0), true)
	motion(actor, Vector3.RIGHT)
	check(not actor._ground_moved, "complex terrain retains all original terrain collisions")
	terrain.data.set_overlay(Vector2i(6,6), TerrainData.OVERLAY_BRIDGE, false)
	await settle()
	reset_actor(actor, Vector3(-3,0.001,0), true)
	motion(actor, Vector3.RIGHT)
	check(actor._ground_moved, "restoring simple terrain permits specialized motion again")
	reset_actor(actor, Vector3(-3,0.001,0), true)
	actor.apply_stun(0.3)
	actor._physics_process(DELTA)
	check(not actor._ground_moved, "stun retains original physics")
	clear_actors()

func formal_map_checks() -> void:
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
	check(wave.slime_ground_movement_enabled and terrain.ground_collision_body() != null, "actual formal map enables the specialized flat floor")
	for id in ["leaf_charger", "lantern_spitter", "pot_brood", "bell_frog", "mini_slime"]:
		var definition: WaveEnemyDefinition = load("res://data/enemies/%s.tres" % id)
		path = wave._navigation_for(definition)
		var point := Vector3.INF
		for candidate in path.graph.get_point_ids():
			var start := path.graph.get_point_position(candidate)
			if path.can_walk_direct(start, start + Vector3.RIGHT * 2.0):
				point = start
				break
		check(point.is_finite(), id + ": actual body-radius navigation supplies a clear sample")
		if not point.is_finite(): continue
		player.global_position = point + Vector3.RIGHT * 2.0
		var actor := creature(id, point + Vector3.UP * 0.001)
		var specialized := 0
		for frame in 20:
			await settle(1)
			actor._move_chase(DELTA, 0.5)
			spatial.update(actor)
			if actor._ground_moved: specialized += 1
			intact(actor, id + ": actual map")
		check(specialized == 20, id + ": actual map chase avoids the general floor solver on every tested step")
		clear_actors()
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
	await chase_checks()
	await obstacle_checks()
	await wall_yield_checks()
	await terrain_checks()
	world.queue_free()
	await settle()
	await formal_map_checks()
	print(JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
