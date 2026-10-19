class_name RicochetCameraFeedback
extends RefCounted
const COMBAT_FOCUS := preload("res://scripts/camera/ricochet_combat_focus.gd")

## 镜头局部时间线，不改人物速度、输入、伤害时钟或 Engine.time_scale。
var active := false
var framing := Vector2.ZERO
var shake := Vector2.ZERO
var carry := Vector3.ZERO
var distance_scale := 1.0
var pitch_offset := 0.0
var aim_focus_offset := Vector3.ZERO
var yaw_offset := 0.0
var roll_offset := 0.0
var collision_offset := Vector3.ZERO
var collision_distance_scale := 0.0
var _impact_shot := RicochetImpactShot.new()
var _combat_focus := COMBAT_FOCUS.new()
var _combat_sword: PlayerSword
var _combat_storm: Node
var _impact_rotation_weight := 1.0
var focus_velocity := Vector3.ZERO
var _camera: FollowCamera
var _player: Player
var _body: PlayerRicochet
var _flying := false
var _charging := false
var _charge_tremor_phase := 0.0
var _charge_tremor_strength := 0.0
var _charge_tremor_offset := Vector2.ZERO
var _full_shake_seen := false
var _full_shake_age := 1000.0
var _full_shake_direction := Vector3.ZERO
var _zoom_amount := 0.0
var _zoom_return_from := 0.0
var _zoom_return_age := 0.0
var _zoom_return_seconds := 0.0
var _pitch_return_from := 0.0
var _lens_velocity := Vector2.ZERO
var _handoff_lens_from := Vector2.ZERO
var _handoff_lens_velocity := Vector2.ZERO
var _lens_handoff := false
var _lens_pitch_seconds := 0.0
var _speed_profile_enabled := false
var _charge_focus_profile_enabled := false
var _flight_speed_weight := 0.0
var _focus_handoff := false
var _release_motion := false
var _focus_handoff_age := 0.0
var _focus_handoff_from := Vector3.ZERO
var _focus_handoff_tangent := Vector3.ZERO
var _focus_start_offset := Vector3.ZERO
var _full_zoom_pulse := false
var _age := 0.0
var _return_age := 0.0
var _return_from := Vector2.ZERO
var _return_velocity := Vector2.ZERO
var _return_carry := Vector3.ZERO
var _return_seconds := 0.0
var _velocity := Vector2.ZERO
var _direction := Vector3.ZERO
var _launch_point := Vector3.ZERO
var _carry_from := Vector3.ZERO
var _bounce_age := 1000.0
var _impact_age := 1000.0
var _impact_direction := Vector3.ZERO
var _impact_strength := 0.0
var _launch_speed := 1.0
var _last_speed := 1.0

func bind(camera: FollowCamera, player: Player) -> void:
	_camera = camera
	_player = player
	_body = player.body_ricochet
	_body.state_changed.connect(_on_state_changed)
	_body.launched.connect(_on_launched)
	_body.wall_bounced.connect(_on_bounced)
	_body.impact_recorded.connect(_on_impact_recorded)
	_body.finished.connect(_on_finished)
	_combat_sword = player.sword
	if is_instance_valid(_combat_sword):
		_combat_sword.strike_started.connect(_combat_strike)
		_combat_sword.hit_landed.connect(_combat_sword_hit)
	if is_instance_valid(_body._session): _combat_storm = _body._session.get_node_or_null("RicochetStorm")
	if is_instance_valid(_combat_storm): _combat_storm.connect(&"presentation_landed", _combat_storm_patch)

func dispose() -> void:
	if is_instance_valid(_combat_sword):
		_combat_sword.strike_started.disconnect(_combat_strike)
		_combat_sword.hit_landed.disconnect(_combat_sword_hit)
	if is_instance_valid(_combat_storm): _combat_storm.disconnect(&"presentation_landed", _combat_storm_patch)
	if is_instance_valid(_body):
		_body.state_changed.disconnect(_on_state_changed)
		_body.launched.disconnect(_on_launched)
		_body.wall_bounced.disconnect(_on_bounced)
		_body.impact_recorded.disconnect(_on_impact_recorded)
		_body.finished.disconnect(_on_finished)
	reset()

