extends SceneTree

const SUITE := preload("res://tests/test_pursuit_tree_workspace.gd")
var checks := 0
var failures: Array[String] = []
var world: Node3D
var terrain: Terrain
var path: TerrainPath

# The gate is test-only: requesting a field while this job is blocked proves
# the main thread takes its synchronous fallback instead of joining the task.
class GatedJob extends TerrainPath.TreeJob:
	var gate := Semaphore.new()
	func run() -> void:
		gate.wait()
		super.run()

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		if failures.size() < 12: push_error(message)

func settle(count := 4) -> void:
	for frame in count: await physics_frame

func finish_jobs() -> void:
	for frame in 180:
		TerrainPath._poll_prefetch()
		if TerrainPath._prefetch_task < 0 and TerrainPath._prefetch_pending.is_empty(): return
		await process_frame
	check(false, "Bounded background work finishes")

func configure_job(job: TerrainPath.TreeJob, goal: int) -> void:
	job.owner = path._prefetch_owner
	job.epoch = path._prefetch_epoch
	job.goal = goal
	job.offsets = path._prefetch_offsets
	job.edges = path._prefetch_edges
	job.lengths = path._prefetch_lengths
	job.enabled = path._prefetch_mask

func reference(goal: int) -> TerrainPath:
	var result := SUITE.ReferencePath.new()
	result.graph = path.graph
	result.data = path.data
	result._size = path._size
	result._cache_graph()
	result.fixed_goal = goal
	result._prepare_pursuit_field(Vector3.ZERO)
	return result

func compare(next: PackedInt32Array, distances: PackedFloat64Array, goal: int, label: String) -> void:
	var expected := reference(goal)
	for id in path.graph.get_point_ids():
		check((next[id] >= 0) == expected._field_has(id), label + " membership %d" % id)
		check(distances[id] == expected.reference_distances[id], label + " exact Float64 distance %d" % id)
		if expected._field_has(id): check(next[id] == expected._pursuit_next[id], label + " predecessor/tie %d" % id)
		if id % 31 == 0 and next[id] >= 0:
			var actual_route := PackedInt32Array([id])
			var expected_route := PackedInt32Array([id])
			while actual_route[-1] != goal and actual_route.size() <= next.size(): actual_route.append(next[actual_route[-1]])
			while expected_route[-1] != goal and expected_route.size() <= next.size(): expected_route.append(expected._pursuit_next[expected_route[-1]])
			check(actual_route.to_byte_array() == expected_route.to_byte_array(), label + " complete route %d" % id)

func request(goal: int) -> bool:
	path._goal_frame = -1
	path._pursuit_goal_id = -1
	return path._prepare_pursuit_field(path.graph.get_point_position(goal))

func oracle_checks() -> void:
	var ids := path.graph.get_point_ids()
	for goal in [ids[0], ids[ids.size() / 3], ids[ids.size() / 2], ids[-1]]:
		request(goal)
		var job := TerrainPath.TreeJob.new()
		configure_job(job, goal)
		job.run()
		compare(job.next, job.distances, goal, "worker kernel")
	var disabled := ids[ids.size() / 2]
	path.graph.set_point_disabled(disabled, true)
	# Even a disabled goal is seeded, matching the established field semantics.
	for goal in [ids[0], disabled]:
		request(goal)
		var job := TerrainPath.TreeJob.new()
		configure_job(job, goal)
		job.run()
		compare(job.next, job.distances, goal, "disabled kernel")
	path.graph.set_point_disabled(disabled, false)
	request(ids[0])

