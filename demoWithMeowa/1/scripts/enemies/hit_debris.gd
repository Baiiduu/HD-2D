extends MultiMeshInstance3D
## 单批原生像素碎屑；闲置隐藏，仅发射与批量回收时写实例数据。
const SHADER = preload("res://shaders/combat/hit_debris.gdshader")
const TEXTURE = preload("res://assets/meowa/combat/body_bounce/bounce_atlas.png")
const CAPACITY := 16384
const RECLAIM_MIN := 32
## 创建前配置；人物反弹使用小批次，怪潮命中保留原容量。
var capacity := CAPACITY
var clock := 0.0
var emitted := 0
var active: bool:
	get: return visible and clock < _until
var _until := 0.0
var _cursor := 0
var _written := 0
var _random := RandomNumberGenerator.new()
var _transforms: Array[Transform3D] = []
var _colors := PackedColorArray()
var _launches := PackedColorArray()
var _expires := PackedFloat64Array()
var _next_expiry := INF

func _ready() -> void:
	capacity = clampi(capacity, 1, CAPACITY)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_random.randomize()
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = QuadMesh.new()
	multimesh.mesh.size = Vector2.ONE
	multimesh.instance_count = capacity
	multimesh.visible_instance_count = 0
	_transforms.resize(capacity)
	_colors.resize(capacity)
	_launches.resize(capacity)
	_expires.resize(capacity)
	material_override = CombatEffectLayer.material(SHADER)
	CombatEffectLayer.set_parameter(material_override, &"spark_texture", TEXTURE)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	global_transform = Transform3D.IDENTITY
	custom_aabb = AABB(Vector3(-256, -32, -256), Vector3(512, 128, 512))
	hide()
	set_process(false)

func burst(point: Vector3, direction: Vector3, pixel: float, settings: PlayerActionVisuals, lethal := false) -> void:
	if not active: clear()
	show()
	var count := clampi(settings.hit_debris_count, 1, 32)
	if lethal: count = mini(count * 3 / 2, 48)
	for index in count:
		var velocity := launch_velocity(direction, settings.hit_debris_speed_multiplier * (1.2 if lethal else 1.0))
		var life := clampf(settings.hit_debris_seconds, 0.15, 0.6) * _random.randf_range(0.8, 1.0)
		var size := pixel * 6.0 * _random.randf_range(1.1 if lethal else 0.9, 1.7 if lethal else 1.5)
		_emit(point, velocity, size, life, _random.randf_range(0.86, 1.0))
	multimesh.visible_instance_count = _written

func rebound(point: Vector3, impact: RicochetImpact, pixel: float, settings: PlayerActionVisuals) -> void:
	var strength := impact.strength(settings.motion_reference_speed)
	if strength < 0.06 or pixel <= 0.0: return
	if not active: clear()
	show()
	var normal := impact.normal
	normal.y = 0.0
	normal = normal.normalized()
	var side := Vector3.UP.cross(normal)
	var outgoing := impact.outgoing_velocity.normalized()
	var count := clampi(roundi(settings.bounce_particle_count * lerpf(0.4, 1.0, strength)), 1, 16)
	for index in count:
		# 法向分量始终朝墙外，出射趋势只改变扇形重心；不消费战斗随机流。
		var heading := (normal * _random.randf_range(0.8, 1.3) + side * _random.randf_range(-0.9, 0.9) + outgoing * 0.35).normalized()
		var speed := settings.bounce_particle_speed * lerpf(0.45, 1.0, strength)
		var velocity := heading * speed * _random.randf_range(0.65, 1.0) + Vector3.UP * _random.randf_range(0.6, 1.6)
		var life := settings.bounce_particle_seconds * _random.randf_range(0.8, 1.0)
		_emit(point + normal * (pixel * 4.5 + 0.015), velocity, pixel * 6.0, life, _random.randf_range(0.86, 1.0))
	multimesh.visible_instance_count = _written

func _emit(point: Vector3, velocity: Vector3, size: float, life: float, green: float) -> void:
	_transforms[_cursor] = Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), point)
	_colors[_cursor] = Color(1.0, green, 0.78, life)
	_launches[_cursor] = Color(velocity.x, velocity.y, velocity.z, clock)
	# 上传的出生时刻／寿命是 float32；向后留舍入余量，避免早于 shader 丢弃。
	var end := float(_launches[_cursor].a) + float(_colors[_cursor].a)
	_expires[_cursor] = end + maxf(1.0, absf(end)) * 0.0000002
	_next_expiry = minf(_next_expiry, _expires[_cursor])
	_until = maxf(_until, _expires[_cursor])
	_upload_instance(_cursor, _transforms[_cursor], _colors[_cursor], _launches[_cursor])
	_cursor = (_cursor + 1) % capacity
	_written = mini(_written + 1, capacity)
	emitted += 1

func _upload_instance(index: int, transform: Transform3D, color: Color, custom: Color) -> void:
	multimesh.set_instance_transform(index, transform)
	multimesh.set_instance_color(index, color)
	multimesh.set_instance_custom_data(index, custom)

func launch_velocity(direction: Vector3, speed_multiplier := 1.0) -> Vector3:
	var heading := direction.rotated(Vector3.UP, _random.randf_range(-0.9, 0.9))
	return (heading * _random.randf_range(0.65, 2.0) + Vector3.UP * _random.randf_range(1.4, 2.6)) * clampf(speed_multiplier, 0.5, 4.8)

func advance(real_delta: float) -> void:
	if not active: return
	clock += maxf(real_delta, 0.0)
	CombatEffectLayer.set_parameter(material_override, &"debris_clock", clock)
	if clock >= _until: clear()
	elif clock >= _next_expiry: _reclaim()

func _reclaim() -> void:
	var expired := 0
	_next_expiry = INF
	for index in _written:
		if _expires[index] <= clock: expired += 1
		else: _next_expiry = minf(_next_expiry, _expires[index])
	if expired == _written:
		clear()
		return
	# 留少量不可见槽位，摊薄搬移与上传；提交量受存活量约束，不累积整场历史。
	if expired < maxi(RECLAIM_MIN, _written / 4): return
	var target := 0
	for index in _written:
		if _expires[index] <= clock: continue
		if target != index:
			_transforms[target] = _transforms[index]
			_colors[target] = _colors[index]
			_launches[target] = _launches[index]
			_expires[target] = _expires[index]
			_upload_instance(target, _transforms[target], _colors[target], _launches[target])
		target += 1
	_written = target
	_cursor = _written % capacity
	multimesh.visible_instance_count = _written

func clear() -> void:
	hide()
	clock = 0.0
	_until = 0.0
	_cursor = 0
	_written = 0
	_next_expiry = INF
	if multimesh: multimesh.visible_instance_count = 0
	if material_override: CombatEffectLayer.set_parameter(material_override, &"debris_clock", 0.0)