func follows(player: Node3D) -> bool:
	return _player == player and is_instance_valid(_body)

func reset(keep_impact := false) -> void:
	_combat_focus.reset()
	active = false
	_flying = false
	_charging = false
	_full_shake_seen = false
	_full_shake_age = 1000.0
	_full_shake_direction = Vector3.ZERO
	_zoom_amount = 0.0
	distance_scale = 1.0
	pitch_offset = 0.0
	focus_velocity = Vector3.ZERO
	_lens_velocity = Vector2.ZERO
	_lens_handoff = false
	_speed_profile_enabled = false
	_charge_focus_profile_enabled = false
	_flight_speed_weight = 0.0
	_focus_handoff = false
	_release_motion = false
	_full_zoom_pulse = false
	framing = Vector2.ZERO
	shake = Vector2.ZERO
	carry = Vector3.ZERO
	_velocity = Vector2.ZERO
	_impact_age = 1000.0
	_bounce_age = 1000.0
	if not keep_impact:
		_charge_tremor_phase = 0.0
		_charge_tremor_strength = 0.0
		_charge_tremor_offset = Vector2.ZERO
		_impact_shot.clear()
		yaw_offset = 0.0
		roll_offset = 0.0
		collision_offset = Vector3.ZERO
		collision_distance_scale = 0.0

func _on_state_changed(state: PlayerRicochet.State) -> void:
	var settings := _camera.ricochet_camera_settings
	if state != PlayerRicochet.State.CHARGING or not settings or not settings.enabled or not settings.charge_focus_enabled: return
	_restart_timeline()
	active = true
	_charging = true
	_age = 0.0
	_carry_from = _camera.focus - _camera._target_point()
	carry = _carry_from
	aim_focus_offset = _carry_from
	_impact_shot.release(0.10)

## 发射和快速重按接住已有推近与轻震，只重启动作的平移时间线。
func _restart_timeline() -> void:
	var zoom := _zoom_amount
	var pitch := pitch_offset
	var pulse_age := _full_shake_age
	var pulse_direction := _full_shake_direction
	var zoom_pulse := _full_zoom_pulse
	reset(true)
	_zoom_amount = zoom
	pitch_offset = pitch
	distance_scale = 1.0 - zoom
	_full_shake_age = pulse_age
	_full_shake_direction = pulse_direction
	_full_zoom_pulse = zoom_pulse

func _trigger_full_shake(direction: Vector3, settings: RicochetCameraSettings) -> void:
	_full_shake_seen = true
	if not settings.charge_full_shake_enabled and not settings.charge_staging_enabled: return
	_full_shake_age = 0.0
	_full_shake_direction = direction
	_full_zoom_pulse = settings.charge_staging_enabled

func _advance_full_shake(delta: float, settings: RicochetCameraSettings, view: Basis, short_side: float) -> Vector2:
	_full_shake_age += delta
	if _charging and not _full_shake_seen and _body.charge_fraction >= 1.0:
		_trigger_full_shake(_body.direction, settings)
	if not settings.charge_full_shake_enabled or _full_shake_age >= settings.charge_full_shake_seconds: return Vector2.ZERO
	var t := clampf(_full_shake_age / maxf(settings.charge_full_shake_seconds, 0.001), 0.0, 1.0)
	# 一次沿瞄准方向的往返，起尾均归零；满蓄保持期间不再重播。
	var pulse := sin(t * TAU) * sin(t * PI)
	return _project(_full_shake_direction, view) * pulse * settings.charge_full_shake_pixels / maxf(short_side, 1.0)

