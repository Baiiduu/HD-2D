extends MultiMeshInstance3D
## 真实击杀的原生像素长斩痕；同批共用，轨迹、展开和破碎由 GPU 求值。
const SHADER = preload("res://shaders/combat/kill_slash.gdshader")
const CAPACITY := 32
var clock := 0.0
var emitted := 0
var active: bool:
	get: return visible and clock < _until
var _until := 0.0
var _cursor := 0
var _written := 0

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = QuadMesh.new()
	multimesh.mesh.size = Vector2.ONE
	multimesh.instance_count = CAPACITY
	multimesh.visible_instance_count = 0
	material_override = CombatEffectLayer.material(SHADER)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	global_transform = Transform3D.IDENTITY
	custom_aabb = AABB(Vector3(-256, -32, -256), Vector3(512, 128, 512))
	hide()
	set_process(false)

func burst(point: Vector3, direction: Vector3, pixel: float, camera: Camera3D, settings: PlayerActionVisuals) -> void:
	if not settings.kill_slash_texture: return
	if not active: clear()
	var normal := camera.global_basis.z
	var axis := (direction - normal * direction.dot(normal)).normalized()
	if axis.is_zero_approx(): axis = camera.global_basis.x
	var size := Vector2(settings.kill_slash_texture.get_size()) * pixel
	var pose := Basis(axis * size.x, normal.cross(axis).normalized() * size.y, normal)
	var life := clampf(settings.kill_slash_seconds, 0.15, 0.6)
	multimesh.set_instance_transform(_cursor, Transform3D(pose, point))
	multimesh.set_instance_color(_cursor, Color(1.0, 1.0, 1.0, life))
	multimesh.set_instance_custom_data(_cursor, Color(direction.x, direction.y, direction.z, clock))
	_cursor = (_cursor + 1) % CAPACITY
	_written = mini(_written + 1, CAPACITY)
	multimesh.visible_instance_count = _written
	_until = maxf(_until, clock + life)
	emitted += 1
	CombatEffectLayer.set_parameter(material_override, &"slash_texture", settings.kill_slash_texture)
	show()

func advance(real_delta: float) -> void:
	if not active: return
	clock += maxf(real_delta, 0.0)
	CombatEffectLayer.set_parameter(material_override, &"slash_clock", clock)
	if clock >= _until: clear()

func clear() -> void:
	hide()
	clock = 0.0
	_until = 0.0
	_cursor = 0
	_written = 0
	if multimesh: multimesh.visible_instance_count = 0
	if material_override: CombatEffectLayer.set_parameter(material_override, &"slash_clock", 0.0)
