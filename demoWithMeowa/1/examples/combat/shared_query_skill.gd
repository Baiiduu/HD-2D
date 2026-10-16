extends Node3D

## Manual single-target integration example, not a registered gameplay skill.
## The owner advances cooldown and requests an attack; there are no idle ticks.
var session: WavePrototype
var interval := 0.5
var height_tolerance := 0.55
var _remaining := 0.0
var _nearby: Array[WaveEnemy] = []
var _ignored: Dictionary[int, bool] = {}

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

func advance(delta: float) -> void:
	if is_instance_valid(session) and session.combat_active():
		_remaining = maxf(0.0, _remaining - maxf(delta, 0.0))

func cancel_current() -> void:
	_remaining = 0.0
	_nearby.clear()

func strike_one(origin: Vector3, radius: float, damage: float) -> bool:
	# Qualification/cooldown precede candidate gathering and physics queries.
	if not is_instance_valid(session) or not session.combat_active() or _remaining > 0.0: return false
	if not origin.is_finite() or not is_finite(radius) or radius <= 0.0 or not is_finite(damage) or damage <= 0.0: return false
	var generation := session.get_combat_generation()
	session.get_nearby_enemies_into(origin, radius, _ignored, _nearby)
	var selected: WaveEnemy
	var excluded: Array[RID] = [session.player.get_rid()]
	for enemy in _nearby:
		if enemy.dead or enemy.spawn_delay > 0.0: continue
		var point := enemy.global_position
		if absf(point.y - origin.y) > height_tolerance: continue
		if not session.terrain.ray_clear(origin + Vector3.UP * 0.45, point + Vector3.UP * 0.45, 1, excluded): continue
		selected = enemy
		break
	# Release the borrowed candidate iteration BEFORE damage invokes callbacks.
	_nearby.clear()
	if not is_instance_valid(selected) or generation != session.get_combat_generation() or not session.combat_active(): return false
	# Reserve cooldown before callbacks: reentrant requests cannot attack twice.
	_remaining = maxf(interval, 0.001)
	selected.take_damage(damage, {"source": &"example_shared_query", "direction": selected.global_position - origin})
	return true
