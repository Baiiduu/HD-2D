extends SceneTree

const WallOracle = preload("res://tests/fixtures/capsule_wall_intrusion_oracle.gd")

const BatchIndex = preload("res://scripts/combat/crowd_batch_enemy_spatial_index.gd")

## Full mixed controllers and physical gameplay, not an FPS benchmark.
## A common spawn-warning window gives both algorithms the same seeded birth plan.
const SEED := 12102026
const WALL_SKIN := 0.003
class EndPhysics extends Node:
	signal completed
	func _physics_process(_delta: float) -> void: completed.emit()

var counts: Array[int] = [128, 160]
var combine_native_chase := false
var output := ""
var checks := 0
var failures: Array[String] = []
var results: Array[Dictionary] = []
var world: Node3D
var wave: WavePrototype
var player: Player
var held_key := 0
var manual_attack_held := false
var stage := ""
var spawn_plan: Array[Dictionary] = []
var hits := 0
var flight_hits := 0
var deflections := 0
var max_raw_pair_distance := 0.0
var bad_contact_details := 0
var end_physics: EndPhysics
var case_population := 0
var case_batch := false
var case_tick := -1
var expected_finish := false
var active_case: Dictionary = {}

func write_progress() -> void:
	if output.is_empty(): return
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "purpose": "Full mixed controller behaviour; 3mm inner-capsule wall oracle, raw pair diagnostic only; never FPS or net performance", "results": results, "active_case": active_case}, "\t"))

