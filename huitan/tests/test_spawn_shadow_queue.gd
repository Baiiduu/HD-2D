extends SceneTree
## 无渲染、无怪物实例：验证预告属于生成队列而非已出生怪物。
var checks := 0
var failures: Array[String] = []

class Host extends RefCounted:
	var queue: WaveSpawnQueue
	var alive := 0
	var generation := 1
	var frozen := false
	var prepares := 0
	var spawns := 0
	var syncs := 0
	var blocked := 0
	var errors := 0
	var valid_point := true
	var on_prepare: Callable
	var limit := 3
	var roster := WaveEnemyRoster.new()
	var population := WavePopulationRules.new()
	var spawned_points: Array[Vector3] = []
	func count() -> int: return alive
	func current(token: int) -> bool: return token == generation
	func is_frozen() -> bool: return frozen
	func synchronize() -> void: syncs += 1
	func changed() -> void: pass
	func notice() -> void: blocked += 1
	func fail() -> void: errors += 1
	func capacity(job: Dictionary) -> bool:
		return roster.can_fit_batch(queue.capacity_reservation(job), limit - alive, population)
	func prepare(job: Dictionary) -> bool:
		prepares += 1
		job.spawn_point = Vector3(prepares * 2, 0, 0)
		if on_prepare.is_valid(): on_prepare.call()
		return true
	func spawn(job: Dictionary) -> bool:
		if not valid_point: return false
		spawns += 1
		alive += 1
		spawned_points.append(job.spawn_point)
		queue.complete_member(job.batch, job.enemy)
		return true

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func run() -> void:
	var queue := WaveSpawnQueue.new()
	var ports := WaveSpawnQueue.Services.new()
	check("warning_seconds" in ports, "Queue exposes a pre-instantiation warning stage")
	if not failures.is_empty(): quit(1); return
	var host := Host.new()
	host.queue = queue
	host.population.max_population_cost = 20
	host.population.role_limits = PackedInt32Array([3, 3, 3, 3])
	ports.set("warning_seconds", 0.5)
	ports.set("prepare", host.prepare)
	ports.alive_count = host.count
	ports.has_capacity = host.capacity
	ports.spawn = host.spawn
	ports.synchronize = host.synchronize
	ports.current = host.current
	ports.frozen = host.is_frozen
	ports.changed = host.changed
	ports.blocked = host.notice
	ports.timed_out = host.fail
	ports.active_limit = host.limit
	ports.check_budget = 8
	ports.spawn_budget = 2
	var started: Array[int] = []
	var ended: Array[Vector2i] = []
	queue.connect("warning_started", func(job: Dictionary, _seconds: float): started.append(job.id))
	queue.connect("warning_finished", func(id: int, born: bool): ended.append(Vector2i(id, int(born))))
	var enemy := WaveEnemyDefinition.new()
	var members: Array[WaveEnemyDefinition] = [enemy, enemy, enemy, enemy]
	var single: Array[WaveEnemyDefinition] = [enemy]
	queue.enqueue(members, 0, 0.3, Vector3.INF, PackedStringArray(), 0, 0, 1)
	queue.process_due(0.29, host.generation, ports)
	check(host.prepares == 0, "Original scheduling is respected before the warning")
	queue.process_due(0.3, host.generation, ports)
	check(host.prepares == 2 and host.spawns == 0 and queue.jobs.size() == 4, "Warnings use the frame budget and keep every pending spawn registered")
	check(queue.prepared_jobs.size() == 2 and started.size() == 2, "Warnings reserve real slots before actors exist")
	queue.process_due(0.31, host.generation, ports)
	check(host.prepares == 3 and queue.prepared_jobs.size() == 3, "Concurrent singleton warnings cannot overbook the active limit")
	var syncs := host.syncs
	queue.process_due(0.4, host.generation, ports)
	check(host.syncs == syncs and host.spawns == 0, "Waiting warnings perform no position synchronization or early spawn")
	host.frozen = true
	queue.process_due(0.8, host.generation, ports)
	check(host.spawns == 0 and queue.prepared_jobs.size() == 3, "Freeze keeps warnings and their reservations unchanged")
	host.frozen = false
	queue.process_due(0.8, host.generation, ports)
	check(host.spawns == 2 and host.spawned_points == [Vector3(2, 0, 0), Vector3(4, 0, 0)], "Successful spawns consume exactly the warned positions within the spawn budget")
	check(ended.size() == 2 and ended[0].y == 1, "Successful warnings finish as visual tails")
	queue.process_due(0.82, host.generation, ports)
	check(host.spawns == 3 and queue.jobs.size() == 1, "A later due warning completes without admitting an unreserved fourth actor")
	queue.clear()
	host.alive = 0
	queue.enqueue(single, 1, 0, Vector3.INF, PackedStringArray(), 0, 0, 1)
	queue.process_due(1, host.generation, ports)
	var stale_point: Vector3 = queue.jobs[0].spawn_point
	host.valid_point = false
	queue.process_due(1.5, host.generation, ports)
	check(queue.prepared_jobs.is_empty() and not queue.jobs[0].has("spawn_point"), "An invalidated location cancels the old warning and reservation")
	check(ended[-1].y == 0 and host.blocked == 1, "Invalidated warnings disappear immediately and use normal retry bookkeeping")
	host.valid_point = true
	queue.process_due(1.9, host.generation, ports)
	check(queue.jobs[0].spawn_point != stale_point and host.spawns == 3, "A replacement location receives a fresh full warning")
	queue.process_due(2.39, host.generation, ports)
	check(host.spawns == 3, "Replanning cannot bypass the warning duration")
	queue.process_due(2.4, host.generation, ports)
	check(host.spawns == 4 and queue.prepared_jobs.is_empty(), "The newly warned location can eventually spawn")
	queue.clear()
	host.alive = 0
	queue.enqueue(members, 3, 0, Vector3.INF, PackedStringArray(), 0, 0, 3)
	queue.process_due(3, host.generation, ports)
	queue.process_due(3.01, host.generation, ports)
	check(queue.prepared_jobs.size() == 3, "Batch capacity includes prepared members only once")
	queue.clear()
	check(queue.jobs.is_empty() and queue.prepared_jobs.is_empty() and ended[-1].y == 0, "Retry/exit clears every warning, job and reservation")
	# Cost and role limits apply to warnings before real actors exist.
	enemy.population_cost = 2
	host.population.max_population_cost = 4
	host.population.role_limits[0] = 1
	queue.enqueue(members, 4, 0, Vector3.INF, PackedStringArray(), 0, 0, 1)
	queue.process_due(4, host.generation, ports)
	check(queue.prepared_jobs.size() == 1, "Per-role limits include pending singleton warnings")
	queue.clear()
	host.population.role_limits[0] = 3
	queue.enqueue(members, 5, 0, Vector3.INF, PackedStringArray(), 0, 0, 1)
	queue.process_due(5, host.generation, ports)
	queue.process_due(5.01, host.generation, ports)
	check(queue.prepared_jobs.size() == 2, "Population cost includes pending singleton warnings")
	queue.clear()
	host.population.max_population_cost = 20
	enemy.max_alive = 1
	queue.enqueue(members, 5.1, 0, Vector3.INF, PackedStringArray(), 0, 0, 1)
	queue.process_due(5.1, host.generation, ports)
	check(queue.prepared_jobs.size() == 1, "Per-kind limits include warnings before real actors exist")
	queue.clear()
	enemy.max_alive = 0
	var triple: Array[WaveEnemyDefinition] = [enemy, enemy, enemy]
	queue.enqueue(single, 5.2, 0, Vector3.INF, PackedStringArray(), 0, 0, 1)
	queue.enqueue(triple, 5.2, 0.1, Vector3.INF, PackedStringArray(), 0, 0, 3)
	queue.sort_jobs()
	queue.process_due(5.2, host.generation, ports)
	var born := host.spawns
	queue.process_due(5.71, host.generation, ports)
	check(host.spawns == born + 1 and queue.reserved_batch.is_empty(), "A later oversized batch cannot deadlock an earlier reserved singleton")
	queue.clear()
	host.alive = 0
	host.on_prepare = func(): queue.clear()
	queue.enqueue(single, 6, 0, Vector3.INF, PackedStringArray(), 0, 0, 1)
	queue.process_due(6, host.generation, ports)
	check(queue.prepared_jobs.is_empty() and queue.jobs.is_empty(), "Reentrant preparation cannot publish stale warnings after queue cancellation")
	host.on_prepare = Callable()
	var cancel_started := func(_job: Dictionary, _seconds: float): queue.clear()
	queue.connect("warning_started", cancel_started)
	queue.enqueue(single, 7, 0, Vector3.INF, PackedStringArray(), 0, 0, 1)
	queue.process_due(7, host.generation, ports)
	check(queue.prepared_jobs.is_empty() and queue.jobs.is_empty(), "Warning listeners can cancel a run without leaving a stale reservation")
	queue.disconnect("warning_started", cancel_started)
	host.valid_point = false
	ports.warning_seconds = 0.0
	ports.block_timeout = 1.0
	queue.enqueue(members, 8, 0, Vector3.INF, PackedStringArray(), 0, 0, 1)
	for job: Dictionary in queue.jobs: job.blocked_since = 0.0
	queue.process_due(8, host.generation, ports)
	check(host.errors == 1, "A timeout stops the current tick even when the host callback does not clear the queue")
	queue.clear()
	host.queue = null
	print(JSON.stringify({"suite":"spawn_shadow_queue", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
