extends "res://tests/test_creature_flat_chase.gd"

const BatchIndex = preload("res://scripts/combat/crowd_batch_enemy_spatial_index.gd")

class RouteProbe extends TerrainPath:
	var calls := 0
	func chase_route(from: Vector3, goal: Vector3, lookahead := 4.0) -> PackedVector3Array:
		calls += 1
		return super.chase_route(from, goal, lookahead)

class SlimeProbe extends SlimeEnemy:
	var decisions := 0
	var movements := 0
	var contacts := 0
	var decision_frames: Array[int] = []
	func _crowd_direction(desired: Vector3) -> Vector3:
		decisions += 1
		decision_frames.append(Engine.get_physics_frames())
		return super._crowd_direction(desired)
	func _move_combat_body(delta: float) -> void:
		movements += 1
		super._move_combat_body(delta)
	func _combat_contact() -> void:
		contacts += 1
		super._combat_contact()

class PotProbe extends PotBroodEnemy:
	var decisions := 0
	var movements := 0
	var contacts := 0
	var decision_frames: Array[int] = []
	func _crowd_direction(desired: Vector3) -> Vector3:
		decisions += 1
		decision_frames.append(Engine.get_physics_frames())
		return super._crowd_direction(desired)
	func _move_combat_body(delta: float) -> void:
		movements += 1
		super._move_combat_body(delta)
	func _touch_player() -> void:
		contacts += 1
		super._touch_player()

var running := true
var damage_calls := 0

func probe_actor(id: String, point: Vector3, script: Script) -> SlimeEnemy:
	var definition: WaveEnemyDefinition = load("res://data/enemies/%s.tres" % id)
	var actor := definition.scene.instantiate() as SlimeEnemy
	actor.set_script(script)
	actor.configure_wave({"player":player,"terrain":terrain,"camera":null,"navigation":path,"attack_root":world,
		"damage_player":func(_damage): damage_calls += 1,"can_damage_player":func(_damage): return true,
		"request_spawn":Callable(),"spatial_index":spatial,"combat_active":func(): return running}, definition, 0.0)
	world.add_child(actor)
	actor.set_physics_process(false)
	actor.set_process(false)
	actors.append(actor)
	reset_actor(actor, point, true)
	return actor

func tick(count: int) -> void:
	for step in count:
		await physics_frame
		for actor in actors: actor._physics_process(DELTA)

func reset_counts() -> void:
	for actor in actors:
		actor.set("decisions", 0)
		actor.set("movements", 0)
		actor.set("contacts", 0)
		actor.get("decision_frames").clear()

func held_step(actor: SlimeEnemy) -> void:
	await physics_frame
	while spatial.call("pursuit_due", actor):
		for member in actors: member._physics_process(DELTA)
		await physics_frame

func cadence_checks() -> void:
	for index in 4:
		probe_actor("wave_slime" if index % 2 == 0 else "pot_brood", Vector3(-4,0.001,index * 1.2 - 1.8), SlimeProbe if index % 2 == 0 else PotProbe)
	await tick(4)
	reset_counts()
	await tick(8)
	for actor in actors: check(actor.get("decisions") == 8, "Small crowds keep ordinary decisions on every physics step")
	spatial.set("pursuit_throttle_threshold", 4)
	await tick(4)
	reset_counts()
	await tick(12)
	var per_frame := {}
	for actor in actors:
		check(actor.get("decisions") == 6, "Each ordinary actor decides at 30Hz under the configured crowd threshold")
		check(actor.get("movements") == 12 and actor.get("contacts") == 12, "Movement, native wall checks and contact attack callbacks retain 60Hz")
		for frame: int in actor.get("decision_frames"): per_frame[frame] = int(per_frame.get(frame, 0)) + 1
	check(per_frame.size() == 12 and per_frame.values().all(func(count): return count == 2), "Stable index cohorts stagger half the actors onto each physics step")
	var actor := actors[0]
	actor._route_clock = 0.3
	var clock := actor._route_clock
	await tick(2)
	check(is_equal_approx(clock - actor._route_clock, DELTA * 2.0), "Route refresh clock consumes every ordinary movement step, including held-intent steps")
	actor.stun_remaining = DELTA * 2.0
	var decisions: int = actor.get("decisions")
	await tick(2)
	check(actor.stun_remaining == 0.0 and actor.get("decisions") == decisions, "Stun duration retains its original physics clock without ordinary planning")
	await tick(1)
	check(actor.get("decisions") == decisions + 1, "Resuming from stun cannot reuse the pre-stun steering")
	running = false
	var before := actor.global_position
	clock = actor._route_clock
	await tick(3)
	check(actor.global_position == before and actor._route_clock == clock, "Combat freeze leaves motion and decision clocks untouched")
	running = true
	decisions = actor.get("decisions")
	await tick(1)
	check(actor.get("decisions") == decisions + 1 and clock - actor._route_clock <= DELTA + 0.000001, "Resume refreshes stale intent without catching up frozen time")
	while actors.size() > 1:
		var removed: SlimeEnemy = actors.pop_back()
		removed.free()
	reset_counts()
	await tick(4)
	check(actor.get("decisions") == 4, "Falling below the live population threshold immediately restores every-step decisions")
	clear_actors()