func phase_changed(value: WavePrototype.Phase) -> void:
	var point := player.global_position if is_instance_valid(player) else Vector3.ZERO
	var event := {"batch_enabled": wave.batch_crowd_enabled, "native_chase_enabled": wave.native_chase_enabled, "phase": value, "tick": case_tick, "pf": Engine.get_physics_frames(), "expected_finish": expected_finish, "alive": wave.enemies.size(), "reason": wave.result_reason, "outcome": wave.outcome, "player": [point.x, point.y, point.z]}
	active_case.phase_events.append(event)
	if case_tick >= 0 and value != WavePrototype.Phase.BATTLE and not expected_finish and not active_case.has("first_unexpected_phase"):
		active_case.first_unexpected_phase = event.duplicate(true)
	write_progress()
	print("CASE_PHASE pop=%d batch=%s tick=%d pf=%d phase=%d expected=%s alive=%d reason=%s player=%s" % [case_population, case_batch, case_tick, Engine.get_physics_frames(), value, expected_finish, wave.enemies.size(), wave.result_reason, point])

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--native-chase": combine_native_chase = true
		elif argument.begins_with("--count="): counts.assign([argument.trim_prefix("--count=").to_int()])
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	create_timer(900.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func settle(ticks: int) -> void:
	for tick in ticks: await physics_frame

func key(value: int) -> void:
	if value == held_key: return
	for entry in [[held_key, false], [value, true]]:
		if entry[0] == 0: continue
		var event := InputEventKey.new()
		event.physical_keycode = entry[0]
		event.keycode = entry[0]
		event.pressed = entry[1]
		Input.parse_input_event(event)
	held_key = value

func manual_attack(value: bool) -> void:
	if manual_attack_held == value: return
	var event := InputEventAction.new()
	event.action = &"normal_attack"
	event.pressed = value
	Input.parse_input_event(event)
	manual_attack_held = value

func spawned(enemy: WaveEnemy) -> void:
	# 仅夹具在开测前冻结已生成成员；正式出生不再有预警等待。
	enemy.spawn_delay = 1000.0
	wave._spatial_index.update(enemy)
	var point := enemy.global_position
	spawn_plan.append({"type": String(enemy.definition.enemy_id), "position": [point.x, point.y, point.z]})
	enemy.damaged.connect(func(_event):
		hits += 1
		if stage == "flight": flight_hits += 1
	)

func histogram() -> Dictionary:
	var result := {}
	for enemy in wave.enemies:
		var id := String(enemy.definition.enemy_id)
		result[id] = int(result.get(id, 0)) + 1
	return result

func nearest_spacing() -> Dictionary:
	var values: Array[float] = []
	for enemy in wave.enemies:
		var distance := INF
		for other in wave.enemies:
			if enemy != other: distance = minf(distance, TerrainPath.horizontal_distance(enemy.global_position, other.global_position))
		values.append(distance)
	values.sort()
	if values.is_empty(): return {}
	return {"min": values[0], "p25": values[values.size() / 4], "median": values[values.size() / 2], "p75": values[values.size() * 3 / 4]}

func wall_contacts() -> int:
	var blocked := 0
	var space := world.get_world_3d().direct_space_state
	for enemy in wave.enemies:
		var collider := enemy.get_node_or_null("Collision") as CollisionShape3D
		var excluded: Array[RID] = enemy.navigation._query.exclude if enemy.navigation else []
		# The actual world/body is untouched. Only a temporary 3 mm inner
		# capsule is queried against this same live backend and wall mask.
		var probe := WallOracle.inspect(space, collider, excluded, WALL_SKIN)
		var raw: float = probe.raw_max_pair_distance
		max_raw_pair_distance = maxf(max_raw_pair_distance, raw)
		var deep_violation: bool = not probe.supported or probe.intrudes
		if deep_violation: blocked += 1
		# Keep the previous large raw contacts visible as diagnostics even when
		# the independently validated inner query correctly finds no intrusion.
		if not deep_violation and raw <= WALL_SKIN: continue
		var first := Vector3.ZERO
		var second := Vector3.ZERO
		var pairs: Array = probe.raw_pairs
		var largest := 0.0
		for pair in range(0, pairs.size(), 2):
			var a: Vector3 = pairs[pair]
			var b: Vector3 = pairs[pair + 1]
			var distance := a.distance_to(b)
			if distance > largest:
				largest = distance
				first = a
				second = b
		var objects: Array[String] = []
		for hit in probe.outer_hits:
			var object: Object = hit.collider
			objects.append(String(object.get_path()) if object is Node else str(object))
		var point := enemy.global_position
		var raw_direction := (second - first).normalized()
		active_case.wall_events.append({"tick": case_tick, "pf": Engine.get_physics_frames(), "stage": stage, "type": String(enemy.definition.enemy_id), "position": [point.x, point.y, point.z], "oracle_supported": probe.supported, "oracle_reason": probe.reason, "inner_epsilon_m": WALL_SKIN, "inner_3mm_violation": deep_violation, "raw_pair_distance": raw, "raw_pair_direction": [raw_direction.x, raw_direction.y, raw_direction.z], "pair_a": [first.x, first.y, first.z], "pair_b": [second.x, second.y, second.z], "objects": objects, "on_floor": enemy.is_on_floor(), "velocity": [enemy.velocity.x, enemy.velocity.y, enemy.velocity.z]})
		if bad_contact_details < 4:
			bad_contact_details += 1
			print("CASE_WALL_ORACLE pop=%d mode=%s tick=%d pf=%d type=%s at=%s raw_pair_m=%s inner_3mm_violation=%s supported=%s objects=%s" % [case_population, case_batch, case_tick, Engine.get_physics_frames(), enemy.definition.enemy_id, point, raw, deep_violation, probe.supported, objects])
	return blocked
func sample(tick: int, population: int) -> Dictionary:
	var controllers := wave.is_physics_processing() and player.is_physics_processing()
	for enemy in wave.enemies: controllers = controllers and enemy.is_physics_processing()
	var walls := wall_contacts()
	var spacing := nearest_spacing()
	var valid_spacing := not spacing.is_empty() and is_finite(float(spacing.median)) and float(spacing.median) > 0.0
	return {"tick": tick, "pf": Engine.get_physics_frames(), "stage": stage, "alive": wave.enemies.size(), "controllers": controllers, "battle": wave.phase == WavePrototype.Phase.BATTLE and not wave.combat_frozen, "phase": wave.phase, "reason": wave.result_reason, "wall_intrusions": walls, "max_raw_pair_distance": max_raw_pair_distance, "nearest_spacing": spacing, "spacing_valid": valid_spacing, "hits": hits, "flight_hits": flight_hits, "deflections": deflections, "player": [player.global_position.x, player.global_position.y, player.global_position.z]}

func aim_at_nearby_enemy() -> Vector3:
	var best: WaveEnemy = null
	var distance := INF
	var space := player.get_world_3d().direct_space_state
	for enemy in wave.enemies:
		var squared := enemy.global_position.distance_squared_to(player.global_position)
		if squared >= distance: continue
		var ray := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 0.4, enemy.global_position + Vector3.UP * 0.4, 1, [player.get_rid()])
		if not space.intersect_ray(ray).is_empty(): continue
		best = enemy
		distance = squared
	return (best.global_position - player.global_position).normalized() if best else Vector3.FORWARD

