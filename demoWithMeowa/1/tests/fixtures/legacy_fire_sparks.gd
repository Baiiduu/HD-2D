extends Node3D

## 沿真实路程布置少量火星候选；单张小卡片由 GPU 求轨迹，不包含火舌曲面。
const EMPTY := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)
static var _shape: QuadMesh
var batch: MultiMeshInstance3D
var material: ShaderMaterial
var count := 0
var _head := 0
var _births := PackedFloat64Array()
var _ends := PackedFloat64Array()
var _transforms: Array[Transform3D] = []
var _custom: Array[Color] = []
var _last_end := Vector3.INF
var _to_next := 0.0
var _serial := 0
var _bounds := AABB()

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if not _shape: _shape = QuadMesh.new()
	batch = MultiMeshInstance3D.new()
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	batch.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.use_custom_data = true
	batch.multimesh.mesh = _shape
	material = ShaderMaterial.new()
	material.shader = preload("res://shaders/combat/player_fire_sparks.gdshader")
	batch.material_override = material
	add_child(batch)
	_grow(64)
	set_process(false)
	hide()

func _grow(capacity: int) -> void:
	var transforms: Array[Transform3D] = []
	var custom: Array[Color] = []
	var births := PackedFloat64Array()
	var ends := PackedFloat64Array()
	for index in count:
		var slot := (_head + index) % _births.size()
		transforms.append(_transforms[slot])
		custom.append(_custom[slot])
		births.append(_births[slot])
		ends.append(_ends[slot])
	batch.multimesh.instance_count = capacity
	_births.resize(capacity)
	_ends.resize(capacity)
	_transforms.resize(capacity)
	_custom.resize(capacity)
	_head = 0
	for index in capacity:
		_transforms[index] = transforms[index] if index < count else EMPTY
		batch.multimesh.set_instance_transform(index, _transforms[index])
		if index < count:
			_custom[index] = custom[index]
			_births[index] = births[index]
			_ends[index] = ends[index]
			batch.multimesh.set_instance_custom_data(index, custom[index])

func deposit(start: Vector3, end: Vector3, seconds: float, clock: float, settings: PlayerActionVisuals) -> void:
	var length := start.distance_to(end)
	if length <= 0.00001: return
	var spacing := maxf(0.15, settings.fire_trail_spark_spacing)
	if not _last_end.is_finite() or _last_end.distance_to(start) > 0.03: _to_next = spacing * 0.5
	var heading := (end - start).normalized()
	var side := Vector3.UP.cross(heading).normalized()
	var width := settings.fire_trail_width * 1.6
	var lifetime := 0.42
	while _to_next <= length + 0.000001:
		if count == _births.size(): _grow(_births.size() * 2)
		var fraction := clampf(_to_next / length, 0.0, 1.0)
		var point := start.lerp(end, fraction)
		var slot := (_head + count) % _births.size()
		_births[slot] = clock + seconds * fraction
		_ends[slot] = _births[slot] + lifetime
		_transforms[slot] = Transform3D(Basis(side * width, Vector3.UP * settings.fire_trail_spark_height, heading * width), point)
		_custom[slot] = Color(_births[slot], lifetime, fmod(_serial * 0.618033989, 1.0), settings.fire_trail_width)
		batch.multimesh.set_instance_transform(slot, _transforms[slot])
		batch.multimesh.set_instance_custom_data(slot, _custom[slot])
		var area := AABB(point, Vector3.ZERO).grow(width * 2.0 + settings.fire_trail_spark_height)
		_bounds = area if count == 0 else _bounds.merge(area)
		count += 1
		_serial += 1
		_to_next += spacing
	_to_next -= length
	_last_end = end
	batch.custom_aabb = _bounds
	advance(clock, settings)

func advance(clock: float, settings: PlayerActionVisuals) -> void:
	if not settings.fire_trail_flow_enabled or settings.fire_trail_spark_amount <= 0.0 or not settings.fire_trail_brush:
		clear()
		return
	material.set_shader_parameter("effect_clock", clock)
	material.set_shader_parameter("energy", settings.fire_trail_energy)
	material.set_shader_parameter("spark_amount", settings.fire_trail_spark_amount)
	material.set_shader_parameter("body_mask_margin_pixels", settings.fire_trail_body_clearance_pixels)
	material.set_shader_parameter("pixels_per_meter", settings.fire_trail_pixels_per_meter)
	material.set_shader_parameter("fire_brush", settings.fire_trail_brush)
	material.set_shader_parameter("flow_strength", settings.fire_trail_flow_strength)
	material.set_shader_parameter("flow_speed", settings.fire_trail_flow_speed)
	var region := settings.fire_trail_brush_region
	material.set_shader_parameter("brush_region", Vector4(region.position.x, region.position.y, region.size.x, region.size.y))
	while count > 0 and clock >= _ends[_head]:
		_transforms[_head] = EMPTY
		batch.multimesh.set_instance_transform(_head, EMPTY)
		_head = (_head + 1) % _births.size()
		count -= 1
	visible = count > 0

func clear() -> void:
	for index in count:
		var slot := (_head + index) % _births.size()
		_transforms[slot] = EMPTY
		batch.multimesh.set_instance_transform(slot, EMPTY)
	_head = 0
	count = 0
	_last_end = Vector3.INF
	_to_next = 0.0
	_serial = 0
	_bounds = AABB()
	material.set_shader_parameter("body_mask_enabled", false)
	hide()
