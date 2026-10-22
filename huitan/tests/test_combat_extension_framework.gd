extends "res://tests/test_creature_flat_chase.gd"

const SESSION := preload("res://tests/fixtures/ricochet_session.gd")
const ENEMY_EXAMPLE := preload("res://examples/combat/shared_chase_enemy.gd")
const SKILL_EXAMPLE := preload("res://examples/combat/shared_query_skill.gd")
var session: WavePrototype

func example_enemy(point: Vector3) -> CreatureEnemy:
	var definition: WaveEnemyDefinition = load("res://data/enemies/leaf_charger.tres").duplicate()
	definition.health = 100.0
	definition.attack_damage = 0.0
	var actor := definition.scene.instantiate() as CreatureEnemy
	actor.set_script(ENEMY_EXAMPLE)
	actor.configure_wave({"player":player, "terrain":terrain, "camera":null, "navigation":path,
		"attack_root":world, "spatial_index":spatial, "request_spawn":Callable(),
		"damage_player":func(_amount): return false, "can_damage_player":func(_amount): return false,
		"combat_active":session.combat_active}, definition, 0.0)
	actor.position = point
	actor.ground_movement_enabled = true
	world.add_child(actor)
	actor.set_process(false)
	actor.set_physics_process(false)
	actors.append(actor)
	return actor

func obstacle_api_checks() -> void:
	var left := wall(Vector3(-7,0,-7), Vector3(0.02,2,1))
	var right := wall(Vector3(7,0,-7), Vector3(0.02,2,1))
	var other := wall(Vector3(-7,0,7), Vector3(0.02,2,1))
	var shared := (left.get_child(0) as CollisionShape3D).shape
	(right.get_child(0) as CollisionShape3D).shape = shared
	for body in [left,right,other]: body.set_meta(&"obstacle_layout_managed", true)
	terrain.prepare_obstacle_change(left)
	terrain.prepare_obstacle_shape_change(shared)
	check(terrain.replace_obstacle_shape(right.get_child(0), shared), "cold native binding replacement uses the same public path")
	check(not is_instance_valid(terrain._obstacle_field), "cold invalidation does not construct a field or scan the scene")
	var field := terrain.obstacle_field()
	check(field._static.has(left) and field._static.has(right), "unchanged cold edits do not prevent later static baking")
	terrain.prepare_obstacle_shape_change(shared)
	check(not field._static.has(left) and not field._static.has(right) and field._static.has(other), "shared shape preparation revokes all owners and leaves unrelated geometry fixed")
	shared.margin += 0.02
	var replacement := BoxShape3D.new()
	replacement.size = Vector3(18,2,18)
	check(terrain.replace_obstacle_shape(other.get_child(0), replacement), "public replacement accepts a real collider")
	check(not field._static.has(other), "native reference replacement revokes its owner before assignment")
	var excluded: Array[RID] = [player.get_rid()]
	check(not terrain.ray_clear(Vector3(3,0.45,7), Vector3(0,0.45,7), 1, excluded), "replacement geometry blocks a formerly empty shared ray in the same step")
	for body in [left,right,other]: body.free()
	await settle()
	terrain.ray_clear(Vector3(-1,0.45,4), Vector3(1,0.45,4), 1, excluded)
	check(terrain.get_query_metrics().ray_requests == 0, "diagnostics are disabled by default")
	terrain.query_diagnostics_enabled = true
	terrain.reset_query_metrics()
	check(terrain.ray_clear(Vector3(-1,0.45,4), Vector3(1,0.45,4), 1, excluded), "instrumented empty ray still succeeds")
	check(not terrain.ray_clear(Vector3(0,0.45,4), Vector3(0,-1,4), 1, excluded), "instrumented ground ray keeps exact native fallback")
	var metrics := terrain.get_query_metrics()
	check(metrics == {"ray_requests":2,"ray_certified":1,"ray_native":1}, "optional counters partition actual proof and native calls")
	check(terrain.get_query_metrics() == metrics, "reading counters performs no additional work or queries")
	terrain.query_diagnostics_enabled = false
	terrain.ray_clear(Vector3(-1,0.45,4), Vector3(1,0.45,4), 1, excluded)
	check(terrain.get_query_metrics() == metrics, "disabled counters stay unchanged")
	terrain.reset_query_metrics()

