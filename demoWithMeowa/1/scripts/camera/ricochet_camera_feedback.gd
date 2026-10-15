class_name RicochetCameraFeedback
extends RefCounted

## 镜头局部时间线，不改人物速度、输入、伤害时钟或 Engine.time_scale。
var active := false
var framing := Vector2.ZERO
var shake := Vector2.ZERO
var carry := Vector3.ZERO
var _camera: FollowCamera
var _player: Player
var _body: PlayerRicochet
var _flying := false
var _age := 0.0
var _return_age := 0.0
var _return_from := Vector2.ZERO
var _return_velocity := Vector2.ZERO
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
	_body.launched.connect(_on_launched)
	_body.wall_bounced.connect(_on_bounced)
	_body.finished.connect(_on_finished)

func dispose() -> void:
	if is_instance_valid(_body):
		_body.launched.disconnect(_on_launched)
		_body.wall_bounced.disconnect(_on_bounced)
		_body.finished.disconnect(_on_finished)
	reset()

func follows(player: Node3D) -> bool:
	return _player == player and is_instance_valid(_body)

func reset() -> void:
	active = false
	_flying = false
	framing = Vector2.ZERO
	shake = Vector2.ZERO
	carry = Vector3.ZERO
	_velocity = Vector2.ZERO
	_impact_age = 1000.0
	_bounce_age = 1000.0

func _on_launched(direction: Vector3, speed: float, _charge: float) -> void:
	if not _camera.ricochet_camera_settings or not _camera.ricochet_camera_settings.enabled: return
	reset()
	active = true
	_flying = true
	_age = 0.0
	_direction = direction
	_launch_speed = maxf(speed, 0.001)
	_last_speed = speed
	_launch_point = _camera._target_point()
	# 接住发射前已有的构图，再平滑交接，避免边走边蓄力时突然居中。
	_carry_from = _camera.focus - _launch_point
	carry = _carry_from

func _on_bounced(_point: Vector3, normal: Vector3) -> void:
	if not active or not _flying: return
	var settings := _camera.ricochet_camera_settings
	if not settings or not settings.enabled: return
	# 用前后真实速度差接住镜头运动，人物折返时镜头不会立刻跟着反向。
	var velocity_change := _direction * _last_speed - _body.direction * _body.flight_speed
	var view := Basis.looking_at(-_camera._orbit_offset(), Vector3.UP)
	_velocity += Vector2(velocity_change.dot(view.x), velocity_change.dot(view.y)) / _camera._short_side_span()
	_direction = _body.direction
	_last_speed = _body.flight_speed
	_bounce_age = 0.0
	if _impact_age >= settings.impact_min_interval:
		_impact_age = 0.0
		_impact_direction = -normal
		_impact_strength = clampf(_body.flight_speed / _launch_speed, 0.0, 1.0)

func _on_finished(_reason: StringName) -> void:
	if not active: return
	_flying = false
	_return_age = 0.0
	_return_from = framing
	_return_velocity = _velocity

func advance(delta: float, point: Vector3, view: Basis, world_span: float, short_side: float) -> void:
	var settings := _camera.ricochet_camera_settings
	if not settings or not settings.enabled or not is_instance_valid(_player) or _player.current_health <= 0.0:
		reset()
		return
	if not active and _body.flying: _on_launched(_body.direction, _body.flight_speed, 0.0)
	if not active or _body.is_frozen(): return
	_age += delta
	_bounce_age += delta
	_impact_age += delta
	if _flying:
		_direction = _body.direction
		_last_speed = _body.flight_speed
		if _age <= settings.launch_lag_seconds:
			var lag := (_launch_point - point) * (1.0 - settings.launch_follow_fraction)
			framing = Vector2(lag.dot(view.x), lag.dot(view.y)) / world_span
			_velocity = Vector2.ZERO
		else:
			var goal := _project(_direction, view) * settings.lookahead_ratio
			var seconds := settings.bounce_inertia_seconds if _bounce_age < settings.bounce_inertia_seconds else settings.lead_settle_seconds
			# 解析临界阻尼，保留反弹前的镜头位移速度，连续转弯也不硬切方向。
			var omega := 4.0 / maxf(seconds, 0.001)
			var error := framing - goal
			var tangent := _velocity + error * omega
			var decay := exp(-omega * delta)
			framing = goal + (error + tangent * delta) * decay
			_velocity = (_velocity - tangent * omega * delta) * decay
	else:
		_return_age += delta
		var t := clampf(_return_age / maxf(settings.return_seconds, 0.001), 0.0, 1.0)
		framing = _return_from * (2.0 * t * t * t - 3.0 * t * t + 1.0) + _return_velocity * settings.return_seconds * (t * t * t - 2.0 * t * t + t)
		if t >= 1.0:
			reset()
			return
	framing = framing.limit_length(settings.max_offset_ratio)
	if framing.length() >= settings.max_offset_ratio and _velocity.dot(framing) > 0.0:
		_velocity -= framing.normalized() * _velocity.dot(framing.normalized())
	carry = _carry_from * (1.0 - smoothstep(0.0, settings.launch_lag_seconds + settings.lead_settle_seconds, _age))
	var impact_t := clampf(_impact_age / maxf(settings.impact_shake_seconds, 0.001), 0.0, 1.0)
	var wave := sin(impact_t * TAU * 1.5) * (1.0 - impact_t) * (1.0 - impact_t)
	shake = _project(_impact_direction, view) * settings.impact_shake_pixels / maxf(short_side, 1.0) * _impact_strength * wave
	# 震动与构图合计也遵守偏移上限，不因窄角连续反弹无限叠加。
	shake = (framing + shake).limit_length(settings.max_offset_ratio) - framing

func _project(direction: Vector3, view: Basis) -> Vector2:
	return Vector2(direction.dot(view.x), direction.dot(view.y)).normalized()
