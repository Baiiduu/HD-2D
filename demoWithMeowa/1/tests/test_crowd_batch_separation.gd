extends "res://tests/test_enemy_crowd.gd"

const Planner = preload("res://scripts/combat/crowd_batch_planner.gd")

class TimedIndex extends "res://scripts/combat/crowd_batch_enemy_spatial_index.gd":
	var measure := false
	var force_usec := 0
	var update_usec := 0
	var force_calls := 0
	func separation(enemy: WaveEnemy, radius: float) -> Vector3:
		if not measure: return super.separation(enemy, radius)
		var began := Time.get_ticks_usec()
		var result := super.separation(enemy, radius)
		force_usec += Time.get_ticks_usec() - began
		force_calls += 1
		return result
	func update(enemy: WaveEnemy) -> void:
		if not measure:
			super.update(enemy)
			return
		var began := Time.get_ticks_usec()
		super.update(enemy)
		update_usec += Time.get_ticks_usec() - began
	func reset_metrics() -> void:
		super.reset_metrics()
		force_usec = 0
		update_usec = 0
		force_calls = 0

var probe := TimedIndex.new()
var player: Player
var results: Array[Dictionary] = []
var proof_only := false
var oracle_only := false
var warmup := 240
var samples := 240
var output := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--proof-only": proof_only = true
		elif argument == "--oracle-only": oracle_only = true
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--warmup="): warmup = maxi(1, int(argument.trim_prefix("--warmup=")))
		elif argument.begins_with("--samples="): samples = maxi(1, int(argument.trim_prefix("--samples=")))
	create_timer(180.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func same_snapshot_oracle() -> void:
	var planner := Planner.new()
	planner.diagnostics_enabled = true
	var random := RandomNumberGenerator.new()
	random.seed = 20261016
	for count in [2, 7, 128, 160]:
		for scenario in 5:
			var positions := PackedVector3Array()
			var ids := PackedInt64Array()
			var active := PackedByteArray()
			var spacing := PackedFloat64Array()
			var bodies := PackedFloat64Array()
			var cells: Dictionary = {}
			for slot in count:
				var point := Vector3(random.randf_range(-5, 5), random.randf_range(-0.4, 0.4), random.randf_range(-5, 5))
				if scenario == 1: point = Vector3((slot % 16 - 7.5) * 0.43, 0.02, (slot / 16) * 0.43)
				elif scenario == 2 and slot < 8: point = Vector3.ZERO
				elif scenario == 3 and slot % 3 == 0: point.y = 4.0
				var body := random.randf_range(0.12, 0.65)
				var space := maxf(random.randf_range(0.4, 3.2), body * 2.1)
				positions.append(point)
				ids.append(7100001 + slot * 103)
				active.append(0 if scenario == 4 and slot % 7 == 0 else 1)
				spacing.append(space)
				bodies.append(body)
				var key := Vector2i(floori(point.x), floori(point.z))
				if not cells.has(key): cells[key] = []
				cells[key].append(slot)
			var forces := planner.plan(cells, positions, ids, active, spacing, bodies, 1.0)
			var force_sum := Vector3.ZERO
			for a in count:
				var expected := Vector3.ZERO
				if active[a] != 0:
					for b in count:
						if b == a or active[b] == 0: continue
						expected += WaveEnemySpatialIndex.crowd_pair_force(positions[a] - positions[b], (spacing[a] + spacing[b]) * 0.5, bodies[a] + bodies[b], ids[a], ids[b])
				var tolerance := maxf(0.00002, expected.length() * 0.000003)
				check(forces[a].distance_to(expected) <= tolerance, "same-snapshot original force, count=%d scenario=%d slot=%d" % [count, scenario, a])
				force_sum += forces[a]
			check(force_sum.length() < 0.003, "pair scatter remains antisymmetric within float accumulation tolerance")
			check(planner.candidate_pairs <= count * (count - 1) / 2, "every unordered pair is visited at most once")
	print("BATCH_SNAPSHOT_ORACLE ", checks, " checks, ", failures, " failures")

func setup_world() -> void:
	probe.diagnostics_enabled = true
	index = probe
	world = Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(60, 0.2, 60)
	collision.shape = shape
	collision.position.y = -0.1
	floor_body.add_child(collision)
	world.add_child(floor_body)
	player = Player.new()
	var visual := Sprite3D.new()
	visual.name = "Sprite"
	player.add_child(visual)
	capsule(player, 0.24, 1.06592)
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.crowd_clearance_distance = 0.12
	target = player

func assert_live_fallback(actor: WaveEnemy, message: String) -> void:
	var result := probe.separation(actor, actor.get_crowd_spacing())
	check(probe._fallback_frame == Engine.get_physics_frames(), message + " invalidates the rest of the current step")
	check(result.is_equal_approx(probe.legacy_separation(actor, actor.get_crowd_spacing())), message + " uses the current live legacy result")

func lifecycle_checks() -> void:
	probe.batch_enabled = true
	var a := mob(Vector3(0, 0.02, 2))
	var b := mob(Vector3(0.7, 0.02, 2))
	await physics_frame
	var expected := probe.legacy_separation(a, a.separation_radius)
	var actual := probe.separation(a, a.separation_radius)
	check(actual.is_equal_approx(expected), "first ordinary separation matches current position snapshot")
	check(probe.separation(b, b.separation_radius).is_equal_approx(-actual), "two ordinary actors share one antisymmetric plan")
	check(probe.batch_builds == 1, "one current-step plan serves all actors")
	b.position.x = 20.0
	probe.update(b)
	check(probe.separation(a, a.separation_radius) == actual, "position-only move/commit preserves the coherent same-step plan")
	check(probe.nearby(b.global_position, 0.1).has(b) and not probe.nearby(a.global_position, 1.0).has(b), "ordinary combat nearby queries immediately read the committed actual position")
	await physics_frame
	check(probe.separation(a, a.separation_radius).is_zero_approx(), "the next physics step never reuses previous forces")
	var c := mob(a.position + Vector3.RIGHT * 0.5)
	assert_live_fallback(a, "same-step spawn")
	await physics_frame
	probe.separation(a, a.separation_radius)
	probe.remove(c)
	assert_live_fallback(a, "same-step removal/death")
	probe.update(c)
	assert_live_fallback(a, "same-step slot reuse")
	await physics_frame
	probe.separation(a, a.separation_radius)
	c.separation_radius = 2.1
	probe.update(c)
	assert_live_fallback(a, "same-step spacing change")
	await physics_frame
	probe.separation(a, a.separation_radius)
	c.body_radius = 0.4
	probe.update(c)
	assert_live_fallback(a, "same-step body change")
	await physics_frame
	probe.separation(a, a.separation_radius)
	c.spawn_delay = 1.0
	probe.update(c)
	assert_live_fallback(a, "same-step warning activation change")
	await physics_frame
	probe.separation(a, a.separation_radius)
	var alternate := probe.separation(a, a.separation_radius * 2.0)
	check(alternate.is_equal_approx(probe.legacy_separation(a, a.separation_radius * 2.0)), "alternate radius keeps the original exact query")
	clear_mobs()
	check(probe._forces.is_empty() and probe._plan_frame == -1 and probe._fallback_frame == -1, "clear releases all plans and invalidation boundaries")
	probe.batch_enabled = false
	pair_checks()
	probe.batch_enabled = true
	# This pressure assertion is independent of the crowd algorithm: preserve
	# the same player clearance constraint on the force actually returned.
	a = mob(Vector3(0, 0.02, 0.77))
	mob(Vector3(0, 0.02, 1.35))
	await physics_frame
	var pressure := a._crowd_direction(Vector3.ZERO)
	var motion := a._personal_space_direction(pressure, a._personal_stop_distance(a.combat_stop_distance))
	check(pressure.z < 0.0 and motion.z >= -0.00001, "batch pressure retains the player's personal clearance under rear crowd pressure")
	clear_mobs()

func reset_actors(points: PackedVector3Array, batch: bool) -> void:
	probe.measure = false
	probe.batch_enabled = batch
	probe._reset_plan()
	player.position = Vector3.ZERO
	player.current_health = player.max_health
	player.crowd_clearance_distance = 0.12
	for number in enemies.size():
		var actor := enemies[number]
		actor.global_position = points[number]
		actor.velocity = Vector3.ZERO
		actor._route.clear()
		actor._route_clock = 0.0
		actor._waypoint = 0
		actor._look = Vector3.FORWARD
		actor._yield_side = 0.0
		actor._ground_moved = false
		probe.update(actor)

func execute_case(count: int, batch: bool, order: int, points: PackedVector3Array) -> Dictionary:
	reset_actors(points, batch)
	await step(warmup)
	probe.reset_metrics()
	probe.measure = true
	var step_times: Array[float] = []
	var nearest_player := INF
	for frame in samples:
		await physics_frame
		var began := Time.get_ticks_usec()
		for actor in enemies:
			actor._combat_tick(1.0 / 60.0)
			probe.update(actor)
		step_times.append(float(Time.get_ticks_usec() - began) / 1000.0)
		for actor in enemies:
			nearest_player = minf(nearest_player, TerrainPath.horizontal_distance(actor.global_position, player.global_position))
	probe.measure = false
	var result := density()
	var total := 0.0
	for value in step_times: total += value
	step_times.sort()
	result.merge({"count": count, "batch": batch, "order": order, "samples": samples,
		"full_step_ms": total / samples, "full_step_p95_ms": step_times[int(samples * 0.95)],
		"separation_ms_per_step": float(probe.force_usec) / 1000.0 / samples,
		"update_ms_per_step": float(probe.update_usec) / 1000.0 / samples,
		"force_calls": probe.force_calls, "legacy_candidates": probe.candidate_checks,
		"batch_builds": probe.batch_builds, "batch_queries": probe.batch_queries,
		"plan_candidate_pairs": probe.plan_candidate_pairs, "plan_accepted_pairs": probe.plan_accepted_pairs,
		"fallbacks": probe.fallback_calls, "minimum_player_distance": nearest_player})
	check(result.minimum > 0.45 and result.median > 0.6 and result.mean_target < 5.0, "128/160 preserves visible shoulder separation and a compact horde")
	check(nearest_player >= 0.755, "128/160 preserves personal clearance under continuous rear pressure")
	check(enemies.all(func(actor): return actor.global_position.is_finite() and actor.velocity.is_finite()), "real enemy movements remain finite")
	if batch:
		check(probe.batch_builds == samples and probe.fallback_calls == 0, "exactly one fresh plan per step without hidden legacy fallback")
	return result

func run() -> void:
	same_snapshot_oracle()
	if not oracle_only:
		setup_world()
		await lifecycle_checks()
		if not proof_only:
			for count in [128, 160]:
				var points := PackedVector3Array()
				for number in count:
					var point := Vector3((number % 16 - 7.5) * 0.85, 0.02, 4.0 + floorf(float(number) / 16) * 0.85)
					mob(point)
					points.append(point)
				var group: Array[Dictionary] = []
				for mode in [false, true, true, false]:
					var result := await execute_case(count, mode, group.size(), points)
					group.append(result)
					results.append(result)
				var old_median := (float(group[0].median) + float(group[3].median)) * 0.5
				var new_median := (float(group[1].median) + float(group[2].median)) * 0.5
				check(absf(new_median - old_median) < 0.1, "batch planning does not materially change settled crowd density")
				clear_mobs()
		world.queue_free()
		await process_frame
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify({"checks": checks, "failures": failures, "warmup": warmup, "samples": samples, "results": results}, "\t"))
	print("CROWD_BATCH_AUTHORITATIVE ", checks, " checks, ", failures, " failures; ", output)
	quit(1 if failures else 0)
