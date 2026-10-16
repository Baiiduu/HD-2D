extends SceneTree
## 队列只依赖显式端口，在没有地图、物理实体和 UI 的情况下验证实际调度。
const PATH := "res://scripts/combat/wave_spawn_queue.gd"
var checks := 0
var failures: Array[String] = []

class Host extends RefCounted:
	var queue
	var generation := 1
	var frozen := false
	var alive := 0
	var attempts := 0
	var notices := 0
	var errors := 0
	var syncs := 0
	var fits := true
	var succeeds := true
	var on_spawn: Callable
	var on_changed: Callable
	func count() -> int: return alive
	func capacity(_job: Dictionary) -> bool: return fits
	func synchronize() -> void: syncs += 1
	func current(token: int) -> bool: return generation == token
	func is_frozen() -> bool: return frozen
	func changed() -> void:
		if on_changed.is_valid(): on_changed.call()
	func notice() -> void: notices += 1
	func fail() -> void: errors += 1
	func spawn(job: Dictionary) -> bool:
		attempts += 1
		if not succeeds: return false
		alive += 1
		queue.complete_member(job.batch, job.enemy)
		if on_spawn.is_valid(): on_spawn.call()
		return true

func _initialize() -> void: run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func run() -> void:
	check(ResourceLoader.exists(PATH), "Spawn queue is available independently of a scene controller")
	if not ResourceLoader.exists(PATH): quit(1); return
	var script = load(PATH)
	var queue = script.new()
	var host := Host.new()
	host.queue = queue
	var ports = script.Services.new()
	ports.alive_count = host.count
	ports.has_capacity = host.capacity
	ports.spawn = host.spawn
	ports.synchronize = host.synchronize
	ports.current = host.current
	ports.frozen = host.is_frozen
	ports.changed = host.changed
	ports.blocked = host.notice
	ports.timed_out = host.fail
	ports.active_limit = 8
	ports.check_budget = 2
	ports.spawn_budget = 1
	ports.retry_interval = 0.3
	ports.block_timeout = 1.0
	var enemy := WaveEnemyDefinition.new()
	var members: Array[WaveEnemyDefinition] = [enemy, enemy, enemy]
	var single: Array[WaveEnemyDefinition] = [enemy]
	var zones := PackedStringArray(["West"])
	queue.enqueue(members, 0.0, 0.5, Vector3.INF, zones, 0.0, 1.0, 2)
	zones[0] = "East"
	check(queue.jobs.size() == 3 and queue.queued_total == 3, "Every delayed member is registered before spawning")
	check(queue.jobs[0].due == 0.5 and queue.jobs[1].due == 0.5 and queue.jobs[2].due == 1.5, "Batch members share a due time and preserve batch intervals")
	check(queue.jobs[0].zones[0] == "West", "Caller zone edits cannot rewrite queued jobs")
	queue.process_due(0.4, host.generation, ports)
	check(host.attempts == 0, "Future jobs never spawn early")
	queue.process_due(0.5, host.generation, ports)
	check(host.attempts == 1 and queue.jobs.size() == 2 and queue.reserved_batch.remaining == 1, "Frame budget leaves the partial batch reserved")
	queue.process_due(0.5, host.generation, ports)
	check(host.attempts == 2 and queue.jobs.size() == 1 and queue.reserved_batch.is_empty(), "Finishing a batch releases its reservation")
	check(queue.queued_total == 3, "Consumed jobs retain the wave registration budget")
	queue.clear()
	host.alive = ports.active_limit
	queue.enqueue(single, 0.0, 0.0, Vector3.INF, PackedStringArray(), 0.0, 0.0, 1)
	queue.jobs[0].blocked_since = 0.0
	var syncs := host.syncs
	queue.process_due(10.0, host.generation, ports)
	check(queue.capacity_waiting == 1 and host.syncs == syncs and queue.jobs[0].blocked_since == -1.0, "Full population waits without position queries or block timeout")
	host.alive = 0
	host.fits = false
	queue.process_due(20.0, host.generation, ports)
	check(queue.jobs[0].blocked_since == -1.0 and queue.capacity_waiting == 1 and host.errors == 0, "Per-kind capacity waits also exclude block timeout")
	host.fits = true
	host.succeeds = false
	queue.process_due(20.0, host.generation, ports)
	var attempts := host.attempts
	queue.process_due(20.1, host.generation, ports)
	check(host.attempts == attempts and host.notices == 1, "Unavailable positions respect retry spacing")
	queue.process_due(21.1, host.generation, ports)
	check(host.errors == 1, "Persistent position failure reports a timeout")
	queue.clear()
	host.succeeds = true
	host.on_spawn = func(): host.generation += 1; queue.clear()
	queue.enqueue(members, 0.0, 0.0, Vector3.INF, PackedStringArray(), 0.0, 0.0, 1)
	queue.process_due(0.0, host.generation, ports)
	check(queue.jobs.is_empty(), "Reentrant run replacement never consumes stale jobs after spawn")
	host.on_spawn = Callable()
	host.on_changed = func(): host.frozen = true
	host.frozen = false
	ports.spawn_budget = 3
	queue.enqueue(members, 0.0, 0.0, Vector3.INF, PackedStringArray(), 0.0, 0.0, 1)
	queue.process_due(0.0, host.generation, ports)
	check(queue.jobs.size() == 2, "A successful spawn is removed before callback-driven freezing stops the tick")
	host.on_changed = Callable()
	host.frozen = false
	host.alive = 0
	queue.clear()
	ports.check_budget = 1
	queue.enqueue(members, 0.0, 0.0, Vector3.INF, PackedStringArray(), 0.0, 0.0, 1)
	queue.process_due(0.0, host.generation, ports)
	check(queue.jobs.size() == 2, "Position check budget remains independent from successful spawn budget")
	queue.clear()
	host.alive = 0
	ports.check_budget = 8
	ports.spawn_budget = 8
	attempts = host.attempts
	host.on_spawn = func():
		queue.clear()
		queue.enqueue(single, 0.0, 0.0, Vector3.INF, PackedStringArray(), 0.0, 0.0, 1)
	queue.enqueue(members, 0.0, 0.0, Vector3.INF, PackedStringArray(), 0.0, 0.0, 1)
	queue.process_due(0.0, host.generation, ports)
	check(host.attempts == attempts + 1 and queue.jobs.size() == 1, "Clearing the queue invalidates an old iteration even without changing the session token")
	queue.clear()
	host.alive = 0
	attempts = host.attempts
	host.on_spawn = func(): queue.enqueue(single, 0.0, 0.0, Vector3.INF, PackedStringArray(), 0.0, 0.0, 1)
	queue.enqueue(members, 0.0, 0.0, Vector3.INF, PackedStringArray(), 0.0, 0.0, 1)
	queue.process_due(0.0, host.generation, ports)
	check(host.attempts == attempts + 3 and queue.jobs.size() == 3, "Jobs appended by spawn callbacks wait until the next tick")
	host.on_spawn = Callable()
	host.queue = null
	print(JSON.stringify({"suite":"spawn_queue_contract", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
