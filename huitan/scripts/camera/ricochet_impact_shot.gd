class_name RicochetImpactShot
extends RefCounted

## 连续的附加机位轨迹；保存世界方向，Q/E 仍控制基础朝向。
var active := false
var offset := Vector3.ZERO
var velocity := Vector3.ZERO
var yaw := 0.0
var roll := 0.0
var pullback := 0.0
var _angular_velocity := Vector3.ZERO
var _points: Array[Vector3] = []
var _angles: Array[Vector3] = []
var _tangents: Array[Vector3] = []
var _angular_tangents: Array[Vector3] = []
var _age := 0.0
var _duration := 0.32
var _limit := 0.0
var _serial := -1
var _side := 1.0
var _releasing := false
var _response_curve: Curve
var _response_offset := Vector3.ZERO
var _response_angles := Vector3.ZERO
var _split := false
var _punch_age := 1000.0
var _punch_direction := Vector3.ZERO
var _punch_strength := 0.0

func clear() -> void:
	active = false
	offset = Vector3.ZERO
	velocity = Vector3.ZERO
	yaw = 0.0
	roll = 0.0
	pullback = 0.0
	_angular_velocity = Vector3.ZERO
	_points.clear()
	_angles.clear()
	_response_curve = null
	_punch_age = 1000.0
	_punch_strength = 0.0

func start(impact: RicochetImpact, settings: RicochetCameraSettings, span: float) -> void:
	if impact.serial <= _serial or not settings.impact_shot_enabled: return
	_serial = impact.serial
	var strength := impact.strength(settings.impact_reference_speed)
	if strength < 0.06: return
	_split = settings.impact_split_enabled
	if _split and _punch_age >= settings.impact_min_interval:
		_punch_age = 0.0
		_punch_direction = -impact.normal
		_punch_strength = strength
	if active and _age < 0.10: strength *= 0.75
	_side = impact.turn_side(_side)
	_duration = settings.impact_shot_seconds * lerpf(0.6, 1.0, strength)
	_limit = maxf(offset.length(), span * settings.impact_shot_offset_ratio * strength)
	var incoming := impact.incoming_velocity.normalized()
	var outgoing := impact.outgoing_velocity.normalized()
	var lateral := Vector3.UP.cross(outgoing) * _side
	_points = [offset, incoming * _limit * 0.75, (outgoing * 0.25 + lateral * 0.65) * _limit, Vector3.ZERO]
	var turn := sqrt(clampf((1.0 - incoming.dot(outgoing)) * 0.5, 0.0, 1.0))
	var peak := Vector3(settings.impact_shot_yaw_degrees * _side * turn,
		-settings.impact_shot_roll_degrees * _side, settings.impact_shot_pullback_ratio) * strength
	if _split:
		# 先接住入射惯性，再平滑带向真实出射方向；转角不跟随短冲击往返抖动。
		_points = [offset, incoming * _limit * 0.25, outgoing * _limit * 0.65, Vector3.ZERO]
	_angles = [Vector3(yaw, roll, pullback), peak * 0.25, peak, Vector3.ZERO]
	_tangents = _velocities(_points, velocity)
	_angular_tangents = _velocities(_angles, _angular_velocity)
	_response_curve = settings.impact_shot_curve if not _split else null
	if _response_curve:
		# 轻压与小回弹只沿真实碰撞法向；旧机位及速度独立平滑退去，连续碰撞不跳帧。
		_response_offset = -impact.normal * span * settings.impact_shot_offset_ratio * strength
		_response_angles = peak
		_points = [offset, Vector3.ZERO]
		_angles = [Vector3(yaw, roll, pullback), Vector3.ZERO]
		_tangents = [velocity, Vector3.ZERO]
		_angular_tangents = [_angular_velocity, Vector3.ZERO]
	_age = 0.0
	_releasing = false
	active = true

