extends Node
## Same ordered actor steps and immediate spatial commits, with one scene callback.
## The driver sits after EnemyAttacks and before actors in the wave's tree order.
var session: WavePrototype
var _actors: Array[WaveEnemy] = []
var _members: Dictionary[WaveEnemy, bool] = {}
var _advancing := false
var _dirty := false
var last_updated := 0

func track(enemy: WaveEnemy) -> void:
	if _members.has(enemy) or not enemy.supports_central_update(): return
	if session.get_script().resource_path != "res://scripts/combat/wave_prototype.gd": return
	if enemy.process_physics_priority != process_physics_priority: return
	if enemy.wave_target != session.player or enemy.combat_active != session.combat_active: return
	_members[enemy] = true
	_actors.append(enemy)
	enemy._central_update_owner = self
	enemy.set_physics_process(false)
	set_physics_process(true)

func untrack(enemy: WaveEnemy) -> void:
	if not _members.erase(enemy): return
	if is_instance_valid(enemy):
		enemy._central_update_owner = null
		enemy.set_physics_process(enemy._wave_tick_enabled and not enemy.dead)
	if _advancing: _dirty = true
	else: _actors.erase(enemy)
	if _members.is_empty(): set_physics_process(false)

func release_all() -> void:
	for enemy in _members.keys(): untrack(enemy)
	if not _advancing: _actors.clear()
	set_physics_process(false)

func _physics_process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	last_updated = 0
	if _advancing or not is_instance_valid(session) or not session.centralized_enemy_updates or not session.combat_active(): return
	var generation := session.get_combat_generation()
	var revision := session._enemy_update_revision
	_advancing = true
	# Births during a callback append after this fixed boundary; removals become
	# tombstones until this pass ends. No per-step copy of the actor array.
	var count := _actors.size()
	for index in count:
		var enemy := _actors[index]
		if not is_instance_valid(enemy) or enemy._central_update_owner != self: continue
		if enemy.dead or not enemy._wave_tick_enabled or not enemy.can_process(): continue
		enemy._advance_wave_step(delta)
		last_updated += 1
		# Known handlers mutate combat state through the session. Recheck after
		# external damage/freeze/phase callbacks instead of polling the full
		# session, target, Callable and tree metadata for every ordinary actor.
		if revision != session._enemy_update_revision:
			if generation != session.get_combat_generation() or not session.combat_active(): break
			revision = session._enemy_update_revision
	_advancing = false
	if _dirty:
		var retained: Array[WaveEnemy] = []
		for enemy in _actors:
			if is_instance_valid(enemy) and _members.has(enemy): retained.append(enemy)
		_actors = retained
		_dirty = false
