class_name LeafChargerEnemy
extends CreatureEnemy

enum AttackPhase { CHASE, WINDUP, CHARGE, RECOVERY }
var attack_phase := AttackPhase.CHASE
var rules: LeafChargerDefinition
var _attack_clock := 1.0
var _phase_clock := 0.0
var _charge_direction := Vector3.FORWARD
var _charge_travel := 0.0
var _charge_plane := 0.0
var _telegraph: EnemyTelegraph

func configure_wave(context: Dictionary, data: WaveEnemyDefinition, warning: float) -> void:
	super.configure_wave(context, data, warning)
	rules = data as LeafChargerDefinition

func _ready() -> void:
	super._ready()
	_telegraph = EnemyTelegraph.new()
	add_child(_telegraph)

func _combat_tick(delta: float) -> void:
	_attack_clock = maxf(0.0, _attack_clock - delta)
	match attack_phase:
		AttackPhase.CHASE:
			_visual_action = &""
			_visual_progress = -1.0
			_move_chase(delta, 0.9)
			if _attack_clock <= 0.0 and TerrainPath.horizontal_distance(global_position, target.global_position) <= rules.trigger_distance and absf(global_position.y - target.global_position.y) < contact_height and _claim_warning():
				if _can_see_target(): _begin_windup()
				else: _release_warning()
		AttackPhase.WINDUP:
			_idle_motion(delta)
			_phase_clock -= delta
			_visual_action = &"skill"
			_visual_progress = (1.0 - maxf(0.0, _phase_clock) / rules.windup_seconds) * 0.5
			_telegraph.set_opacity(0.35 + _visual_progress * 0.45)
			if _phase_clock <= 0.0:
				_release_warning()
				_telegraph.hide()
				attack_phase = AttackPhase.CHARGE
				_charge_travel = 0.0
		AttackPhase.CHARGE:
			_visual_action = &"skill"
			_visual_progress = 0.5
			_advance_charge(delta)
		AttackPhase.RECOVERY:
			_idle_motion(delta)
			_phase_clock -= delta
			_visual_action = &"skill"
			_visual_progress = 0.5 + (1.0 - maxf(0.0, _phase_clock) / rules.recovery_seconds) * 0.5
			if _phase_clock <= 0.0: attack_phase = AttackPhase.CHASE

func _begin_windup() -> void:
	_charge_direction = target.global_position - global_position
	_charge_direction.y = 0.0
	_charge_direction = _charge_direction.normalized()
	if _charge_direction.is_zero_approx():
		_release_warning()
		return
	_look = _charge_direction
	_charge_plane = navigation.ground_position(global_position).y
	var length := _surface_collision.ground_limit(navigation, global_position, _charge_direction, rules.charge_distance, _charge_plane, 0.2)
	var wall := _surface_collision.wall_contact(get_world_3d().direct_space_state, global_position + Vector3.UP * 0.45, global_position + Vector3.UP * 0.45 + _charge_direction * length, body_radius, [target.get_rid()])
	if not wall.is_empty(): length = minf(length, wall.distance)
	if length < 0.2:
		_release_warning()
		_attack_clock = 0.3
		return
	_telegraph.line(navigation.ground_position(global_position), _charge_direction, length, body_radius * 2.0)
	_phase_clock = rules.windup_seconds
	attack_phase = AttackPhase.WINDUP
	velocity.x = 0.0
	velocity.z = 0.0
	_sound(attack_sound, &"leaf_windup", GameAudio.Kind.DANGER)

func _advance_charge(delta: float) -> void:
	var length := minf(rules.charge_speed * delta, rules.charge_distance - _charge_travel)
	var allowed := _surface_collision.ground_limit(navigation, global_position, _charge_direction, length, _charge_plane, 0.2)
	var before := global_position
	var motion := _charge_direction * allowed
	if allowed > 0.0: motion.y = navigation.ground_position(global_position + motion).y + 0.03 - global_position.y
	var hit := move_and_collide(motion)
	_charge_travel += TerrainPath.horizontal_distance(before, global_position)
	velocity.x = _charge_direction.x * rules.charge_speed
	velocity.z = _charge_direction.z * rules.charge_speed
	if hit and hit.get_collider() == target and damage_player.is_valid() and (not can_damage_player.is_valid() or can_damage_player.call(attack_damage)):
		damage_player.call(attack_damage)
	if hit or allowed < length or _charge_travel >= rules.charge_distance - 0.001:
		attack_phase = AttackPhase.RECOVERY
		_phase_clock = rules.recovery_seconds
		_attack_clock = rules.attack_interval
		velocity.x = 0.0
		velocity.z = 0.0

func _on_defeated() -> void:
	_telegraph.hide()
	super._on_defeated()
