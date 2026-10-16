class_name PlayerFireTrail
extends Node3D

## 三阶段地面火带，仅消费真实弹射路段。无伤害、碰撞、额外灯光或怪物覆盖通道。
const SHADER := preload("res://shaders/combat/player_fire_trail.gdshader")
const EMPTY := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
const INITIAL_CAPACITY := 128
var _player: Player
var _body: PlayerRicochet
var _mesh: MultiMeshInstance3D
var _material: ShaderMaterial
var _births := PackedFloat64Array()
var _transforms: Array[Transform3D] = []
var _custom: Array[Color] = []
var _timing := Vector4(-1, -1, -1, -1)
var _pixels := -1.0
var _head := 0
var _count := 0
var _clock := 0.0
var _duration := 0.0
var _bounds := AABB()

func _ready() -> void:
	_player = get_parent() as Player
	_body = _player.body_ricochet
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_body.flight_segment_travelled.connect(_travelled)
	if is_instance_valid(_body._session):
		_body._session.phase_changed.connect(_phase_changed)
		_body._session.wave_clearing.connect(clear)
		_body._session.run_started.connect(clear)
	clear()

func _phase_changed(phase: int) -> void:
	if phase != WavePrototype.Phase.BATTLE: clear()

func _prepare() -> void:
	if _mesh: return
	_mesh = MultiMeshInstance3D.new()
	_mesh.name = "GroundRibbon"
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_mesh.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_mesh.multimesh = MultiMesh.new()
	_mesh.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_mesh.multimesh.use_custom_data = true
	_mesh.multimesh.mesh = QuadMesh.new()
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_mesh.material_override = _material
	add_child(_mesh)
	_grow(INITIAL_CAPACITY)

func _grow(capacity: int) -> void:
	var transforms: Array[Transform3D] = []
	var data: Array[Color] = []
	var births := PackedFloat64Array()
	for index in _count:
		var slot := (_head + index) % _births.size()
		transforms.append(_transforms[slot])
		data.append(_custom[slot])
		births.append(_births[slot])
	_mesh.multimesh.instance_count = capacity
	_births.resize(capacity)
	_transforms.resize(capacity)
	_custom.resize(capacity)
	_head = 0
	for index in capacity:
		_transforms[index] = transforms[index] if index < _count else EMPTY
		_mesh.multimesh.set_instance_transform(index, _transforms[index])
		if index < _count:
			_custom[index] = data[index]
			_mesh.multimesh.set_instance_custom_data(index, data[index])
			_births[index] = births[index]

func _configure() -> void:
	var settings := _player.action_visuals
	_duration = settings.fire_trail_fresh_seconds + settings.fire_trail_burn_seconds + settings.fire_trail_ember_seconds
	var timing := Vector4(settings.fire_trail_fresh_seconds, settings.fire_trail_burn_seconds, settings.fire_trail_ember_seconds, settings.fire_trail_energy)
	if timing == _timing and _pixels == settings.fire_trail_pixels_per_meter: return
	_timing = timing
	_pixels = settings.fire_trail_pixels_per_meter
	_material.set_shader_parameter("fresh_seconds", settings.fire_trail_fresh_seconds)
	_material.set_shader_parameter("burn_seconds", settings.fire_trail_burn_seconds)
	_material.set_shader_parameter("ember_seconds", settings.fire_trail_ember_seconds)
	_material.set_shader_parameter("energy", settings.fire_trail_energy)
	_material.set_shader_parameter("pixels_per_meter", settings.fire_trail_pixels_per_meter)

func _travelled(start: Vector3, end: Vector3, _heading: Vector3, seconds: float) -> void:
	var settings := _player.action_visuals
	if not settings or not settings.show_fire_trail or _body.is_frozen(): return
	if not start.is_finite() or not end.is_finite() or not is_finite(seconds) or seconds <= 0.0: return
	var length := start.distance_to(end)
	if length <= 0.00001 or settings.fire_trail_width <= 0.0: return
	_prepare()
	_configure()
	if _count == _births.size(): _grow(_births.size() * 2)
	# 根节点脚底高度来自真实弹射支撑面；地面层不朝向相机，不附着人物。
	var offset := Vector3.UP * (0.014 - _body._foot_offset)
	if _body._path.data:
		start = _body._path.ground_position(start) + Vector3.UP * 0.014
		end = _body._path.ground_position(end) + Vector3.UP * 0.014
	else:
		start += offset
		end += offset
	var heading := (end - start).normalized()
	var side := Vector3(heading.z, 0.0, -heading.x).normalized()
	var width := settings.fire_trail_width
	var basis := Basis(heading * (length + width), side * width, heading.cross(side).normalized())
	var slot := (_head + _count) % _births.size()
	_births[slot] = _clock + seconds
	_transforms[slot] = Transform3D(basis, (start + end) * 0.5)
	_custom[slot] = Color(_clock, seconds, length, width)
	_mesh.multimesh.set_instance_transform(slot, _transforms[slot])
	_mesh.multimesh.set_instance_custom_data(slot, _custom[slot])
	var area := AABB(start, Vector3.ZERO).expand(end).grow(width)
	_bounds = area if _count == 0 else _bounds.merge(area)
	_mesh.custom_aabb = _bounds
	_count += 1
	_material.set_shader_parameter("effect_clock", _clock)
	show()
	set_process(true)

func _process(delta: float) -> void:
	if not _player.action_visuals or not _player.action_visuals.show_fire_trail or _player.current_health <= 0.0:
		clear()
		return
	if _body.is_frozen(): return
	_clock += maxf(0.0, delta)
	_configure()
	_material.set_shader_parameter("effect_clock", _clock)
	while _count > 0 and _clock >= _births[_head] + _duration:
		_transforms[_head] = EMPTY
		_mesh.multimesh.set_instance_transform(_head, EMPTY)
		_head = (_head + 1) % _births.size()
		_count -= 1
	if _count == 0: clear()

func clear() -> void:
	if _mesh:
		for index in _count:
			var slot := (_head + index) % _births.size()
			_transforms[slot] = EMPTY
			_mesh.multimesh.set_instance_transform(slot, EMPTY)
	_head = 0
	_count = 0
	_clock = 0.0
	_bounds = AABB()
	hide()
	set_process(false)
