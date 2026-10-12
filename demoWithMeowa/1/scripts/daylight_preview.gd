@tool
extends Node3D

const CLOUD_SHADER := preload("res://shaders/cloud_shadow.gdshader")
var _progress_value := 0.35

@export_group("日照演示")
@export var art_direction: ArtDirection:
	set(value): art_direction = value; _queue_apply()
## 关闭恢复 ArtDirection 中的月光、环境光与天空参数。
@export var enabled := false:
	set(value): enabled = value; _queue_apply()
## 自动往返演示；关闭后可用 Progress 手动选定时刻。
@export var playing := true:
	set(value): playing = value; _queue_apply()
## 0 为日照起点，1 为终点；编辑器默认静止，拖动即可预览。
@export_range(0.0, 1.0, 0.001) var progress := 0.35:
	get: return _progress_value
	set(value):
		_progress_value = clampf(value, 0.0, 1.0)
		_travel_phase = acos(1.0 - 2.0 * _progress_value) / PI
		_queue_apply()
## 从起点到终点的秒数，之后平滑返回，不突跳到起点。
@export_range(15.0, 600.0, 1.0, "suffix:s") var travel_seconds := 180.0:
	set(value): travel_seconds = value; _queue_apply()
## 只用于编辑器自动播放；默认关，避免编辑时持续改变场景。
@export var animate_in_editor := false:
	set(value): animate_in_editor = value; _queue_apply()

@export_group("日光与阴影")
## 方向光起止方位，单位度；相对于世界坐标，不跟随 QE 镜头。
@export var azimuth_range := Vector2(-65.0, 65.0):
	set(value): azimuth_range = value; _queue_apply()
## 起止时的俯照角；较低时投影更长。
@export_range(10.0, 60.0, 1.0, "degrees") var low_elevation := 20.0:
	set(value): low_elevation = value; _queue_apply()
## 演示中段的俯照角。
@export_range(10.0, 80.0, 1.0, "degrees") var peak_elevation := 38.0:
	set(value): peak_elevation = value; _queue_apply()
@export var warm_color := Color(1.0, 0.77, 0.48):
	set(value): warm_color = value; _queue_apply()
@export var noon_color := Color(1.0, 0.94, 0.82):
	set(value): noon_color = value; _queue_apply()
@export_range(0.0, 4.0, 0.05) var sun_energy := 1.5:
	set(value): sun_energy = value; _queue_apply()
## 日照下的冷色环境填充，决定云影和物体阴影的可读性。
@export var shade_color := Color(0.47, 0.56, 0.72):
	set(value): shade_color = value; _queue_apply()
@export_range(0.0, 2.0, 0.01) var shade_energy := 0.32:
	set(value): shade_energy = value; _queue_apply()
## 日光角直径：增加会柔化远离投影面的遮挡物阴影。
@export_range(0.0, 6.0, 0.1, "degrees") var sun_softness := 1.2:
	set(value): sun_softness = value; _queue_apply()
## 主光阴影的深浅，同时影响云影和物体投影；局部路灯阴影保持原值。
@export_range(0.0, 1.0, 0.05) var sun_shadow_opacity := 0.75:
	set(value): sun_shadow_opacity = value; _queue_apply()
## 对现有夜空与雾色的轻微提亮，不改变远景构图。
@export_range(0.0, 1.0, 0.05) var sky_blend := 0.5:
	set(value): sky_blend = value; _queue_apply()

@export_group("移动云影")
@export var cloud_shadows := true:
	set(value): cloud_shadows = value; _queue_apply()
## 云影占比；高空层只遮挡方向光，路灯仍可照亮云影内的地面。
@export_range(0.0, 1.0, 0.05) var cloud_coverage := 0.45:
	set(value): cloud_coverage = value; _queue_apply()
## 云团在世界空间的尺度，米；大于细小草影，形成大片明暗。
@export_range(3.0, 24.0, 0.5, "suffix:m") var cloud_size := 9.0:
	set(value): cloud_size = value; _queue_apply()
