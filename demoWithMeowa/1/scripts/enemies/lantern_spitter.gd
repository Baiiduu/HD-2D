class_name LanternSpitterEnemy
extends CreatureEnemy

enum AttackPhase { MOVE, WINDUP, RECOVERY }
var attack_phase := AttackPhase.MOVE
var rules: LanternSpitterDefinition
var _attack_clock := 1.0
var _phase_clock := 0.0
var _shot_direction := Vector3.FORWARD
var _telegraph: EnemyTelegraph

func configure_wave(context: Dictionary, data: WaveEnemyDefinition, warning: float) -> void:
	super.configure_wave(context, data, warning)
	rules = data as LanternSpitterDefinition

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
			_release_warning()
			_telegraph.hide()
			_feedback.shoot_seed(self, _shot_direction, rules)
			_sound(attack_sound, &"lantern_shot", GameAudio.Kind.ATTACK)
			attack_phase = AttackPhase.RECOVERY
			_phase_clock = rules.recovery_seconds
			_attack_clock = rules.attack_interval
		return
	if attack_phase == AttackPhase.RECOVERY:
		_idle_motion(delta)
		_phase_clock -= delta
		_visual_action = &"skill"
		_visual_progress = 0.65 + (1.0 - maxf(0.0, _phase_clock) / rules.recovery_seconds) * 0.35
		if _phase_clock <= 0.0: attack_phase = AttackPhase.MOVE
		return
	_visual_action = &""
	_visual_progress = -1.0
	var distance := TerrainPath.horizontal_distance(global_position, target.global_position)
	if distance < rules.retreat_distance:
		var away := global_position - target.global_position
		away.y = 0.0
		away = away.normalized()
		_move_local(away, delta)
		_look = -away
	elif distance > rules.shooting_range or not _can_see_target(): _move_chase(delta, 1.4)
	else:
		_idle_motion(delta)
		if _attack_clock <= 0.0 and absf(global_position.y - target.global_position.y) < contact_height and _claim_warning():
			_shot_direction = target.global_position - global_position
			_shot_direction.y = 0.0
			_shot_direction = _shot_direction.normalized()
			_look = _shot_direction
			_phase_clock = rules.windup_seconds
			attack_phase = AttackPhase.WINDUP
			_telegraph.line(navigation.ground_position(global_position), _shot_direction, minf(distance, rules.shooting_range), 0.18)

func _on_defeated() -> void:
	_telegraph.hide()
	super._on_defeated()