func wall_and_contact_checks() -> void:
	var actor := probe_actor("wave_slime", Vector3(-3,0.001,0), SlimeProbe)
	spatial.set("pursuit_throttle_threshold", 1)
	actor.separation_strength = 0.0
	await tick(4)
	# Install a new wall on an actual held-intent step, not just a decision step.
	await held_step(actor)
	var before := actor.global_position
	var barrier := wall(before + Vector3(actor.body_radius + 0.015, 1.0, 0), Vector3(0.03,2.0,1.0))
	barrier.force_update_transform()
	var decisions: int = actor.get("decisions")
	actor._physics_process(DELTA)
	check(actor.get("decisions") == decisions, "The wall case exercises a skipped decision")
	check(actor.global_position.x <= barrier.global_position.x - actor.body_radius + 0.003, "Held steering still sweeps a same-step new thin wall with the real capsule")
	intact(actor, "throttled ordinary movement")
	barrier.free()
	player.global_position = actor.global_position + Vector3(0.7,0,0)
	actor.attack_damage = 1.0
	damage_calls = 0
	await tick(4)
	check(damage_calls == 4, "Actual contact damage checks still reach the original callback on all physics steps")
	clear_actors()

func partial_force_checks() -> void:
	player.position = Vector3(5,0,0)
	for index in 4: probe_actor("wave_slime", Vector3(-3 + index * 0.1,0.001,0), SlimeProbe)
	var batch := spatial as CrowdBatchEnemySpatialIndex
	batch.batch_enabled = true
	batch.diagnostics_enabled = true
	await physics_frame
	var frame := Engine.get_physics_frames()
	var due_count := 0
	for actor in actors:
		if not batch.call("pursuit_due", actor): continue
		due_count += 1
		var expected := batch.legacy_separation(actor, actor.separation_radius)
		var actual: Vector3 = batch.call("pursuit_separation", actor, actor.separation_radius)
		check(actual.distance_to(expected) < 0.00001, "Scheduled cohort force matches the live full-neighbor oracle")
	check(due_count == 2 and batch._plan_frame == frame and batch._planner.candidate_pairs == 5, "The shared planner omits pairs whose two endpoints both belong to the other cohort")
	var removed: SlimeEnemy = actors.pop_back()
	removed.free()
	for actor in actors:
		if not batch.call("pursuit_due", actor): continue
		var actual: Vector3 = batch.call("pursuit_separation", actor, actor.separation_radius)
		check(actual.distance_to(batch.legacy_separation(actor, actor.separation_radius)) < 0.00001, "Same-step death revokes the partial force plan and excludes the removed body")
	clear_actors()