func cleanup() -> void:
	key(0)
	manual_attack(false)
	stage = ""
	expected_finish = true
	if is_instance_valid(wave): wave.retreat()
	if is_instance_valid(world): world.queue_free()
	await settle(4)

func run_case(population: int, batch: bool) -> Dictionary:
	case_population = population
	case_batch = batch
	case_tick = -1
	expected_finish = false
	hits = 0
	flight_hits = 0
	deflections = 0
	max_raw_pair_distance = 0.0
	bad_contact_details = 0
	spawn_plan = []
	active_case = {"population": population, "batch": batch, "native_chase": batch and combine_native_chase, "wall_oracle": "rigid_capsule_eroded_3mm_live_intersect", "tick": -1, "phase_events": [], "wall_events": [], "samples": [], "started_pf": Engine.get_physics_frames(), "complete": false}
	write_progress()
	print("CASE_BEGIN pop=%d batch=%s pf=%d" % [population, batch, Engine.get_physics_frames()])
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	wave = world.get_node("WavePrototype")
	# Instantiate the same adapter for A and B before any actor is born. Only its
	# bool differs; there is no remove/recreate or reconfigure of existing actors.
	var crowd_index := BatchIndex.new()
	crowd_index.batch_enabled = batch
	crowd_index.diagnostics_enabled = true
	wave._spatial_index = crowd_index
	wave.batch_crowd_enabled = batch
	wave.native_chase_enabled = batch and combine_native_chase
	wave.random_seed = SEED
	# Real spawning keeps running; spawned() freezes earlier members until setup ends.
	wave.population_rules = wave.population_rules.duplicate(true)
	wave.population_rules.simulation_mode = true
	wave.population_rules.simulation_enemy_count = population
	wave.population_rules.simulation_skills.clear()
	wave.enemy_spawned.connect(spawned)
	wave.phase_changed.connect(phase_changed)
	root.add_child(world)
	current_scene = world
	player = wave.player
	player.body_ricochet.crowd_deflected.connect(func(_point, _incoming, _outgoing): deflections += 1)
	await settle(20)
	check(wave.start_run(), "Formal mixed horde starts with zero damage and no skill-card gate")
	var center := wave.battle_area.get_center()
	player.global_position = wave._path.graph.get_point_position(wave._path.closest_point(Vector3(center.x, 0, center.y))) + Vector3.UP * 0.03
	player.velocity = Vector3.ZERO
	(player.movement_camera as FollowCamera).snap_to_target()
	var attempts := 0
	while wave.enemies.size() < population and wave.phase == WavePrototype.Phase.BATTLE and attempts < 3600:
		await physics_frame
		attempts += 1
	check(wave.phase == WavePrototype.Phase.BATTLE and wave.enemies.size() == population and wave._pending == 0 and histogram().size() >= 5 and wave.is_physics_processing() and wave.is_horde_simulation() and wave.combat_modifiers.damage_disabled, "Complete five-type mixed batch and real controller enter zero-damage simulation")
	if wave.enemies.size() != population:
		var failed := {"population": population, "batch": batch, "spawn_plan": spawn_plan.duplicate(true), "error": "incomplete spawn"}
		active_case.merge(failed, true)
		write_progress()
		print("CASE_END pop=%d batch=%s tick=-1 phase=%d reason=%s incomplete spawn" % [population, batch, wave.phase, wave.result_reason])
		await cleanup()
		return failed
	var switches := wave._path.native_chase_enabled == (batch and combine_native_chase)
	for path: TerrainPath in wave._paths_by_radius.values():
		switches = switches and path.native_chase_enabled == (batch and combine_native_chase)
	check(switches and wave._spatial_index == crowd_index and crowd_index.batch_enabled == batch, "All body radii inherit the requested route mode; A has both switches OFF")
	for enemy in wave.enemies:
		enemy.spawn_delay = 0.0
		wave._spatial_index.update(enemy)
	var health_start := player.current_health
	var samples: Array[Dictionary] = []
	active_case.samples = samples
	active_case.spawn_plan = spawn_plan.duplicate(true)
	crowd_index.reset_metrics()
	var first_pf := Engine.get_physics_frames()
	var charge := false
	var released := false
	var flying_ticks := 0
	for tick in 600:
		case_tick = tick
		active_case.tick = tick
		stage = "stand" if tick < 240 else ("walk" if tick < 420 else ("charge" if tick < 480 else "flight"))
		if tick == 0: manual_attack(true)
		if tick >= 240 and tick < 420: key([KEY_D, KEY_S, KEY_A, KEY_W][((tick - 240) / 45) % 4])
		if tick == 420:
			key(0)
			manual_attack(false)
			charge = player.body_ricochet.begin_charge(aim_at_nearby_enemy())
		if tick == 480: released = player.body_ricochet.release_charge()
		# Sampling after a render frame can skip several catch-up physics steps.
		# The final-priority hook advances input exactly once per actual physics step.
		await end_physics.completed
		if player.body_ricochet.flying: flying_ticks += 1
		if tick % 15 == 0:
			samples.append(sample(tick, population))
			write_progress()
		if wave.phase != WavePrototype.Phase.BATTLE:
			if tick % 15 != 0: samples.append(sample(tick, population))
			write_progress()
			break
	var integrity := {"controllers": true, "population": true, "walls": true, "spacing": true}
	for value in samples:
		integrity.controllers = integrity.controllers and value.controllers and value.battle
		integrity.population = integrity.population and int(value.alive) == population
		integrity.walls = integrity.walls and int(value.wall_intrusions) == 0
		integrity.spacing = integrity.spacing and value.spacing_valid
	var actual_steps := Engine.get_physics_frames() - first_pf + 1
	integrity.controllers = integrity.controllers and actual_steps == case_tick + 1
	check(actual_steps == 600, "Exactly 600 real physics steps reach the final-priority hook")
	if batch: check(crowd_index.batch_builds == actual_steps and crowd_index.fallback_calls == 0, "Every mixed physics step builds one fresh ordinary plan without hidden fallback")
	check(integrity.controllers and integrity.population and integrity.walls and integrity.spacing, "Every 15-tick mixed diagnostic preserves controllers/alive/3mm walls/full spacing: " + JSON.stringify(integrity))
	check(charge and released and flying_ticks > 0 and deflections > 0 and flight_hits > 0, "Real charge/release retains crowd curvature and flight sword hits")
	check(hits > 0 and wave.kills == 0 and is_equal_approx(player.current_health, health_start) and not player.ricochet_rules.enemy_push_enabled, "Zero-damage feedback, complete population and confirmed no-push ricochet remain intact")
	var result := {"population": population, "batch": batch, "seed": SEED, "spawn_plan": spawn_plan.duplicate(true), "types": histogram(), "samples": samples, "hits": hits, "flight_hits": flight_hits, "deflections": deflections, "flying_ticks": flying_ticks, "health_start": health_start, "health_end": player.current_health, "kills": wave.kills, "phase": wave.phase, "reason": wave.result_reason, "outcome": wave.outcome, "max_raw_pair_distance_m": max_raw_pair_distance, "controller_enabled": wave.is_physics_processing(), "physics_steps": actual_steps, "complete": true}
	active_case.merge(result, true)
	active_case.batch_stats = {"builds": crowd_index.batch_builds, "queries": crowd_index.batch_queries, "fallbacks": crowd_index.fallback_calls, "candidate_pairs": crowd_index.plan_candidate_pairs, "accepted_pairs": crowd_index.plan_accepted_pairs}
	result = active_case
	write_progress()
	print("CASE_END pop=%d batch=%s tick=%d pf_steps=%d phase=%d reason=%s raw_max_pair=%s" % [population, batch, case_tick, result.physics_steps, wave.phase, wave.result_reason, max_raw_pair_distance])
	await cleanup()
	return result

func density(samples: Array) -> float:
	var values: Array[float] = []
	for value in samples:
		if value.stage == "stand" and int(value.tick) >= 120: values.append(float(value.nearest_spacing.median))
	values.sort()
	return values[values.size() / 2] if not values.is_empty() else NAN

func run() -> void:
	Engine.max_fps = 60
	end_physics = EndPhysics.new()
	end_physics.process_physics_priority = 1000000
	root.add_child(end_physics)
	for population in counts:
		var before := await run_case(population, false)
		results.append(before)
		write_progress()
		var after := await run_case(population, true)
		results.append(after)
		write_progress()
		check(before.spawn_plan == after.spawn_plan, "Legacy/batch use the exact same ordered seeded mixed births")
		if before.has("samples") and after.has("samples"):
			var old_spacing := density(before.samples)
			var new_spacing := density(after.samples)
			check(is_finite(old_spacing) and is_finite(new_spacing) and absf(new_spacing - old_spacing) <= 0.1, "Settled mixed crowd median spacing stays within 10cm")
	write_progress()
	print("Batch crowd mixed world: %d checks, %d failures" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)
