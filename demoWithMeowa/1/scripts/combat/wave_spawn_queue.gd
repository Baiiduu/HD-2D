class_name WaveSpawnQueue
extends RefCounted
## 持有待生成任务、批次预留和重试状态；地图与会话通过显式端口接入。
signal warning_started(job: Dictionary, seconds: float)
signal warning_finished(id: int, spawned: bool)

class Services extends RefCounted:
	var active_limit := 1
	var check_budget := 1
	var spawn_budget := 1
	var retry_interval := 0.3
	var block_timeout := 10.0
	var warning_seconds := 0.0
	var prepare: Callable
	var alive_count: Callable
	var has_capacity: Callable
	var spawn: Callable
	var synchronize: Callable
	var current: Callable
	var frozen: Callable
	var changed: Callable
	var blocked: Callable
	var timed_out: Callable

var jobs: Array[Dictionary] = []
var reserved_batch: Dictionary = {}
## 仅保存已验证的预告落点；不实例化怪物，也不登记到伤害／找怪索引。
var prepared_jobs: Dictionary[int, Dictionary] = {}
var sequence := 0
var queued_total := 0
var capacity_waiting := 0
var capacity_blocked := false
var _revision := 0

func clear() -> void:
	_revision += 1
	for id: int in prepared_jobs.keys(): _release_warning(id, false)
	jobs.clear()
	reserved_batch.clear()
	capacity_waiting = 0
	capacity_blocked = false

func _release_warning(id: int, spawned: bool) -> void:
	if not prepared_jobs.has(id): return
	var job := prepared_jobs[id]
	prepared_jobs.erase(id)
	job.erase("spawn_point")
	job.erase("ready_at")
	warning_finished.emit(id, spawned)

## 整批尚未出生的成员 + 批外预告 + 当前申请，只计算一次容量。
func capacity_reservation(job: Dictionary) -> Dictionary:
	var members: Array[WaveEnemyDefinition] = []
	if not reserved_batch.is_empty():
		for definition: WaveEnemyDefinition in reserved_batch.counts:
			for index in int(reserved_batch.counts[definition]): members.append(definition)
	for prepared: Dictionary in prepared_jobs.values():
		if prepared.batch.is_empty() or prepared.batch.id != reserved_batch.get("id", -1): members.append(prepared.enemy)
	if job.batch.is_empty():
		if not prepared_jobs.has(int(job.id)): members.append(job.enemy)
	elif job.batch.id != reserved_batch.get("id", -1):
		for definition: WaveEnemyDefinition in job.batch.counts:
			for index in int(job.batch.counts[definition]): members.append(definition)
	return make_batch(members, -1)

func _batch_has_warning(batch: Dictionary) -> bool:
	for job: Dictionary in prepared_jobs.values():
		if not job.batch.is_empty() and job.batch.id == batch.id: return true
	return false

static func make_batch(members: Array[WaveEnemyDefinition], id: int) -> Dictionary:
	var counts := {}
	var roles := [0, 0, 0, 0]
	var cost := 0
	var clearance := 0.0
	for enemy in members:
		counts[enemy] = int(counts.get(enemy, 0)) + 1
		roles[enemy.role] += 1
		cost += enemy.population_cost
		clearance = maxf(clearance, enemy.spawn_clearance)
	return {"id":id, "size":members.size(), "remaining":members.size(), "counts":counts, "roles":roles, "cost":cost, "clearance":clearance}

func enqueue(members: Array[WaveEnemyDefinition], clock: float, delay: float, position: Vector3, zones: PackedStringArray, warning: float, interval: float, batch_size: int) -> void:
	var batch: Dictionary = {}
	for index in members.size():
		sequence += 1
		if batch_size > 1 and index % batch_size == 0:
			batch = make_batch(members.slice(index, mini(index + batch_size, members.size())), sequence)
		jobs.append({"id":sequence, "enemy":members[index], "due":clock + delay + floorf(float(index) / batch_size) * interval, "position":position,
			"zones":zones.duplicate(), "warning":warning, "next_attempt":0.0, "blocked_since":-1.0, "batch":batch})
	queued_total += members.size()

func sort_jobs() -> void:
	jobs.sort_custom(func(a: Dictionary, b: Dictionary): return a.due < b.due or (a.due == b.due and a.id < b.id))

