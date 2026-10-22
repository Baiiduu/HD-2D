class_name BellFrogEnemy
extends CreatureEnemy

enum AttackPhase { MOVE, WINDUP, RECOVERY }
var attack_phase := AttackPhase.MOVE
var rules: BellFrogDefinition
var _attack_clock := 1.0
var _phase_clock := 0.0
var _telegraph: EnemyTelegraph
var _affected: Dictionary[int, WeakRef] = {}

func configure_wave(context: Dictionary, data: WaveEnemyDefinition, warning: float) -> void:
	super.configure_wave(context, data, warning)
	rules = data as BellFrogDefinition

func _ready() -> void:
	super._ready()
	_telegraph = EnemyTelegraph.new()
	add_child(_telegraph)

func _combat_tick(delta: float) -> void:
	_attack_clock = maxf(0.0, _attack_clock - delta)
	if attack_phase == AttackPhase.WINDUP:
		_idle_motion(delta)
		_phase_clock -= delta
		_visual_action = &"skill"
		_visual_progress = (1.0 - maxf(0.0, _phase_clock) / rules.windup_seconds) * 0.65
		if _phase_clock <= 0.0:
			_pulse()
			_release_warning()
			attack_phase = AttackPhase.RECOVERY
			_phase_clock = rules.recovery_seconds
			_attack_clock = rules.attack_interval
		return
	if attack_phase == AttackPhase.RECOVERY:
		_idle_motion(delta)
		_phase_clock -= delta
		_visual_action = &"skill"
		_visual_progress = 0.65 + (1.0 - maxf(0.0, _phase_clock) / rules.recovery_seconds) * 0.35
		_telegraph.set_opacity(maxf(0.0, _phase_clock) / rules.recovery_seconds * 0.65)
		if _phase_clock <= 0.0:
			_telegraph.hide()
			attack_phase = AttackPhase.MOVE
		return
	_visual_action = &""
	_visual_progress = -1.0
	_move_chase(delta, 2.0)
	_touch_player()
	if _attack_clock <= 0.0 and spatial_index and _claim_warning():
		if _boost_targets(true).is_empty():
			_release_warning()
			return
		_phase_clock = rules.windup_seconds
		attack_phase = AttackPhase.WINDUP
		_telegraph.ring(navigation.ground_position(global_position), rules.boost_radius)
		_telegraph.set_opacity(0.25)

func _boost_targets(first_only := false) -> Array[WaveEnemy]:
	var result: Array[WaveEnemy] = []
	if not spatial_index: return result
	var space := get_world_3d().direct_space_state
	for enemy in spatial_index.nearby(global_position, rules.boost_radius):
		if enemy == self or enemy.dead or enemy.spawn_delay > 0.0 or not enemy.definition or enemy.definition.role != WaveEnemyDefinition.Role.COMMON: continue
		if absf(global_position.y - enemy.global_position.y) > 0.35: continue
		var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.4, enemy.global_position + Vector3.UP * 0.4, 1, [target.get_rid()])
		if space.intersect_ray(ray).is_empty():
			result.append(enemy)
			# Windup only needs existence; the actual pulse still checks everybody.
			if first_only: return result
	return result

func _pulse() -> void:
	for id in _affected.keys():
		var previous: WaveEnemy = _affected[id].get_ref()
		if not is_instance_valid(previous) or previous.dead or not previous._speed_boosts.has(get_instance_id()): _affected.erase(id)
	for enemy in _boost_targets():
		enemy.add_speed_boost(self, rules.speed_multiplier, rules.boost_seconds)
		_affected[enemy.get_instance_id()] = weakref(enemy)
	_telegraph.set_opacity(0.65)
	_sound(attack_sound, &"frog_pulse", GameAudio.Kind.DANGER)

func _clear_boosts() -> void:
	for reference in _affected.values():
		var enemy: WaveEnemy = reference.get_ref()
		if is_instance_valid(enemy): enemy.remove_speed_boost(get_instance_id())
	_affected.clear()

func _on_stun_started() -> void:
	attack_phase = AttackPhase.MOVE
	_phase_clock = 0.0
	_telegraph.hide()
	super._on_stun_started()

func _on_defeated() -> void:
	_clear_boosts()
	_telegraph.hide()
	super._on_defeated()

func cancel() -> void:
	_clear_boosts()
	super.cancel()

func _exit_tree() -> void:
	_clear_boosts()
	super._exit_tree()
