@tool
extends SpotLight3D

## Layer 15 is only a light receiver tag; cameras exclude it so water proxies
## can share the tag without appearing in the main view.
const RECEIVER_LAYER := 1 << 14

@export_group("场景连接")
@export var camera: Camera3D

@export_group("人物重点补光")
## 独立真实聚光，只照人物与人物倒影；不修改原人物材质。
@export var fill_enabled := true:
	set(value): fill_enabled = value; apply_fill()
@export var fill_color := Color(1.0, 0.90, 0.76):
	set(value): fill_color = value; apply_fill()
@export_range(0.0, 6.0, 0.05) var fill_energy := 2.0:
	set(value): fill_energy = value; apply_fill()
@export_range(2.0, 9.0, 0.1, "suffix:m") var fill_height := 4.5:
	set(value): fill_height = value; apply_fill()
## 随镜头水平方位保持前侧受光，不随运镜俯仰和侧倾晃动。
@export_range(0.5, 6.0, 0.1, "suffix:m") var fill_front_offset := 3.0:
	set(value): fill_front_offset = value; apply_fill()
@export_range(-4.0, 4.0, 0.1, "suffix:m") var fill_side_offset := -1.5:
	set(value): fill_side_offset = value; apply_fill()
@export_range(0.0, 2.0, 0.05, "suffix:m") var fill_target_height := 0.55:
	set(value): fill_target_height = value; apply_fill()
@export_range(8.0, 45.0, 0.5, "suffix:°") var fill_angle := 20.0:
	set(value): fill_angle = value; apply_fill()

func _ready() -> void:
	process_priority = 50 # Camera framing is ready; planar reflections update at 100.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	apply_fill()
	sync_pose()

func apply_fill() -> void:
	visible = fill_enabled
	set_process(fill_enabled)
	light_color = fill_color
	light_energy = fill_energy
	light_cull_mask = RECEIVER_LAYER
	light_specular = 0.0
	light_indirect_energy = 0.0
	light_volumetric_fog_energy = 0.0
	light_bake_mode = Light3D.BAKE_DISABLED
	shadow_enabled = false
	distance_fade_enabled = false
	spot_angle = fill_angle
	spot_angle_attenuation = 1.2
	spot_attenuation = 0.2
	spot_range = Vector3(fill_side_offset, fill_height - fill_target_height, fill_front_offset).length() + 2.0

func _process(_delta: float) -> void:
	sync_pose()

func sync_pose() -> void:
	if not fill_enabled or not is_inside_tree() or not is_instance_valid(camera): return
	var player := get_parent() as Node3D
	if not player or not camera.is_inside_tree(): return
	var backward := Vector3(camera.global_basis.z.x, 0.0, camera.global_basis.z.z).normalized()
	if backward.is_zero_approx(): backward = Vector3.BACK
	var right := Vector3.UP.cross(backward)
	var point := player.get_global_transform_interpolated().origin
	global_position = point + Vector3.UP * fill_height + backward * fill_front_offset + right * fill_side_offset
	look_at(point + Vector3.UP * fill_target_height, Vector3.UP)
