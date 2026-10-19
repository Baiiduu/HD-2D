class_name PlayerMotionFeedback
extends Node3D

## 人物姿态与反弹气流只消费真实运动，空闲不处理，不参与伤害或位移。
const AIR_SHADER := preload("res://shaders/combat/player_departure_airflow.gdshader")
var lean := Vector3.ZERO
var _player: Player
var _body: PlayerRicochet
var _impact: RicochetImpact
var _impact_age := 1000.0
var _air_impact: RicochetImpact
var _air_spacing_left := 0.0
var _active: Array[Dictionary] = []
var _pool: Array[MeshInstance3D] = []
var _quads: Dictionary = {}
var _materials: Dictionary = {}
var _foot_texture: Texture2D
var _foot_pixel := 0.0

func _ready() -> void:
	_player = get_parent() as Player
	_body = _player.body_ricochet
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_priority = 2 # 人物选帧、受光之后，残影采样之前。
	_body.launched.connect(_launched)
	_body.impact_recorded.connect(_collided)
	_body.flight_segment_travelled.connect(_travelled)
	_body.finished.connect(_finished)
	if is_instance_valid(_body._session): _body._session.phase_changed.connect(_phase)
	set_process(false)

func _launched(_direction: Vector3, _speed: float, _charge: float) -> void:
	_impact = null
	_air_impact = null
	var settings := _player.action_visuals
	if not settings or (not settings.motion_feedback_enabled and not settings.departure_airflow_enabled):
		clear()
		return
	set_process(true)

func _collided(impact: RicochetImpact) -> void:
	var settings := _player.action_visuals
	if not settings or (not settings.motion_feedback_enabled and not settings.departure_airflow_enabled): return
	_impact = impact
	_impact_age = 0.0
	_air_impact = impact
	_air_spacing_left = 0.0
	set_process(true)

func _finished(_reason: StringName) -> void:
	_impact = null
	_air_impact = null
	set_process(not lean.is_zero_approx() or not _active.is_empty())

func _phase(phase: WavePrototype.Phase) -> void:
	if phase != WavePrototype.Phase.BATTLE: clear()

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	var settings := _player.action_visuals
	if not settings or _player.current_health <= 0.0 or (not settings.motion_feedback_enabled and not settings.departure_airflow_enabled):
		clear()
		return
	if _body.is_frozen(): return
	_impact_age += maxf(delta, 0.0)
	var goal := Vector3.ZERO
	if settings.motion_feedback_enabled and _body.flying:
		goal = _target_lean(_body.direction, _body.flight_speed, _impact_age)
	var seconds := 0.025 if _body.flying else settings.lean_return_seconds * 0.25
	lean = lean.lerp(goal, 1.0 - exp(-maxf(delta, 0.0) / maxf(seconds, 0.001)))
	if lean.length_squared() < 0.00000001: lean = Vector3.ZERO
	_apply_pose()
	for index in range(_active.size() - 1, -1, -1):
		var item := _active[index]
		if not settings.departure_airflow_enabled:
			_recycle(index)
			continue
		if item.presented: item.age += maxf(0.0, delta)
		item.presented = true
		if item.age >= item.duration:
			_recycle(index)
		else:
			item.mesh.set_instance_shader_parameter("progress", item.age / item.duration)
	if lean.is_zero_approx() and _active.is_empty() and (not _body.flying or not settings.motion_feedback_enabled): set_process(false)

func _target_lean(heading: Vector3, speed: float, age: float) -> Vector3:
	var settings := _player.action_visuals
	if not settings or not settings.motion_feedback_enabled: return Vector3.ZERO
	if _impact and age < settings.impact_lean_hold + settings.impact_lean_turn:
		var weight := smoothstep(settings.impact_lean_hold, settings.impact_lean_hold + settings.impact_lean_turn, age)
		heading = _impact.incoming_velocity.normalized().lerp(heading, weight)
		speed = lerpf(_impact.incoming_velocity.length(), speed, weight)
	return Vector3.UP.cross(heading) * deg_to_rad(settings.flight_lean_degrees) * clampf(speed / maxf(settings.motion_reference_speed, 0.001), 0.0, 1.0)

func pose_for_segment(heading: Vector3, flight_time: float) -> Vector3:
	return _target_lean(heading, _body.flight_speed, maxf(0.0, flight_time - _impact.seconds) if _impact else 1000.0)

func _apply_pose() -> void:
	var pivot := foot_pivot(_player.get_global_transform_interpolated().origin)
	var sprite := _player.sprite
	if sprite.has_method("set_motion_pose"):
		sprite.set_motion_pose(lean, pivot)
	else:
		sprite.set_meta("motion_lean", lean)
		sprite.set_meta("motion_pivot", pivot)