func lifecycle_checks() -> void:
	player.position = Vector3(5,0,0)
	var actor := probe_actor("wave_slime", Vector3(-3,0.001,0), SlimeProbe)
	spatial.set("pursuit_throttle_threshold", 1)
	await tick(4)
	await held_step(actor)
	var decisions: int = actor.get("decisions")
	player.global_position = actor.global_position + Vector3(0.4,0,0)
	actor._physics_process(DELTA)
	check(actor.get("decisions") == decisions + 1 and actor._ordinary_intended.is_zero_approx() and actor.velocity.x <= 0.0, "Entering personal stopping space overrides held inward steering immediately")
	player.position = Vector3(5,0,0)
	await tick(4)
	await held_step(actor)
	decisions = actor.get("decisions")
	actor.position.z += 0.2
	actor.commit_spatial_state()
	actor._physics_process(DELTA)
	check(actor.get("decisions") == decisions + 1, "External teleport revokes old steering even on the other cohort's step")
	await tick(4)
	await held_step(actor)
	var replacement := RouteProbe.new()
	replacement.build(terrain, actor.body_radius, [player.get_rid()])
	actor.navigation = replacement
	actor._route_clock = 0.0
	decisions = actor.get("decisions")
	actor._physics_process(DELTA)
	check(actor.get("decisions") == decisions + 1 and replacement.calls == 1, "Replacing navigation replans through the current public path on the same held step")
	spatial.set("pursuit_throttle_threshold", 0)
	reset_counts()
	await tick(4)
	check(actor.get("decisions") == 4, "Disabling the map threshold immediately restores full-rate decisions")
	clear_actors()

func spacing_checks() -> void:
	player.position = Vector3(5,0,0)
	var actor := probe_actor("pot_brood", Vector3(-3,0.001,0), PotProbe) as CreatureEnemy
	spatial.set("pursuit_throttle_threshold", 1)
	for step in 4:
		await physics_frame
		actor._idle_motion(DELTA, true)
	reset_counts()
	var actual_steps := 0
	for step in 8:
		await physics_frame
		actor._idle_motion(DELTA, true)
		if actor._ordinary_last_step == Engine.get_physics_frames(): actual_steps += 1
	check(actor.get("decisions") == 4 and actual_steps == 8, "Standing crowd spacing decisions stagger while the body still moves on every step")
	reset_counts()
	for step in 4:
		await physics_frame
		actor._move_local(Vector3.LEFT, DELTA)
	check(actor.get("decisions") == 4, "Special local retreat keeps fresh avoidance on every physics step")
	clear_actors()

func special_checks() -> void:
	var leaf := creature("leaf_charger", Vector3(-4,0.001,3)) as LeafChargerEnemy
	spatial.set("pursuit_throttle_threshold", 1)
	leaf.combat_active = func(): return true
	leaf.rules = leaf.rules.duplicate()
	leaf.rules.charge_speed = 3.0
	leaf.rules.charge_distance = 4.0
	leaf.attack_phase = LeafChargerEnemy.AttackPhase.CHARGE
	leaf._charge_direction = Vector3.RIGHT
	leaf._charge_plane = 0.0
	leaf._charge_travel = 0.0
	for step in 8:
		await physics_frame
		leaf._physics_process(DELTA)
	check(absf(leaf._charge_travel - 8.0 * DELTA * 3.0) < 0.0001, "Locked-line charge movement keeps every original physics step")
	leaf.attack_phase = LeafChargerEnemy.AttackPhase.WINDUP
	leaf._phase_clock = 0.2
	for step in 4:
		await physics_frame
		leaf._physics_process(DELTA)
	check(absf(leaf._phase_clock - (0.2 - 4 * DELTA)) < 0.000001, "Special attack windup keeps its 60Hz countdown")
	clear_actors()

func run() -> void:
	spatial = BatchIndex.new()
	check(spatial.get("pursuit_throttle_threshold") != null, "Crowd decisions have a map-owned population threshold")
	var profile := load("res://data/combat/scenes/world/configuration.tres")
	check(profile.get("pursuit_throttle_threshold") == 80, "Formal World first enables the strategy at 80 living actors")
	if not failures.is_empty(): quit(1); return
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
	player.set_physics_process(false)
	player.set_process(false)
	player.position = Vector3(5,0,0)
	await settle()
	rebuild()
	await cadence_checks()
	player.position = Vector3(5,0,0)
	await wall_and_contact_checks()
	await partial_force_checks()
	await lifecycle_checks()
	await spacing_checks()
	await special_checks()
	world.queue_free()
	await settle()
	print("PURSUIT_CADENCE ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
