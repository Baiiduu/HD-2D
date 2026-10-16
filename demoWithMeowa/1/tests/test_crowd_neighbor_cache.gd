extends "res://tests/test_crowd_batch_separation.gd"

## Small functional proofs only: deliberately excludes the inherited timing
## and 128/160-actor branches. The oracle uses the original all-pairs formula.
class Snapshot extends RefCounted:
	var positions := PackedVector3Array()
	var ids := PackedInt64Array()
	var active := PackedByteArray()
	var spacing := PackedFloat64Array()
	var bodies := PackedFloat64Array()
	var revision := 0
	var cells: Dictionary = {}
	func add(point: Vector3, body := 0.2, space := 1.0, enabled := true) -> void:
		positions.append(point)
		ids.append(7100001 + positions.size() * 103)
		active.append(1 if enabled else 0)
		spacing.append(maxf(space, body * 2.1))
		bodies.append(body)
		revision += 1
	func plan(planner: RefCounted, cell_size := 1.0, versioned := true) -> PackedVector3Array:
		cells.clear()
		for slot in positions.size():
			var point := positions[slot]
			var key := Vector2i(floori(point.x / cell_size), floori(point.z / cell_size))
			if not cells.has(key): cells[key] = []
			cells[key].append(slot)
		return planner.plan(cells, positions, ids, active, spacing, bodies, cell_size, revision if versioned else -1)

func compare_oracle(snapshot: Snapshot, forces: PackedVector3Array, context: String) -> void:
	for a in snapshot.positions.size():
		var expected := Vector3.ZERO
		if snapshot.active[a] != 0:
			for b in snapshot.positions.size():
				if a == b or snapshot.active[b] == 0: continue
				expected += WaveEnemySpatialIndex.crowd_pair_force(snapshot.positions[a] - snapshot.positions[b],
					(snapshot.spacing[a] + snapshot.spacing[b]) * 0.5, snapshot.bodies[a] + snapshot.bodies[b], snapshot.ids[a], snapshot.ids[b])
		check(forces[a].distance_to(expected) <= maxf(0.00002, expected.length() * 0.000003), "%s slot %d matches original exact force" % [context, a])