func async_checks() -> void:
	var ids := path.graph.get_point_ids()
	var goal := ids[ids.size() / 2]
	path._queue_tree(goal)
	await finish_jobs()
	var hits := path.prefetch_hits
	var builds := path.shared_field_builds
	check(request(goal), "Completed prediction serves current goal")
	check(path.prefetch_hits == hits + 1 and path.shared_field_builds == builds, "Completed exact result avoids synchronous build")
	compare(path._pursuit_dense, path._field_distances, goal, "background result")
	var cached := path._prefetched_tree(goal)
	check(cached != null, "Completed prediction remains bounded cache entry")
	var original_next := cached.next.duplicate()
	var original_distances := cached.distances.duplicate()
	path._pursuit_dense.fill(-1)
	path._field_distances.fill(INF)
	check(cached.next == original_next and cached.distances == original_distances, "Active field workspace never aliases completed cache")
	check(request(goal), "Cache survives later mutable workspace reuse")
	compare(path._pursuit_dense, path._field_distances, goal, "reused result")
	await finish_jobs()
	TerrainPath._forget_prefetch(path._prefetch_owner, false)
	# While the worker is deliberately unfinished, a real request must finish.
	var blocked := GatedJob.new()
	configure_job(blocked, ids[-1])
	TerrainPath._prefetch_pending.append(blocked)
	TerrainPath._connect_prefetch_poll()
	TerrainPath._poll_prefetch()
	hits = path.prefetch_hits
	builds = path.shared_field_builds
	check(request(blocked.goal), "Unfinished prediction falls back immediately")
	check(path.prefetch_hits == hits and path.shared_field_builds == builds + 1, "Fallback never waits for gated worker")
	compare(path._pursuit_dense, path._field_distances, blocked.goal, "unfinished fallback")
	blocked.gate.post()
	await finish_jobs()
	# A stale disabled snapshot cannot be adopted, even for a ready exact goal.
	goal = ids[ids.size() / 3]
	path._queue_tree(goal)
	await finish_jobs()
	path.graph.set_point_disabled(ids[ids.size() / 2], true)
	hits = path.prefetch_hits
	request(goal)
	check(path.prefetch_hits == hits, "Changed native disabled flags invalidate ready predictions")
	compare(path._pursuit_dense, path._field_distances, goal, "fresh disabled snapshot")
	path.graph.set_point_disabled(ids[ids.size() / 2], false)
	request(ids[0])
	await finish_jobs()

func invalidation_checks() -> void:
	var ids := path.graph.get_point_ids()
	var goal := ids[ids.size() / 2]
	path._queue_tree(goal)
	await finish_jobs()
	terrain.position.x += 0.125
	check(not path._can_prefetch(), "Transform change invalidates prediction generation")
	check(path._prefetched_tree(goal) == null, "Transform change clears completed results")
	terrain.position.x -= 0.125
	path.build(terrain, 0.28, [])
	request(goal)
	path._queue_tree(ids[-1])
	await finish_jobs()
	var epoch := path._prefetch_epoch
	terrain.data.emit_changed()
	check(path._prefetch_epoch > epoch and not path._prefetch_valid, "Resource signal invalidates frozen graph generation")
	path.build(terrain, 0.28, [])
	request(goal)
	path._queue_tree(ids[-1])
	await finish_jobs()
	epoch = path._prefetch_epoch
	path.build(terrain, 0.28, [])
	check(path._prefetch_epoch > epoch and path._prefetched_tree(ids[-1]) == null, "Rebuild cannot reuse an older graph result")
	request(goal)
	for id in ids:
		path._queue_tree(id)
	check(TerrainPath._prefetch_pending.size() <= TerrainPath.PREFETCH_QUEUE_LIMIT, "Pending queue is strictly bounded")
	await finish_jobs()
	check(TerrainPath._prefetch_results.size() <= TerrainPath.PREFETCH_RESULT_LIMIT, "Completed cache is strictly bounded")
	var owner := path._prefetch_owner
	path = null
	check(not TerrainPath._prefetch_owners.has(owner), "Releasing path removes owner without retaining scene Nodes")
	for job in TerrainPath._prefetch_results: check(job.owner != owner, "Released owner has no completed result")
	for job in TerrainPath._prefetch_pending: check(job.owner != owner, "Released owner has no pending task")
	await finish_jobs()
	# A running worker is allowed to outlive its scene/path; it contains no Nodes.
	path = TerrainPath.new()
	path.build(terrain, 0.28, [])
	request(goal)
	var blocked := GatedJob.new()
	configure_job(blocked, ids[-1])
	TerrainPath._prefetch_pending.append(blocked)
	TerrainPath._connect_prefetch_poll()
	TerrainPath._poll_prefetch()
	owner = path._prefetch_owner
	path = null
	check(not TerrainPath._prefetch_owners.has(owner), "Running task never retains its released path")
	blocked.gate.post()
	await finish_jobs()
	check(TerrainPath._prefetch_task < 0 and TerrainPath._prefetch_running == null, "Released running task is reaped without scene callbacks")
	for job in TerrainPath._prefetch_results: check(job.owner != owner, "Late completed result from released owner is discarded")