func _advance_charge_tremor(delta: float, settings: RicochetCameraSettings, short_side: float) -> Vector2:
	if _charging and settings.charge_tremor_enabled:
		var progress := smoothstep(0.0, 1.0, _body.charge_fraction)
		var goal := settings.charge_tremor_pixels * lerpf(0.2, 1.0, progress)
		_charge_tremor_strength = lerpf(_charge_tremor_strength, goal, 1.0 - exp(-delta / 0.06))
		# 积分频率而非用当前频率乘总时间，蓄力变速时相位仍连续。
		_charge_tremor_phase += TAU * lerpf(settings.charge_tremor_start_hz, settings.charge_tremor_full_hz, progress) * delta
		var phase := _charge_tremor_phase
		var horizontal := (sin(phase) + 0.35 * sin(phase * 1.73 + 0.8)) / 1.35
		var vertical := (sin(phase * 1.17 + 0.9) + 0.25 * sin(phase * 1.41 + 2.1)) * 0.6 / 1.25
		# 解析幅度界限，避免逐帧随机和向量截断造成突然拐点。
		_charge_tremor_offset = Vector2(horizontal, vertical) * (_charge_tremor_strength / 1.17)
	else:
		var decay := exp(-4.0 * delta / maxf(settings.charge_tremor_release_seconds, 0.001))
		_charge_tremor_strength *= decay
		_charge_tremor_offset *= decay
		if _charge_tremor_strength < 0.001:
			_charge_tremor_strength = 0.0
			_charge_tremor_offset = Vector2.ZERO
	return _charge_tremor_offset / maxf(short_side, 1.0)

func _begin_zoom_return(seconds: float) -> void:
	_zoom_return_from = _zoom_amount
	_pitch_return_from = pitch_offset
	_zoom_return_age = 0.0
	_zoom_return_seconds = seconds
	if seconds <= 0.0:
		_zoom_amount = 0.0
		pitch_offset = 0.0
		distance_scale = 1.0

func _advance_zoom(delta: float, settings: RicochetCameraSettings) -> void:
	var previous := Vector2(1.0 - distance_scale, pitch_offset)
	if _lens_handoff:
		_zoom_return_age += delta
		var goal := _flight_lens_goal(settings)
		var opening := settings.release_progress(_zoom_return_age, _zoom_return_seconds) if _flying else -1.0
		_zoom_amount = clampf(goal.x + _lens_return(_handoff_lens_from.x - goal.x, _handoff_lens_velocity.x, _zoom_return_age, _zoom_return_seconds, opening), -0.15, 0.25)
		pitch_offset = clampf(goal.y + _lens_return(_handoff_lens_from.y - goal.y, _handoff_lens_velocity.y, _zoom_return_age, _lens_pitch_seconds), -8.0, 0.0)
		if _zoom_return_age >= maxf(_zoom_return_seconds, _lens_pitch_seconds): _lens_handoff = false
	elif _charging:
		var fraction := _body.charge_fraction
		var progress := lerpf(settings.charge_onset_ratio, 1.0, smoothstep(0.0, 1.0, fraction) if settings.charge_staging_enabled else fraction)
		var goal := clampf(settings.charge_zoom_ratio, 0.0, 0.25) * progress
		var weight := 1.0 - exp(-delta / maxf(settings.charge_focus_seconds, 0.001))
		_zoom_amount = lerpf(_zoom_amount, goal, weight)
		var pitch_goal := -settings.charge_pitch_drop * smoothstep(0.1, 0.9, fraction) if settings.charge_staging_enabled else 0.0
		pitch_offset = lerpf(pitch_offset, pitch_goal, weight)
		if settings.charge_staging_enabled and fraction >= 1.0:
			if absf(pitch_offset - pitch_goal) < 0.005: pitch_offset = pitch_goal
			if absf(_zoom_amount - goal) < 0.0001: _zoom_amount = goal
	elif _flying and settings.flight_speed_camera_enabled:
		var goal := _flight_lens_goal(settings)
		_zoom_amount = goal.x
		pitch_offset = goal.y
	elif not is_zero_approx(_zoom_amount) or not is_zero_approx(pitch_offset):
		_zoom_return_age += delta
		var remaining := 1.0 - smoothstep(0.0, maxf(_zoom_return_seconds, 0.001), _zoom_return_age)
		_zoom_amount = _zoom_return_from * remaining
		pitch_offset = _pitch_return_from * remaining
	var punch := 0.0
	if _full_zoom_pulse and settings.charge_staging_enabled and _full_shake_age < settings.charge_full_shake_seconds:
		punch = sin(PI * _full_shake_age / maxf(settings.charge_full_shake_seconds, 0.001)) * settings.charge_full_punch_ratio
	distance_scale = 1.0 - minf(0.25, _zoom_amount + punch)
	distance_scale += _combat_focus.pulse * settings.combat_pullback_ratio
	if delta > 0.0: _lens_velocity = (Vector2(1.0 - distance_scale, pitch_offset) - previous) / delta

