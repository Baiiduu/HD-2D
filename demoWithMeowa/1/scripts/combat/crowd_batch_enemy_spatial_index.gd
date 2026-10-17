class_name CrowdBatchEnemySpatialIndex
extends WaveEnemySpatialIndex

## Commit contract: update() immediately follows every actual body move,
## teleport, spawn activation, or crowd-parameter change. The inherited packed
## positions therefore describe the current world until the next actual move;
## crossing a physics-step boundary does not itself make a position stale.
##
## The first ordinary query creates fresh forces from that authoritative index
## for this Engine physics frame. Only those forces are frozen for coherent
## planning; nearby/swept queries and body commits always remain live. No force
## from an earlier physics frame is returned, and no Node-wide refresh is needed.
const BatchPlanner = preload("res://scripts/combat/crowd_batch_planner.gd")
var batch_enabled := false:
	set(value):
		if batch_enabled == value: return
		batch_enabled = value
		_reset_plan()
## Behaviour is independent of diagnostics; leave counters off in production.
var diagnostics_enabled := false:
	set(value):
		diagnostics_enabled = value
		_planner.diagnostics_enabled = value
		reset_metrics()
var batch_builds := 0
var batch_queries := 0
var fallback_calls := 0
var plan_candidate_pairs := 0
var plan_accepted_pairs := 0
var neighbor_rebuilds := 0
var neighbor_reuses := 0
var neighbor_search_pairs := 0
var _planner := BatchPlanner.new()
var _plan_frame := -1
var _fallback_frame := -1
var _forces := PackedVector3Array()
var native_kernel: RefCounted:
	set(value):
		if native_kernel == value: return
		native_kernel = value
		_reset_plan()

func _reset_plan() -> void:
	_plan_frame = -1
	_fallback_frame = -1
	_forces.clear()
	_planner.clear()
	if native_kernel: native_kernel.clear()

func reset_metrics() -> void:
	batch_builds = 0
	batch_queries = 0
	fallback_calls = 0
	plan_candidate_pairs = 0
	plan_accepted_pairs = 0
	neighbor_rebuilds = 0
	neighbor_reuses = 0
	neighbor_search_pairs = 0
	candidate_checks = 0

func clear() -> void:
	super.clear()
	_reset_plan()
	reset_metrics()

func update(enemy: WaveEnemy) -> void:
	var revision := _crowd_revision
	super.update(enemy)
	# Position commits preserve this step's coherent plan. Metadata changes
	# invalidate it and the reusable neighbor list, without rereading Node data.
	if batch_enabled and _plan_frame == Engine.get_physics_frames() and revision != _crowd_revision:
		_fallback_frame = _plan_frame

func remove(enemy: WaveEnemy) -> void:
	var registered := _entries.has(enemy)
	super.remove(enemy)
	if registered and batch_enabled and _plan_frame == Engine.get_physics_frames():
		_fallback_frame = _plan_frame
	# Safe rest normally removes the last actor without clearing the base slot
	# capacity. Release the force plan immediately; retain this frame's fallback
	# marker in case a replacement is spawned synchronously after the death.
	if _entries.is_empty():
		_forces.clear()
		_plan_frame = -1
		_planner.clear()
		if native_kernel: native_kernel.clear()

func legacy_separation(enemy: WaveEnemy, radius: float) -> Vector3:
	return super.separation(enemy, radius)

func _prepare_current_step(frame: int) -> void:
	# No await/callback occurs during planning. The packed input describes one
	# common current snapshot even though later movement commits mutate it.
	var planner: RefCounted = native_kernel if native_kernel else _planner
	_forces = planner.plan(_cells, _positions, _ids, _active, _spacing, _bodies, CELL_SIZE, _crowd_revision)
	# The optional kernel may reject an unsupported packet. Never publish a
	# short force array to callers; keep the established script implementation.
	if _forces.size() != _positions.size():
		_forces = _planner.plan(_cells, _positions, _ids, _active, _spacing, _bodies, CELL_SIZE, _crowd_revision)
	_plan_frame = frame
	if diagnostics_enabled and not native_kernel:
		batch_builds += 1
		plan_candidate_pairs += _planner.candidate_pairs
		plan_accepted_pairs += _planner.accepted_pairs
		if _planner.neighbors_rebuilt: neighbor_rebuilds += 1
		else: neighbor_reuses += 1
		neighbor_search_pairs += _planner.search_pairs

func separation(enemy: WaveEnemy, radius: float) -> Vector3:
	if radius <= 0.0: return Vector3.ZERO
	if not batch_enabled: return super.separation(enemy, radius)
	var frame := Engine.get_physics_frames()
	if _fallback_frame == frame:
		if diagnostics_enabled: fallback_calls += 1
		return super.separation(enemy, radius)
	var slot: int = _entries.get(enemy, -1)
	if slot < 0:
		_fallback_frame = frame
		if diagnostics_enabled: fallback_calls += 1
		return super.separation(enemy, radius)
	# Only the actual caller is inspected. This catches direct caller parameter
	# changes before its normal post-move commit, without polling every Node.
	var body := enemy.get_crowd_body_radius()
	if _active[slot] == 0 or enemy.dead or enemy.spawn_delay > 0.0 \
			or body != _bodies[slot] \
			or maxf(enemy.get_crowd_spacing(), body * 2.1) != _spacing[slot] \
			or maxf(radius, body * 2.1) != _spacing[slot]:
		_fallback_frame = frame
		if diagnostics_enabled: fallback_calls += 1
		return super.separation(enemy, radius)
	if _plan_frame != frame: _prepare_current_step(frame)
	if diagnostics_enabled: batch_queries += 1
	return _forces[slot]