## X/Z 方向上的移动速度，米/秒；暂停播放时云影也暂停。
@export var cloud_velocity := Vector2(0.12, 0.05):
	set(value): cloud_velocity = value; _queue_apply()
## 手动平移云影，方便在固定进度比较同一片地表。
@export var cloud_offset := Vector2.ZERO:
	set(value): cloud_offset = value; _queue_apply()

var _cloud: MeshInstance3D
var _cloud_material: ShaderMaterial
var _apply_queued := false
var _travel_phase := 0.0
var _cloud_clock := 0.0

func _ready() -> void:
	process_priority = 30 # Before the mirrored cameras update their environment.
	_travel_phase = acos(1.0 - 2.0 * progress) / PI
	_apply()

func _queue_apply() -> void:
	if _apply_queued or not is_inside_tree():
		return
	_apply_queued = true
	_apply.call_deferred()

func _apply() -> void:
	_apply_queued = false
	if art_direction:
		art_direction.apply() # This calls apply_daylight after the base settings.

func _process(delta: float) -> void:
	if not art_direction:
		return
	if not _cloud:
		apply_daylight()
	if not enabled or not playing or (Engine.is_editor_hint() and not animate_in_editor):
		return
	_travel_phase = fposmod(_travel_phase + delta / maxf(travel_seconds, 1.0), 2.0)
	# Ease both ends of the reversible trajectory; Inspector reflects the live position.
	_progress_value = (1.0 - cos(_travel_phase * PI)) * 0.5
	_cloud_clock += delta
	apply_daylight()

func _ensure_cloud() -> void:
	if _cloud:
		return
	_cloud_material = ShaderMaterial.new()
	_cloud_material.shader = CLOUD_SHADER
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	# Subdivision keeps the large layer valid across native shadow pancakes/splits.
	plane.subdivide_width = 32
	plane.subdivide_depth = 32
	_cloud = MeshInstance3D.new()
	_cloud.name = "CloudShadowCaster"
	_cloud.mesh = plane
	_cloud.material_override = _cloud_material
	_cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_cloud.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_cloud.position.y = 18.0
	add_child(_cloud) # No owner: generated render helper is not saved with the map.

func apply_daylight() -> void:
	# New Inspector fields can be Nil in an already-open @tool instance after reload.
	var script: Script = get_script()
	for property in script.get_script_property_list():
		if not (property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_EDITOR):
			continue
		var default_value: Variant = script.get_property_default_value(property.name)
		if get(property.name) == null and default_value != null:
			set(property.name, default_value)
	if not art_direction or not art_direction.moon:
		return
	_ensure_cloud()
	var light := art_direction.moon
	var environment := art_direction.world_environment.environment if art_direction.world_environment else null
	var sky := environment.sky.sky_material as ShaderMaterial if environment and environment.sky else null
	_cloud.visible = enabled and cloud_shadows and cloud_coverage > 0.0
	if not enabled:
		return
	var height := sin(progress * PI)
	light.rotation_degrees = Vector3(-lerpf(low_elevation, peak_elevation, height),
		lerpf(azimuth_range.x, azimuth_range.y, progress), 0.0)
	light.light_color = warm_color.lerp(noon_color, height)
	light.light_energy = sun_energy * lerpf(0.75, 1.0, height)
	light.light_angular_distance = sun_softness
	light.shadow_opacity = sun_shadow_opacity
	_cloud_material.set_shader_parameter("cloud_size", cloud_size)
	_cloud_material.set_shader_parameter("coverage", cloud_coverage)
	_cloud_material.set_shader_parameter("drift", cloud_offset + cloud_velocity * _cloud_clock)
	if environment:
		environment.ambient_light_color = shade_color
		environment.ambient_light_energy = shade_energy
		if sky:
			sky.set_shader_parameter("zenith_color", art_direction.sky_top_color.lerp(Color(0.18, 0.30, 0.46), sky_blend))
			sky.set_shader_parameter("horizon_color", art_direction.fog_color.lerp(Color(0.62, 0.59, 0.48), sky_blend))
			sky.set_shader_parameter("moon_glow_color", light.light_color)
			sky.set_shader_parameter("star_density", art_direction.stars * (1.0 - sky_blend))