func _flight_lens_goal(settings: RicochetCameraSettings) -> Vector2:
	if not _flying or not settings.flight_speed_camera_enabled: return Vector2.ZERO
	var result := Vector2(-settings.flight_pullback_ratio, -settings.flight_pitch_drop) * _flight_speed_weight
	if settings.flight_charge_focus_enabled:
		var pitch := -settings.charge_pitch_drop if settings.charge_staging_enabled else 0.0
		result = Vector2(settings.charge_zoom_ratio, pitch) * get_flight_focus_weight()
	result.x -= _combat_focus.orbit_weight * settings.orbit_pullback_ratio
	return result

## 供场景后处理共用同一份平滑后的真实速度权重。
func get_flight_focus_weight() -> float:
	var settings := _camera.ricochet_camera_settings
	if not _flying or not settings or not settings.enabled or not settings.flight_speed_camera_enabled or not settings.flight_charge_focus_enabled: return 0.0
	return _flight_speed_weight * settings.flight_charge_focus_ratio * lerpf(1.0, 0.7, _combat_focus.orbit_weight)

func _begin_lens_handoff(lens: Vector2, velocity: Vector2, seconds: float, pitch_seconds: float) -> void:
	_begin_zoom_return(seconds)
	_lens_pitch_seconds = pitch_seconds
	_full_zoom_pulse = false
	_lens_handoff = true
	_handoff_lens_from = lens
	_handoff_lens_velocity = velocity
	_zoom_amount = lens.x
	distance_scale = 1.0 - lens.x

func _lens_return(from: float, velocity: float, age: float, seconds: float, opening := -1.0) -> float:
	if seconds <= 0.0: return 0.0
	var t := clampf(age / seconds, 0.0, 1.0)
	var remaining := 1.0 - opening if opening >= 0.0 else 2.0 * t * t * t - 3.0 * t * t + 1.0
	return from * remaining + velocity * seconds * (t * t * t - 2.0 * t * t + t)

func _on_launched(direction: Vector3, speed: float, _charge: float) -> void:
	if not _camera.ricochet_camera_settings or not _camera.ricochet_camera_settings.enabled: return
	var settings := _camera.ricochet_camera_settings
	var handoff := settings.charge_release_handoff_enabled and _charging
	var lens := Vector2(1.0 - distance_scale, pitch_offset)
	var lens_velocity := _lens_velocity
	var inherited_velocity := focus_velocity
	# 真实满蓄后立即松手时，渲染循环可能尚未采样满蓄边沿。
	if _charging and not _full_shake_seen and _charge >= 1.0:
		_trigger_full_shake(direction, _camera.ricochet_camera_settings)
	_restart_timeline()
	_begin_zoom_return(_camera.ricochet_camera_settings.charge_release_seconds)
	active = true
	_flying = true
	_age = 0.0
	_direction = direction
	_launch_speed = maxf(speed, 0.001)
	_last_speed = speed
	_launch_point = _camera._target_point()
	_speed_profile_enabled = settings.flight_speed_camera_enabled
	_charge_focus_profile_enabled = settings.flight_charge_focus_enabled
	_flight_speed_weight = settings.flight_speed_weight(speed) if _speed_profile_enabled else 0.0
	# 接住发射前已有的构图，再平滑交接，避免边走边蓄力时突然居中。
	_carry_from = _camera.focus - _launch_point
	carry = _carry_from
	if handoff or _speed_profile_enabled:
		# 从当前镜头接向实际余速的飞行构图，距离与俯角分段交接。
		_begin_lens_handoff(lens, lens_velocity, settings.charge_release_seconds, settings.charge_release_pitch_seconds)
	if handoff:
		_release_motion = true
		_begin_focus_handoff(inherited_velocity)