func lifecycle_and_examples() -> void:
	player.position = Vector3(3,0.001,0)
	var first := example_enemy(Vector3(-3,0.001,0))
	var second := example_enemy(Vector3(-1,0.001,0))
	check(spatial._entries.has(first) and spatial._entries.has(second), "example inherits automatic spawn registration")
	var first_slot: int = spatial._entries.get(first)
	first._physics_process(DELTA)
	check(first._ground_moved and spatial._positions[first_slot] == first.global_position, "example ordinary tick uses flat movement and automatically commits its real position")
	first.global_position = Vector3(5,0.001,4)
	first.reset_physics_interpolation()
	first.commit_spatial_state()
	check(spatial.nearby(first.global_position,0.1) == [first], "external relocation is immediately visible after the public commit")
	var revision := spatial._crowd_revision
	first.separation_radius += 0.3
	first.commit_spatial_state()
	check(spatial._crowd_revision > revision, "crowd metadata edits invalidate batch candidates through the same commit")
	first.spawn_delay = 1.0
	first.commit_spatial_state()
	check(spatial._active[first_slot] == 0, "activation edits are published through the same commit")
	first.spawn_delay = 0.0
	first.commit_spatial_state()
	var result: Array[WaveEnemy] = [first]
	var excluded: Dictionary[int, bool] = {}
	var reference := session.get_nearby_enemies(Vector3.ZERO, 12.0)
	session.get_nearby_enemies_into(Vector3.ZERO,12.0,excluded,result)
	check(result == reference, "public reusable candidate query preserves original order and content")
	excluded[first.get_instance_id()] = true
	session.get_nearby_enemies_into(Vector3.ZERO,12.0,excluded,result)
	check(result == [second], "reusable candidate query clears old contents and respects excluded IDs")
	var skill := SKILL_EXAMPLE.new()
	skill.session = session
	world.add_child(skill)
	check(not skill.is_processing() and not skill.is_physics_processing(), "skill example creates no idle callbacks")
	terrain.query_diagnostics_enabled = true
	terrain.reset_query_metrics()
	check(not skill.strike_one(Vector3.ZERO,3.0,0.0) and terrain.get_query_metrics().ray_requests == 0, "cheap invalid attack qualification precedes physics")
	check(skill.strike_one(Vector3.ZERO,3.0,7.0) and second.health == 93.0, "example uses public candidates, shared ray and real damage")
	var requests: int = terrain.get_query_metrics().ray_requests
	check(not skill.strike_one(Vector3.ZERO,3.0,7.0) and terrain.get_query_metrics().ray_requests == requests, "cooldown prevents even an extra ray query")
	var generation := session.get_combat_generation()
	session.set_combat_frozen(true)
	skill.advance(10.0)
	check(not skill.strike_one(Vector3.ZERO,3.0,7.0) and second.health == 93.0, "freeze blocks attack and cooldown advancement")
	check(session.get_combat_generation() == generation, "freezing does not end the current attack generation")
	session.set_combat_frozen(false)
	check(not skill.strike_one(Vector3.ZERO,3.0,7.0), "resume does not consume frozen time")
	skill.advance(0.5)
	var blocker := wall(Vector3(-0.5,0,0),Vector3(0.02,2,2))
	blocker.force_update_transform()
	check(not skill.strike_one(Vector3.ZERO,3.0,7.0) and second.health == 93.0, "example cannot damage through a new wall")
	blocker.free()
	var reentrant: Array[bool] = []
	var callback := func(_event): reentrant.append(skill.strike_one(Vector3.ZERO,3.0,7.0))
	second.damaged.connect(callback)
	check(skill.strike_one(Vector3.ZERO,3.0,7.0) and second.health == 86.0 and reentrant == [false], "damage callbacks cannot reenter an unreserved cooldown")
	second.damaged.disconnect(callback)
	var removed_before_callback: Array[bool] = []
	second.defeated.connect(func(_actor): removed_before_callback.append(not spatial._entries.has(second)))
	second.take_damage(1000)
	check(removed_before_callback == [true], "inherited death removes spatial state before lifecycle callbacks")
	actors.erase(second)
	first.cancel()
	first.commit_spatial_state()
	check(not spatial._entries.has(first), "inherited cancellation removes spatial state immediately")
	actors.erase(first)
	skill.cancel_current()
	skill.free()
	terrain.query_diagnostics_enabled = false

func run() -> void:
	world = Node3D.new()
	terrain = Terrain.new()
	terrain.data = TerrainData.new()
	terrain.data.size = Vector2i.ZERO
	terrain.data.resize(Vector2i(-10,-10),Vector2i(21,21))
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
	session = SESSION.new()
	session.name = "WavePrototype"
	session.player = player
	session.terrain = terrain
	session.phase = WavePrototype.Phase.BATTLE
	session._spatial_index = spatial
	world.add_child(session)
	await settle()
	rebuild()
	await obstacle_api_checks()
	lifecycle_and_examples()
	await settle()
	var floor := terrain.ground_collision_body()
	terrain.prepare_obstacle_shape_change((floor.get_child(0) as CollisionShape3D).shape)
	check(terrain.ground_collision_body() == null and not is_instance_valid(terrain._obstacle_field._support), "native floor preparation revokes both flat support and ray bounds")
	terrain.data.changed.emit()
	await settle()
	check(terrain.ground_collision_body() != null, "only a terrain generator rebuild restores verified floor qualification")
	terrain.prepare_obstacle_change(terrain.ground_collision_body())
	check(terrain.ground_collision_body() == null, "body-owner edits also revoke verified floor qualification before mutation")
	var generation := session.get_combat_generation()
	session._cleanup_attacks()
	check(session.get_combat_generation() != generation, "attack-root cleanup advances the public generation token")
	world.queue_free()
	await settle()
	print("COMBAT_EXTENSION_FRAMEWORK ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