func boundary_checks() -> void:
	var planner := Planner.new()
	planner.diagnostics_enabled = true
	var snapshot := Snapshot.new()
	snapshot.add(Vector3(-0.05, 0, 0))
	snapshot.add(Vector3(1.12, 0, 0))
	var forces := snapshot.plan(planner)
	compare_oracle(snapshot, forces, "initial expanded list")
	check(planner.neighbors_rebuilt and planner._pairs.size() == 2 and forces[0].is_zero_approx(), "the buffer retains a pair outside the actual interaction radius")
	snapshot.positions[0].x += 0.09
	snapshot.positions[1].x -= 0.09
	forces = snapshot.plan(planner)
	compare_oracle(snapshot, forces, "crossing cell boundaries")
	check(not planner.neighbors_rebuilt and planner.search_pairs == 0 and planner.cell_pairs == 0 and not forces[0].is_zero_approx(), "opposing movement and cell crossing reuse the list with fresh nonzero forces")
	snapshot.positions[1].y = 2.0
	forces = snapshot.plan(planner)
	check(not planner.neighbors_rebuilt and forces[0].is_zero_approx(), "current height immediately removes contact without a list rebuild")
	snapshot.positions[1].y = 0.0
	forces = snapshot.plan(planner)
	compare_oracle(snapshot, forces, "returning to contact height")
	check(not planner.neighbors_rebuilt and not forces[0].is_zero_approx(), "returning from a jump immediately restores contact")
	snapshot.positions[0].x += 0.05
	snapshot.plan(planner)
	check(not planner.neighbors_rebuilt, "0.14 metres of accumulated displacement remains inside the half buffer")
	snapshot.positions[0].x += 0.011
	compare_oracle(snapshot, snapshot.plan(planner), "accumulated displacement")
	check(planner.neighbors_rebuilt, "displacement is measured from list construction, not the last step")

	planner.clear()
	snapshot = Snapshot.new()
	snapshot.add(Vector3(-1.0, 0, 0))
	snapshot.add(Vector3(0.301, 0, 0))
	snapshot.plan(planner)
	check(planner._pairs.is_empty(), "a pair beyond spacing plus the buffer can be omitted")
	snapshot.positions[0].x += 0.1499
	snapshot.positions[1].x -= 0.1499
	forces = snapshot.plan(planner)
	compare_oracle(snapshot, forces, "opposing movement just inside the budget")
	check(not planner.neighbors_rebuilt and forces[0].is_zero_approx(), "an omitted pair cannot enter contact within the displacement budget")
	snapshot.positions[0].x += 0.0007
	snapshot.positions[1].x -= 0.0007
	forces = snapshot.plan(planner)
	compare_oracle(snapshot, forces, "omitted pair enters contact")
	check(planner.neighbors_rebuilt and not forces[0].is_zero_approx(), "rebuilding discovers the previously omitted pair before it contacts")
	snapshot.positions[0] = snapshot.positions[1] + Vector3(0.3, 0, 0.1)
	compare_oracle(snapshot, snapshot.plan(planner), "teleport")
	check(planner.neighbors_rebuilt, "large instantaneous motion immediately rebuilds the list")
	snapshot.plan(planner, 0.5)
	check(planner.neighbors_rebuilt, "changing the grid cell size rebuilds")
	snapshot.plan(planner, 0.5, false)
	snapshot.plan(planner, 0.5, false)
	check(planner.neighbors_rebuilt, "unversioned callers never reuse unchecked metadata")

	planner.clear()
	snapshot = Snapshot.new()
	snapshot.add(Vector3.ZERO, 0.12, 0.5)
	snapshot.add(Vector3.RIGHT, 0.12, 1.500000002)
	forces = snapshot.plan(planner)
	check(forces[0].x != 0.0, "the cached list preserves float64 spacing just inside its true interaction radius")
	compare_oracle(snapshot, snapshot.plan(planner), "float64 spacing during reuse")
	snapshot.bodies[0] = 0.1249999999
	snapshot.bodies[1] = 0.25
	snapshot.spacing[0] = 0.8
	snapshot.spacing[1] = 0.8
	snapshot.positions[1] = Vector3(0.2, 0.375, 0)
	snapshot.revision += 1
	forces = snapshot.plan(planner)
	check(forces[0] == Vector3.ZERO, "float64 body radii preserve the exact height exclusion boundary")
	snapshot.bodies[0] = 0.1250000001
	snapshot.revision += 1
	forces = snapshot.plan(planner)
	check(forces[0].x != 0.0, "a sub-float32 body radius change rebuilds and restores height contact")
	compare_oracle(snapshot, forces, "float64 body mutation")

func mixed_snapshot_checks() -> void:
	var planner := Planner.new()
	var random := RandomNumberGenerator.new()
	random.seed = 2026101603
	var reused := 0
	var rebuilt := 0
	for scenario in 5:
		planner.clear()
		var snapshot := Snapshot.new()
		for slot in 12:
			var point := Vector3(random.randf_range(-1.6, 1.6), 0, random.randf_range(-1.6, 1.6))
			if scenario == 1 and slot < 3: point = Vector3.ZERO
			if scenario == 2 and slot % 2 == 0: point.y = 2.0
			snapshot.add(point, random.randf_range(0.12, 0.55), random.randf_range(0.4, 2.1), scenario != 3 or slot % 3 != 0)
		for frame in 24:
			for slot in snapshot.positions.size():
				# Small per-step motion, but cumulative displacement crosses the
				# budget. Height deliberately changes without a metadata revision.
				snapshot.positions[slot] += Vector3(0.018 * (1 if slot % 2 else -1), 0, 0.01)
			if frame == 4: snapshot.positions[2].y = 0.0
			if frame == 6:
				snapshot.spacing[1] += 0.7000000001
				snapshot.revision += 1
			elif frame == 11:
				snapshot.bodies[2] += 0.03
				snapshot.revision += 1
			elif frame == 12:
				snapshot.active[3] = 0
				snapshot.revision += 1
			elif frame == 13:
				snapshot.ids[3] += 99
				snapshot.active[3] = 1
				snapshot.revision += 1
			elif frame == 15:
				snapshot.positions[5] += Vector3(12, 0, 8)
			elif frame == 17:
				snapshot.add(Vector3(-0.1, 0, -0.2), 0.4, 1.2)
			compare_oracle(snapshot, snapshot.plan(planner), "mixed scenario %d step %d" % [scenario, frame])
			if planner.neighbors_rebuilt: rebuilt += 1
			else: reused += 1
			if frame in [0, 6, 11, 12, 13, 15, 17]:
				check(planner.neighbors_rebuilt, "membership, ID, activation, body and spacing changes invalidate the list")
	check(rebuilt > 0 and reused > 0, "the original force oracle covers both rebuilt and reused lists")
	print("NEIGHBOR_SNAPSHOT_PROOF rebuilt=", rebuilt, " reused=", reused, "; at most 13 array entries, no timing samples")

