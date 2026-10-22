class_name FollowCamera
extends Camera3D

## 跟随目标（人物）
@export var target: Node3D
## 焦点相对目标原点的高度：对准人物贴图中心
@export var focus_height: float = 0.75
## 相机到焦点的距离（米）
@export var distance: float = 13.0
## 俯角（度），越大越接近俯瞰
@export_range(10.0, 80.0) var pitch_degrees: float = 35.0
## 跟随平滑度，越大跟得越紧
@export var smoothing: float = 6.0
## 死区半径（米）：人物在焦点附近这个范围内移动时相机不动
@export var dead_zone: float = 0.6
## 焦点距离地图东西两侧、南侧、北侧边缘的最小距离（米），避免画面露出太多地图外区域
@export var bounds_margin_side: float = 5.0
@export var bounds_margin_south: float = 4.0
@export var bounds_margin_north: float = 0.0

@export_group("景深")
@export var dof_enabled: bool = true
## 焦点前后保持清晰的距离（米）
@export var dof_far_margin: float = 2.5
@export var dof_far_transition: float = 5.0
@export var dof_near_margin: float = 2.5
@export var dof_near_transition: float = 2.0
@export_range(0.0, 1.0) var dof_amount: float = 0.1

## 焦点在地面 XZ 上的活动范围，由 set_world_rect() 根据地图大小计算
var bounds_min := Vector2(-INF, -INF)
var bounds_max := Vector2(INF, INF)
var anchor: Vector3
var focus: Vector3

func _ready() -> void:
	# 在 _process 中按插值后的人物位置移动，相机自身不参与物理插值
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if attributes == null:
		attributes = CameraAttributesPractical.new()
	snap_to_target()

func set_world_rect(rect: Rect2) -> void:
	bounds_min = rect.position + Vector2(bounds_margin_side, bounds_margin_north)
	bounds_max = rect.end - Vector2(bounds_margin_side, bounds_margin_south)
	# 地图比可视范围还窄时，焦点固定在中线上
	if bounds_min.x > bounds_max.x:
		bounds_min.x = rect.get_center().x
		bounds_max.x = bounds_min.x
	if bounds_min.y > bounds_max.y:
		bounds_min.y = rect.get_center().y
		bounds_max.y = bounds_min.y

func snap_to_target() -> void:
	if not target:
		return
	anchor = _clamp_to_bounds(_target_point())
	focus = anchor
	_apply_transform()
	_update_dof()

func _process(delta: float) -> void:
	if not target:
		return
	var point := _target_point()
	var offset := Vector2(point.x - anchor.x, point.z - anchor.z)
	if offset.length() > dead_zone:
		var push := offset.normalized() * (offset.length() - dead_zone)
		anchor.x += push.x
		anchor.z += push.y
	anchor.y = point.y
	anchor = _clamp_to_bounds(anchor)
	focus = focus.lerp(anchor, 1.0 - exp(-smoothing * delta))
	_apply_transform()
	_update_dof()

func _target_point() -> Vector3:
	return target.get_global_transform_interpolated().origin + Vector3.UP * focus_height

func _clamp_to_bounds(point: Vector3) -> Vector3:
	point.x = clampf(point.x, bounds_min.x, bounds_max.x)
	point.z = clampf(point.z, bounds_min.y, bounds_max.y)
	return point

func _apply_transform() -> void:
	# 相机位于焦点正南方（+Z），朝北俯视
	var pitch := deg_to_rad(pitch_degrees)
	global_position = focus + Vector3(0.0, sin(pitch), cos(pitch)) * distance
	look_at(focus, Vector3.UP)

func _update_dof() -> void:
	var practical := attributes as CameraAttributesPractical
	if not practical:
		return
	var focus_distance := global_position.distance_to(_target_point())
	practical.dof_blur_far_enabled = dof_enabled
	practical.dof_blur_near_enabled = dof_enabled
	practical.dof_blur_far_distance = focus_distance + dof_far_margin
	practical.dof_blur_far_transition = dof_far_transition
	practical.dof_blur_near_distance = maxf(focus_distance - dof_near_margin, 0.1)
	practical.dof_blur_near_transition = dof_near_transition
	practical.dof_blur_amount = dof_amount
