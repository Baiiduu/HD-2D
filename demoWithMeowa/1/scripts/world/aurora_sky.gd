extends Node

## 当前雾城远景的动态极光。天空与指定湿石板读取同一张实时天幕，不改变基础照明。
const FIELD_SHADER = preload("res://shaders/environment/aurora_field.gdshader")
const FIELD_SIZE := Vector2i(1536, 384)

@export_group("天空极光与局部倒影")
## 总开关；关闭后恢复原天空与地面，不影响现有路灯反射。
@export var enabled := true:
	set(value): enabled = value; _queue_apply()
## 天空极光亮度，地面仍由独立倒影强度限制。
@export_range(0.0, 3.0, 0.05) var sky_strength := 1.0:
	set(value): sky_strength = value; _queue_apply()
## 只作用于指定湿石板区域，不改变方向光和路灯镜面高光。
@export_range(0.0, 8.0, 0.05) var reflection_strength := 6.0:
	set(value): reflection_strength = value; _queue_apply()
@export_range(0.0, 3.0, 0.05) var flow_speed := 1.4:
	set(value): flow_speed = value; _queue_apply()
@export var green_color := Color(0.22, 0.95, 0.66):
	set(value): green_color = value; _queue_apply()
@export var blue_color := Color(0.20, 0.48, 1.0):
	set(value): blue_color = value; _queue_apply()
@export var purple_color := Color(0.48, 0.29, 0.76):
	set(value): purple_color = value; _queue_apply()
@export var pink_color := Color(0.95, 0.30, 0.64):
	set(value): pink_color = value; _queue_apply()
## 每项为世界坐标 X/Z 中心与 X/Z 半径（米）；最多四片，地面材质继续排除草地。
@export var reflection_regions: Array[Vector4] = [
	Vector4(-4.0, 43.0, 3.6, 2.2), Vector4(5.0, 48.0, 3.5, 2.2),
	Vector4(0.0, 41.0, 3.2, 2.0)]:
	set(value): reflection_regions = value; _queue_apply()

var clock := 0.0
var _field: SubViewport
var _field_material: ShaderMaterial
var _sky: ShaderMaterial
var _ground: ShaderMaterial
var _apply_queued := false

func _ready() -> void:
	set_process(false)
	_setup.call_deferred()

func _setup() -> void:
	var effects := get_parent()
	var environment: WorldEnvironment = effects.get_node_or_null("WorldEnvironment")
	if not environment or not environment.environment or not environment.environment.sky:
		return
	_sky = environment.environment.sky.sky_material as ShaderMaterial
	# Other map previews retain their own sky; the current city matte opts in.
	if not _sky or _sky.get_shader_parameter("city_matte_enabled") != true:
		_sky = null
		return
	var terrain := effects.get("terrain") as Terrain
	_ground = terrain.top_material if terrain else null
	if not _ground:
		_sky = null
		return
	_field = SubViewport.new()
	_field.name = "AuroraField"
	_field.size = FIELD_SIZE
	_field.disable_3d = true
	_field.use_hdr_2d = true
	add_child(_field)
	_field_material = ShaderMaterial.new()
	_field_material.shader = FIELD_SHADER
	var canvas := ColorRect.new()
	canvas.size = Vector2(FIELD_SIZE)
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.material = _field_material
	_field.add_child(canvas)
	for material in [_sky, _ground]:
		material.set_shader_parameter("aurora_texture", _field.get_texture())
	_apply()

func _queue_apply() -> void:
	if not is_inside_tree() or _apply_queued: return
	_apply_queued = true
	_apply.call_deferred()

func _apply() -> void:
	_apply_queued = false
	if not _field: return
	for material in [_sky, _ground]:
		material.set_shader_parameter("aurora_enabled", enabled)
		material.set_shader_parameter("aurora_strength", sky_strength)
	_field_material.set_shader_parameter("green_color", green_color)
	_field_material.set_shader_parameter("blue_color", blue_color)
	_field_material.set_shader_parameter("purple_color", purple_color)
	_field_material.set_shader_parameter("pink_color", pink_color)
	_ground.set_shader_parameter("aurora_reflection_strength", reflection_strength)
	var regions := PackedVector4Array()
	for i in 4:
		regions.append(reflection_regions[i] if i < reflection_regions.size() else Vector4.ZERO)
	_ground.set_shader_parameter("aurora_reflection_regions", regions)
	_ground.set_shader_parameter("aurora_reflection_region_count", mini(reflection_regions.size(), 4))
	_field.render_target_update_mode = (SubViewport.UPDATE_ALWAYS if flow_speed > 0.0 else SubViewport.UPDATE_ONCE) if enabled else SubViewport.UPDATE_DISABLED
	set_process(enabled and flow_speed > 0.0)
	update_clock()

func _process(delta: float) -> void:
	clock += delta * flow_speed
	update_clock()

func update_clock() -> void:
	if _field_material:
		_field_material.set_shader_parameter("aurora_clock", clock)

func _exit_tree() -> void:
	for material in [_sky, _ground]:
		if material:
			material.set_shader_parameter("aurora_enabled", false)
			material.set_shader_parameter("aurora_texture", null)