## 使用稳定 idle 母帧的透明脚边；动画中抬脚不改变枢轴。
func foot_pivot(point: Vector3) -> Vector3:
	var sprite := _player.sprite
	var reference := sprite.texture
	if _player.animations:
		for name in [&"idle", &"idle_front", &"idle_side"]:
			if _player.animations.has_animation(name):
				reference = _player.animations.get_frame_texture(name, 0)
				break
	if reference != _foot_texture:
		_foot_texture = reference
		var image := reference.get_image() if reference else null
		_foot_pixel = reference.get_height() * 0.5 - image.get_used_rect().end.y if image and not image.is_empty() else 0.0
	var height := sprite.get_global_transform_interpolated().origin.y - _player.get_global_transform_interpolated().origin.y
	height += (_foot_pixel + sprite.offset.y) * sprite.pixel_size * sprite.global_basis.y.length()
	return point + Vector3.UP * maxf(0.015, height)

func _travelled(start: Vector3, end: Vector3, heading: Vector3, seconds: float) -> void:
	var settings := _player.action_visuals
	if not settings or not settings.departure_airflow_enabled or not _air_impact or not settings.departure_airflow_texture: return
	if _air_impact.flight_id != _body.flight_serial: return
	var elapsed := maxf(0.0, _body.flight_elapsed - seconds - _air_impact.seconds)
	var allowed := minf(seconds, settings.departure_airflow_seconds - elapsed)
	if allowed <= 0.0: return
	var strength := _air_impact.strength(settings.motion_reference_speed)
	if strength < 0.06: return
	var length := start.distance_to(end)
	if length < 0.00001: return
	# 按真实减速积分裁短发射窗口；不会把气流从墙前连到墙后。
	var timing := _body.motion_timing(seconds)
	var reach := minf(length, maxf(0.0, timing.x * allowed - 0.5 * timing.y * allowed * allowed))
	while _air_spacing_left <= reach:
		_spawn_airflow(start.lerp(end, _air_spacing_left / length), heading, strength)
		_air_spacing_left += maxf(0.1, settings.departure_airflow_spacing)
	_air_spacing_left = maxf(0.0, _air_spacing_left - reach)

func _spawn_airflow(point: Vector3, heading: Vector3, strength: float) -> void:
	var settings := _player.action_visuals
	var texture := settings.departure_airflow_texture
	var pixel := _player.sprite.pixel_size * _player.sprite.global_basis.x.length()
	var size := texture.get_size() * pixel
	if not _quads.has(size):
		var quad := QuadMesh.new()
		quad.size = size
		_quads[size] = quad
	if not _materials.has(texture):
		var material := ShaderMaterial.new()
		material.shader = AIR_SHADER
		material.set_shader_parameter("airflow_texture", texture)
		_materials[texture] = material
	var side := Vector3.UP.cross(heading).normalized()
	for sign_value in [-1.0, 1.0]:
		var mesh: MeshInstance3D = _pool.pop_back() if not _pool.is_empty() else MeshInstance3D.new()
		if not mesh.is_inside_tree():
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			mesh.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			add_child(mesh)
		mesh.mesh = _quads[size]
		mesh.material_override = _materials[texture]
		# 贴地的真实方向平面，镜头转动不会把尾迹转向或拖走。
		mesh.global_transform = Transform3D(Basis(heading, side, Vector3.UP), point + Vector3.UP * 0.08 - heading * size.x * 0.30 + side * sign_value * 0.20)
		mesh.set_instance_shader_parameter("progress", 0.0)
		mesh.set_instance_shader_parameter("opacity", settings.departure_airflow_opacity * strength)
		var normal := _air_impact.normal
		mesh.set_instance_shader_parameter("wall_plane", Vector4(normal.x, normal.y, normal.z, -normal.dot(_air_impact.point)))
		mesh.show()
		_active.append({"mesh": mesh, "age": 0.0, "duration": settings.departure_airflow_lifetime, "presented": false})
	set_process(true)

func _recycle(index: int) -> void:
	var mesh: MeshInstance3D = _active[index].mesh
	mesh.hide()
	_pool.append(mesh)
	_active.remove_at(index)

func active_airflow_count() -> int:
	return _active.size()

func airflow_ages() -> Array:
	return _active.map(func(item): return item.age)

func clear() -> void:
	lean = Vector3.ZERO
	_impact = null
	_air_impact = null
	for index in range(_active.size() - 1, -1, -1): _recycle(index)
	if is_instance_valid(_player) and is_instance_valid(_player.sprite): _apply_pose()
	set_process(false)