func index_reuse_checks() -> void:
	probe.batch_enabled = true
	var a := mob(Vector3(0, 0.02, 2))
	var b := mob(Vector3(0.7, 0.02, 2))
	await physics_frame
	var first := probe.separation(a, a.separation_radius)
	check(probe.neighbor_rebuilds == 1, "the live index constructs its first neighbor list")
	for frame in 6:
		await physics_frame
		b.position.x -= 0.01
		var revision := probe._crowd_revision
		probe.update(b)
		check(probe._crowd_revision == revision, "ordinary motion keeps the metadata revision")
		var actual := probe.separation(a, a.separation_radius)
		check(actual.is_equal_approx(probe.legacy_separation(a, a.separation_radius)) and actual != first, "each real physics step recalculates forces at the current positions")
		check(probe.separation(b, b.separation_radius).is_equal_approx(-actual), "the shared plan remains antisymmetric")
	check(probe.neighbor_rebuilds == 1 and probe.neighbor_reuses == 6 and probe.batch_builds == 7, "seven fresh force plans need only one grid neighbor search in this selected small-motion case")
	check(probe.fallback_calls == 0, "ordinary reuse does not silently fall back to per-enemy search")
	await physics_frame
	b.position = a.position + Vector3(0.4, 0, 0)
	probe.update(b)
	probe.separation(a, a.separation_radius)
	check(probe.neighbor_rebuilds == 2, "a live teleport rebuilds before the next plan")
	var revision := probe._crowd_revision
	b.separation_radius += 0.2
	probe.update(b)
	check(probe._crowd_revision > revision, "spacing changes advance the native index revision")
	assert_live_fallback(a, "metadata change after a reused plan")
	await physics_frame
	probe.separation(a, a.separation_radius)
	check(probe.neighbor_rebuilds == 3, "a metadata change rebuilds at the next step")
	probe.remove(b)
	assert_live_fallback(a, "removal after a cached plan")
	probe.update(b)
	await physics_frame
	probe.separation(a, a.separation_radius)
	check(probe.neighbor_rebuilds == 4, "same-slot reactivation rebuilds without stale pairs")
	clear_mobs()
	check(probe._planner._pairs.is_empty() and probe._planner._reference_positions.is_empty(), "clear releases all candidate storage")
	# The new actor may occupy the same integer slot as one from the old run.
	a = mob(Vector3(0, 0.02, 2))
	await physics_frame
	check(probe.separation(a, a.separation_radius).is_zero_approx() and probe.neighbor_rebuilds == 1, "new run starts with fresh membership and no old force")
	clear_mobs()

func run() -> void:
	boundary_checks()
	mixed_snapshot_checks()
	setup_world()
	await lifecycle_checks()
	await index_reuse_checks()
	world.queue_free()
	await process_frame
	print("CROWD_NEIGHBOR_CACHE ", checks, " checks, ", failures, " failures; functional only")
	quit(1 if failures else 0)