func complete_member(batch: Dictionary, definition: WaveEnemyDefinition) -> void:
	if batch.is_empty(): return
	batch.remaining -= 1
	batch.counts[definition] -= 1
	batch.roles[definition.role] -= 1
	batch.cost -= definition.population_cost
	if batch.remaining == 0: reserved_batch = {}

func process_due(clock: float, generation: int, services: Services) -> void:
	if services.frozen.call() or not services.current.call(generation): return
	capacity_waiting = 0
	if jobs.is_empty():
		capacity_blocked = false
		reserved_batch.clear()
		return
	if services.alive_count.call() >= services.active_limit:
		for job in jobs:
			if job.due > clock: break
			capacity_waiting += 1
		if not capacity_blocked:
			for job in jobs: job.blocked_since = -1.0
		capacity_blocked = true
		return
	capacity_blocked = false
	var revision := _revision
	var checked := 0
	var spawned := 0
	var synchronized := false
	var warnings_enabled := services.warning_seconds > 0.0 and services.prepare.is_valid()
	if reserved_batch.is_empty():
		for job in jobs:
			if job.due > clock: break
			if not job.batch.is_empty() and job.next_attempt <= clock:
				if warnings_enabled and not services.has_capacity.call(job): continue
				reserved_batch = job.batch
				break
	# 追加任务不进入本帧快照；取消或更换会话立即终止旧迭代。
	for job in jobs.duplicate():
		if job.due > clock: break
		if job.next_attempt > clock: continue
		# 预告等待不查位置、不同步索引；冻结时 clock 同样保持不变。
		if job.has("ready_at") and float(job.ready_at) > clock: continue
		var batch: Dictionary = job.batch
		if not batch.is_empty():
			if reserved_batch.is_empty():
				if warnings_enabled and not services.has_capacity.call(job):
					capacity_waiting += 1
					continue
				reserved_batch = batch
			if reserved_batch.id != batch.id:
				job.blocked_since = -1.0
				capacity_waiting += 1
				continue
		if not services.has_capacity.call(job):
			job.blocked_since = -1.0
			capacity_waiting += 1
			continue
		if checked >= services.check_budget or spawned >= services.spawn_budget or services.alive_count.call() >= services.active_limit: break
		# Waits need no scan. Commit external movement once before the first real attempt.
		if not synchronized:
			services.synchronize.call()
			synchronized = true
		checked += 1
		if warnings_enabled and not prepared_jobs.has(int(job.id)):
			var prepared: bool = services.prepare.call(job)
			if revision != _revision or not services.current.call(generation): return
			if prepared:
				job.ready_at = clock + services.warning_seconds
				prepared_jobs[int(job.id)] = job
				spawned += 1 # 创建预告也遵守本帧预算，不把整批工作挤到同一帧。
				warning_started.emit(job, services.warning_seconds)
				if revision != _revision or not services.current.call(generation) or services.frozen.call(): return
				continue
			if _retry(job, batch, clock, services): return
			if revision != _revision or not services.current.call(generation): return
			continue
		var success: bool = services.spawn.call(job)
		if revision != _revision or not services.current.call(generation): return
		if success:
			jobs.erase(job)
			_release_warning(int(job.id), true)
			if revision != _revision or not services.current.call(generation): return
			spawned += 1
			services.changed.call()
			if revision != _revision or not services.current.call(generation) or services.frozen.call(): return
		else:
			_release_warning(int(job.id), false)
			if revision != _revision or not services.current.call(generation): return
			if _retry(job, batch, clock, services): return
			if revision != _revision or not services.current.call(generation): return

func _retry(job: Dictionary, batch: Dictionary, clock: float, services: Services) -> bool:
	if not batch.is_empty() and batch.remaining == batch.size and not _batch_has_warning(batch):
		reserved_batch = {}
		batch.erase("points")
		batch.erase("zone")
		batch.erase("front_points")
	if job.blocked_since < 0: job.blocked_since = clock
	job.next_attempt = clock + services.retry_interval
	var revision := _revision
	services.blocked.call()
	if revision != _revision: return true
	if clock - float(job.blocked_since) >= services.block_timeout:
		services.timed_out.call()
		return true
	return false