func _begin_focus_handoff(inherited_velocity: Vector3) -> void:
	_focus_handoff = true
	_focus_handoff_age = 0.0
	_focus_handoff_from = _camera.focus
	_focus_start_offset = _camera.focus - _camera._target_point()
	_focus_handoff_tangent = inherited_velocity
	framing = Vector2.ZERO
	_velocity = Vector2.ZERO
	carry = _focus_start_offset

func _on_impact_recorded(impact: RicochetImpact) -> void:
	if not active or not _flying: return
	var settings := _camera.ricochet_camera_settings
	if settings and settings.enabled:
		_impact_shot.start(impact, settings, _camera._short_side_span())

func _combat_strike(heading: Vector3, flying: bool, _reverse: bool) -> void:
	_combat_focus.begin_sword(heading, flying)

func _combat_sword_hit(enemy: WaveEnemy, _damage: float, flying: bool) -> void:
	var settings := _camera.ricochet_camera_settings
	if not flying or not _body.flying or not settings or not settings.combat_beat_enabled: return
	_combat_focus.sword_hit(enemy.global_position, enemy.dead)

func _combat_storm_patch(point: Vector3, hits: int, kills: int, flight_id: int) -> void:
	var settings := _camera.ricochet_camera_settings
	if not _body.flying or flight_id != _body.flight_serial or not settings or not settings.combat_beat_enabled: return
	_combat_focus.storm_patch(point, hits, kills, _player.global_position)

func _on_bounced(_point: Vector3, normal: Vector3) -> void:
	if not active or not _flying: return
	var settings := _camera.ricochet_camera_settings
	if not settings or not settings.enabled: return
	# 用前后真实速度差接住镜头运动，人物折返时镜头不会立刻跟着反向。
	var velocity_change := _direction * _last_speed - _body.direction * _body.flight_speed
	var impact := _body.last_impact
	if impact and impact.flight_id == _body.flight_serial and impact.point.is_equal_approx(_point):
		velocity_change = impact.incoming_velocity - impact.outgoing_velocity
	var view := Basis.looking_at(-_camera._orbit_offset(), Vector3.UP)
	_velocity += Vector2(velocity_change.dot(view.x), velocity_change.dot(view.y)) / _camera._short_side_span()
	_direction = _body.direction
	_last_speed = _body.flight_speed
	_bounce_age = 0.0
	if _focus_handoff: _begin_focus_handoff(focus_velocity)
	if _impact_age >= settings.impact_min_interval:
		_impact_age = 0.0
		_impact_direction = -normal
		_impact_strength = clampf(_body.flight_speed / _launch_speed, 0.0, 1.0)

func _on_finished(_reason: StringName) -> void:
	if not active: return
	var settings := _camera.ricochet_camera_settings
	if not settings:
		reset()
		return
	_return_seconds = settings.charge_cancel_seconds if _charging else settings.return_seconds
	var view := Basis.looking_at(-_camera._orbit_offset(), Vector3.UP)
	var span := _camera._short_side_span()
	var speed_return := _speed_profile_enabled or settings.flight_speed_camera_enabled
	if speed_return:
		# 吸收仍在播放的满蓄挤压；碰撞拉远继续由独立碰撞层收尾，避免叠算。
		_begin_lens_handoff(Vector2(1.0 - distance_scale, pitch_offset), _lens_velocity, _return_seconds, _return_seconds)
	elif _charging: _begin_zoom_return(settings.charge_cancel_seconds)
	_charging = false
	_flying = false
	_focus_handoff = false
	_return_age = 0.0
	_return_from = framing
	_return_velocity = _velocity
	_return_carry = carry
	if speed_return:
		# 反弹偏航已经改变投影基底，从实际世界焦点重建归位余量。
		_return_carry = _camera.focus - _camera._target_point() - collision_offset - (view.x * framing.x + view.y * framing.y) * span
	_impact_shot.release(0.10)
	_combat_focus.reset()