func run() -> void:
	world = Node3D.new()
	terrain = Terrain.new()
	terrain.data = TerrainData.new()
	terrain.data.size = Vector2i.ZERO
	terrain.data.resize(Vector2i(-2, -2), Vector2i(12, 12))
	world.add_child(terrain)
	root.add_child(world)
	current_scene = world
	await settle()
	path = TerrainPath.new()
	path.build(terrain, 0.28, [])
	oracle_checks()
	await async_checks()
	await invalidation_checks()
	await reload_checks()
	TerrainPath._shutdown_prefetch()
	world.queue_free()
	await settle()
	print("Pursuit tree prefetch: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func reload_checks() -> void:
	# Exercise real hot reload with an active, deliberately large packed-only job.
	# Only the resource's in-memory source changes; the project file is untouched.
	var script: GDScript = load("res://scripts/enemies/terrain_path.gd")
	var original := script.source_code
	path = TerrainPath.new()
	var count := 100000
	path._prefetch_mask.resize(count)
	path._prefetch_mask.fill(1)
	path._field_enabled = path._prefetch_mask.duplicate()
	path._prefetch_offsets.resize(count * 2)
	for id in count:
		path._prefetch_offsets[id * 2] = path._prefetch_edges.size()
		if id > 0:
			path._prefetch_edges.append(id - 1)
			path._prefetch_lengths.append(0.5)
		if id < count - 1:
			path._prefetch_edges.append(id + 1)
			path._prefetch_lengths.append(0.5)
		path._prefetch_offsets[id * 2 + 1] = 1 if id == 0 or id == count - 1 else 2
	path._queue_tree(0)
	var job := TerrainPath._prefetch_running
	var task := TerrainPath._prefetch_task
	var version := TerrainPath._prefetch_kernel_version
	check(not WorkerThreadPool.is_task_completed(task), "Reload probe overlaps an unfinished real worker")
	# An actual arithmetic change must invalidate old ready and running results.
	script.source_code = original.replace("var distance := cost + lengths[index]", "var distance := cost + lengths[index] * 2.0")
	check(script.reload(true) == OK, "TerrainPath hot reload preserves live instances")
	check(TerrainPath._prefetch_task == task and TerrainPath._prefetch_running == job and TerrainPath._prefetch_owners.has(path._prefetch_owner), "Hot reload preserves task handle, running job and owner registry")
	check(path._prefetched_tree(0) == null, "Reloaded algorithm refuses an older kernel result before adoption")
	check(TerrainPath._prefetch_kernel_version > version, "Algorithm source change advances worker generation")
	await finish_jobs()
	check(job.next.size() == count and job.distances[-1] == (count - 1) * 0.5 and job.next[-1] == count - 2, "Frozen worker survives host hot reload with exact original route")
	check(TerrainPath._prefetch_results.is_empty() and TerrainPath._prefetch_task < 0, "Old kernel task is reaped and its result discarded")
	path._queue_tree(1)
	await finish_jobs()
	var updated := path._prefetched_tree(1)
	check(updated != null and updated.distances[-1] == float(count - 2), "Following worker uses the reloaded arithmetic")
	script.source_code = original
	check(script.reload(true) == OK, "Restore in-memory algorithm after reload oracle")
	check(path._prefetched_tree(1) == null, "Restored source also rejects modified ready results")
	path = null
