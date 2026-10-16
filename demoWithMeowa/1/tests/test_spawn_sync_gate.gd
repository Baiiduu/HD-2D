extends SceneTree

class IndexProbe extends WaveEnemySpatialIndex:
	var syncs := 0
	func synchronize(enemies: Array[WaveEnemy]) -> void:
		syncs += 1
		super.synchronize(enemies)

class SpawnProbe extends WavePrototype:
	var attempts := 0
	var observed := Vector3.INF
	var actor: WaveEnemy
	func _ready() -> void:
		set_physics_process(false)
	func _spawn_enemy(_definition: WaveEnemyDefinition = null, _position := Vector3.INF,
			_zones := PackedStringArray(), _warning := -1.0, _batch: Dictionary = {}) -> bool:
		attempts += 1
		observed = _spatial_index._positions[_spatial_index._entries[actor]]
		return false

var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func job(enemy: WaveEnemyDefinition, due := 10.0, retry := 0.0, batch: Dictionary = {}) -> Dictionary:
	return {"id":0, "enemy":enemy, "due":due, "next_attempt":retry, "batch":batch,
		"blocked_since":-1.0, "position":Vector3.INF, "zones":PackedStringArray(), "warning":0.0}

func _initialize() -> void:
	create_timer(10.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var wave := SpawnProbe.new()
	world.add_child(wave)
	wave.phase = WavePrototype.Phase.BATTLE
	wave._path_ready = true
	wave._wave_clock = 10.0
	wave.max_active_enemies = 10
	wave.max_spawn_checks_per_tick = 4
	wave.max_spawns_per_tick = 4
	var index := IndexProbe.new()
	wave._spatial_index = index
	var actor := WaveEnemy.new()
	world.add_child(actor)
	actor.set_physics_process(false)
	wave.enemies.append(actor)
	wave.actor = actor
	index.update(actor)
	actor.position = Vector3(4,0,3) # Deliberate external move without a commit.
	var data := WaveEnemyDefinition.new()
	wave._process_spawns()
	check(index.syncs == 0, "empty queue does not synchronize")
	wave._spawn_queue.assign([job(data, 20.0)])
	for step in 6: wave._process_spawns()
	check(index.syncs == 0 and wave.attempts == 0, "future-only queue performs no full scans across repeated calls")
	wave._spawn_queue.assign([job(data, 10.0, 12.0)])
	wave._process_spawns()
	check(index.syncs == 0, "retry backoff performs no full scan")
	data.max_alive = 1
	wave._alive_by_definition[data] = 1
	wave._spawn_queue.assign([job(data)])
	wave._process_spawns()
	check(index.syncs == 0 and wave._capacity_waiting == 1, "definition capacity wait performs no full scan")
	data.max_alive = 0
	wave.max_active_enemies = 1
	wave._process_spawns()
	check(index.syncs == 0 and wave._spawn_state.capacity_blocked, "global capacity wait retains its bookkeeping without synchronization")
	wave.max_active_enemies = 10
	wave.max_spawn_checks_per_tick = 0
	wave._process_spawns()
	check(index.syncs == 0, "exhausted check budget performs no full scan")
	wave.max_spawn_checks_per_tick = 4
	wave.max_spawns_per_tick = 0
	wave._process_spawns()
	check(index.syncs == 0, "exhausted spawn budget performs no full scan")
	wave.max_spawns_per_tick = 4
	wave.combat_frozen = true
	wave._process_spawns()
	check(index.syncs == 0, "combat freeze performs no full scan")
	wave.combat_frozen = false
	wave._path_ready = false
	wave._process_spawns()
	check(index.syncs == 0, "unready path performs no full scan")
	wave._path_ready = true
	wave._spawn_queue.assign([job(data), job(data)])
	wave._process_spawns()
	check(index.syncs == 1 and wave.attempts == 2, "two actual attempts share exactly one synchronization")
	check(wave.observed == actor.global_position, "external movement is synchronized before the actual attempt")
	check(wave._spawn_queue.size() == 2 and wave._spawn_queue[0].next_attempt > 10.0, "failed attempts retain jobs and original retry scheduling")
	wave._process_spawns()
	check(index.syncs == 1 and wave.attempts == 2, "new retry wait does not repeat the scan")
	wave._wave_clock = 11.0
	wave._process_spawns()
	check(index.syncs == 2 and wave.attempts == 4, "a later actual retry receives a fresh synchronization")
	world.free()
	print("Spawn synchronization gate: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