func release(seconds := 0.10) -> void:
	if not active: return
	_points = [offset, Vector3.ZERO]
	_angles = [Vector3(yaw, roll, pullback), Vector3.ZERO]
	_tangents = [velocity, Vector3.ZERO]
	_angular_tangents = [_angular_velocity, Vector3.ZERO]
	_duration = maxf(seconds, 0.02)
	_age = 0.0
	_releasing = true

func _velocities(points: Array[Vector3], initial: Vector3) -> Array[Vector3]:
	return [initial, (points[2] - points[0]) / (_duration * (0.55 if _split else 0.48)) * 0.65,
		(points[3] - points[1]) / (_duration * (0.78 if _split else 0.82)) * 0.65, Vector3.ZERO]

func screen_punch(view: Basis, short_side: float, settings: RicochetCameraSettings) -> Vector2:
	if not active or not settings.impact_split_enabled or _punch_age >= settings.impact_punch_seconds: return Vector2.ZERO
	var t := clampf(_punch_age / maxf(settings.impact_punch_seconds, 0.001), 0.0, 1.0)
	var direction := Vector2(_punch_direction.dot(view.x), _punch_direction.dot(view.y)).normalized()
	if direction.is_zero_approx(): direction = Vector2.UP
	return direction * sin(PI * t) * _punch_strength * settings.impact_punch_pixels / maxf(short_side, 1.0)

func advance(delta: float, settings: RicochetCameraSettings) -> void:
	if not active: return
	if not settings.impact_shot_enabled:
		clear()
		return
	_punch_age += maxf(0.0, delta)
	_age += maxf(0.0, delta)
	if _age >= _duration:
		clear()
		return
	var curved := _response_curve != null and not _releasing
	var times: Array = [0.0, _duration] if _releasing or curved else [0.0, _duration * 0.18, _duration * 0.48, _duration]
	if _split and not _releasing: times = [0.0, _duration * 0.22, _duration * 0.55, _duration]
	var index := 0
	while index < times.size() - 2 and _age > times[index + 1]: index += 1
	var length := maxf(times[index + 1] - times[index], 0.001)
	var t := clampf((_age - times[index]) / length, 0.0, 1.0)
	var position := _sample(_points[index], _points[index + 1], _tangents[index], _tangents[index + 1], t, length)
	var angles := _sample(_angles[index], _angles[index + 1], _angular_tangents[index], _angular_tangents[index + 1], t, length)
	if curved:
		var pulse := _response_curve.sample(t)
		var low := maxf(0.0, t - 0.001)
		var high := minf(1.0, t + 0.001)
		var slope := 0.0
		if t > 0.0 and t < 1.0: slope = (_response_curve.sample(high) - _response_curve.sample(low)) / ((high - low) * length)
		position[0] += _response_offset * pulse
		position[1] += _response_offset * slope
		angles[0] += _response_angles * pulse
		angles[1] += _response_angles * slope
	offset = position[0].limit_length(_limit)
	velocity = position[1]
	yaw = clampf(angles[0].x, -settings.impact_shot_yaw_degrees, settings.impact_shot_yaw_degrees)
	roll = clampf(angles[0].y, -settings.impact_shot_roll_degrees, settings.impact_shot_roll_degrees)
	pullback = clampf(angles[0].z, 0.0, settings.impact_shot_pullback_ratio)
	_angular_velocity = angles[1]

static func _sample(a: Vector3, b: Vector3, va: Vector3, vb: Vector3, t: float, seconds: float) -> Array[Vector3]:
	var t2 := t * t
	var t3 := t2 * t
	return [a * (2.0 * t3 - 3.0 * t2 + 1.0) + va * seconds * (t3 - 2.0 * t2 + t) + b * (-2.0 * t3 + 3.0 * t2) + vb * seconds * (t3 - t2),
		(a * (6.0 * t2 - 6.0 * t) + b * (-6.0 * t2 + 6.0 * t)) / seconds + va * (3.0 * t2 - 4.0 * t + 1.0) + vb * (3.0 * t2 - 2.0 * t)]