func advance(delta: float, point: Vector3, view: Basis, world_span: float, short_side: float) -> void:
	var settings := _camera.ricochet_camera_settings
	if not settings or not settings.enabled or not is_instance_valid(_player) or _player.current_health <= 0.0:
		reset()
		return
	if _charging and not settings.charge_focus_enabled: _on_finished(&"cancelled")
	if settings.charge_focus_enabled and _body.charging and not _charging: _on_state_changed(PlayerRicochet.State.CHARGING)
	if not _flying and _body.flying: _on_launched(_body.direction, _body.flight_speed, 0.0)
	if not active or _body.is_frozen(): return
	_age += delta
	_combat_focus.advance(delta, _body.orbiting, point, _body.orbit_presentation_center, settings)
	if _flying:
		if _speed_profile_enabled != settings.flight_speed_camera_enabled or _charge_focus_profile_enabled != settings.flight_charge_focus_enabled:
			_speed_profile_enabled = settings.flight_speed_camera_enabled
			_charge_focus_profile_enabled = settings.flight_charge_focus_enabled
			_begin_lens_handoff(Vector2(_zoom_amount, pitch_offset), _lens_velocity, settings.charge_release_seconds, settings.charge_release_pitch_seconds)
		var speed_goal := settings.flight_speed_weight(_body.flight_speed) if _speed_profile_enabled else 0.0
		_flight_speed_weight = lerpf(_flight_speed_weight, speed_goal, 1.0 - exp(-delta / maxf(settings.flight_speed_smoothing, 0.001)))
	var full_shake := _advance_full_shake(delta, settings, view, short_side)
	var charge_tremor := _advance_charge_tremor(delta, settings, short_side)
	_advance_zoom(delta, settings)
	_impact_shot.advance(delta, settings)
	collision_offset = _impact_shot.offset
	var rotation_goal := 0.35 if _camera._yaw_input_active else 1.0
	_impact_rotation_weight = move_toward(_impact_rotation_weight, rotation_goal, maxf(0.0, delta) / 0.06)
	yaw_offset = _impact_shot.yaw * _impact_rotation_weight
	roll_offset = _impact_shot.roll * _impact_rotation_weight
	collision_distance_scale = _impact_shot.pullback
	if _charging:
		# 焦点始终跟随当前人物；只渐消进入蓄力前的跟随余量。
		carry = _carry_from * exp(-(4.0 if settings.charge_staging_enabled else 1.0) * _age / maxf(settings.charge_focus_seconds, 0.001))
		if settings.charge_staging_enabled and carry.length_squared() < 0.00000001: carry = Vector3.ZERO
		var next := Vector2.ZERO
		if settings.charge_staging_enabled:
			next.x = sin(PI * _body.charge_fraction) * settings.charge_arc_ratio * smoothstep(0.0, 0.08, _age)
		if settings.charge_direction_bias_ratio > 0.0:
			next += _project(_body.direction, view) * settings.charge_direction_bias_ratio * smoothstep(0.65, 1.0, _body.charge_fraction)
			next = framing.lerp(next, 1.0 - exp(-delta / maxf(settings.charge_focus_seconds, 0.001)))
		if delta > 0.0: _velocity = (next - framing) / delta
		framing = next.limit_length(settings.max_offset_ratio)
		shake = (framing + full_shake + charge_tremor).limit_length(settings.max_offset_ratio) - framing
		return
	_bounce_age += delta
	_impact_age += delta
	if _flying:
		_direction = _body.direction
		_last_speed = _body.flight_speed
		if _focus_handoff:
			_focus_handoff_age += delta
			var seconds := maxf(settings.charge_release_framing_seconds, 0.001)
			var t := clampf(_focus_handoff_age / seconds, 0.0, 1.0)
			var goal := _flight_lead_goal(settings, view)
			framing = goal * smoothstep(0.0, 1.0, t)
			_velocity = goal * (6.0 * t - 6.0 * t * t) / seconds
			# 从已渲染的世界焦点续行，再交给当前插值人物；不预扣尚未呈现的飞行位移。
			carry = (_focus_handoff_from + _focus_handoff_tangent * _focus_handoff_age - point) * (1.0 - smoothstep(0.0, 1.0, t))
			# 合计构图保留原有上限；起手已有的跟随余量可以连续退回。
			var offset := framing + Vector2(carry.dot(view.x), carry.dot(view.y)) / world_span
			var initial := Vector2(_focus_start_offset.dot(view.x), _focus_start_offset.dot(view.y)).length() / world_span
			var cap := maxf(settings.max_offset_ratio, initial)
			var soft_start := (cap + initial) * 0.5
			var limited := offset
			if offset.length() > soft_start:
				var width := maxf(0.00001, cap - soft_start)
				limited = offset.normalized() * minf(cap, soft_start + width * (1.0 - exp(-(offset.length() - soft_start) / width)))
			var correction := (limited - offset) * world_span
			carry += view.x * correction.x + view.y * correction.y
			if t >= 1.0: _focus_handoff = false
		elif _age <= settings.launch_lag_seconds:
			var lag := (_launch_point - point) * (1.0 - settings.launch_follow_fraction)
			framing = Vector2(lag.dot(view.x), lag.dot(view.y)) / world_span
			_velocity = Vector2.ZERO
		else:
			var goal := _flight_lead_goal(settings, view)
			var seconds := settings.bounce_inertia_seconds if _bounce_age < settings.bounce_inertia_seconds else settings.lead_settle_seconds
			# 解析临界阻尼，保留反弹前的镜头位移速度，连续转弯也不硬切方向。
			var omega := 4.0 / maxf(seconds, 0.001)
			var error := framing - goal
			var tangent := _velocity + error * omega
			var decay := exp(-omega * delta)
			framing = goal + (error + tangent * delta) * decay
			_velocity = (_velocity - tangent * omega * delta) * decay
		if not _focus_handoff and not _release_motion:
			carry = _carry_from * (1.0 - smoothstep(0.0, settings.launch_lag_seconds + settings.lead_settle_seconds, _age))
	else:
		_return_age += delta
		var t := clampf(_return_age / maxf(_return_seconds, 0.001), 0.0, 1.0)
		framing = _return_from * (2.0 * t * t * t - 3.0 * t * t + 1.0) + _return_velocity * _return_seconds * (t * t * t - 2.0 * t * t + t)
		carry = _return_carry * (1.0 - smoothstep(0.0, 1.0, t))
		if t >= 1.0 and is_zero_approx(_zoom_amount) and is_zero_approx(pitch_offset) and not _lens_handoff and _charge_tremor_strength == 0.0 and (not (settings.charge_full_shake_enabled or settings.charge_staging_enabled) or _full_shake_age >= settings.charge_full_shake_seconds):
			reset()
			return
	framing = framing.limit_length(settings.max_offset_ratio)
	if framing.length() >= settings.max_offset_ratio and _velocity.dot(framing) > 0.0:
		_velocity -= framing.normalized() * _velocity.dot(framing.normalized())
	var impact_t := clampf(_impact_age / maxf(settings.impact_shake_seconds, 0.001), 0.0, 1.0)
	var wave := sin(impact_t * TAU * 1.5) * (1.0 - impact_t) * (1.0 - impact_t)
	# 曲线已按法向速度筛选冲击；极浅擦也不补回旧的等强度震动。
	if _impact_shot.active or (settings.impact_shot_enabled and (settings.impact_shot_curve != null or settings.impact_split_enabled)): wave = 0.0
	shake = _project(_impact_direction, view) * settings.impact_shake_pixels / maxf(short_side, 1.0) * _impact_strength * wave + full_shake + charge_tremor
	if not _camera.wave_shot_active and not _camera.hit_shot_active:
		shake += _impact_shot.screen_punch(view, short_side, settings)
	if not _impact_shot.active:
		shake += Vector2(_combat_focus.recoil.dot(view.x), _combat_focus.recoil.dot(view.y)) * settings.combat_beat_pixels / maxf(short_side, 1.0)
	# 震动与构图合计也遵守偏移上限，不因窄角连续反弹无限叠加。
	shake = (framing + shake).limit_length(settings.max_offset_ratio) - framing

func _project(direction: Vector3, view: Basis) -> Vector2:
	return Vector2(direction.dot(view.x), direction.dot(view.y)).normalized()

func _flight_lead_goal(settings: RicochetCameraSettings, view: Basis) -> Vector2:
	var weight := _flight_speed_weight if settings.flight_speed_camera_enabled else 1.0
	var goal := _project(_direction, view) * settings.lookahead_ratio * weight
	return _combat_focus.lead_goal(goal, view, _camera._short_side_span())
