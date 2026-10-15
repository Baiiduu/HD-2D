class_name FollowCamera
extends Camera3D

@export_group("场景连接")
## 跟随目标（人物）
@export var target: Node3D
## 可指定通用效果子场景的屏幕后处理；留空时使用同层 PostProcess/Screen。
@export var post_process: CanvasItem:
	set(value):
		if post_process != value:
			post_process = value
			_post_material = null
@export_group("构图与跟随")
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
@export_subgroup("地图边缘保护")
## 焦点距离地图东西两侧、南侧、北侧边缘的最小距离（米），避免画面露出太多地图外区域
@export var bounds_margin_side: float = 5.0
@export var bounds_margin_south: float = 4.0
@export var bounds_margin_north: float = 0.0

@export_group("水平旋转")
## 初始水平朝向（度）；0 为从南向北看，Q/E 在此基础上左右旋转。
@export_range(-180.0, 180.0, 1.0) var yaw_degrees: float = 0.0
## 是否允许按住 Q/E 向左/向右绕焦点连续旋转；可沿同一方向转过任意圈数。
@export var horizontal_rotation_enabled: bool = true
## 按住 Q/E 时允许达到的最高旋转速度（度/秒）。
@export_range(0.0, 720.0, 1.0) var yaw_speed_degrees: float = 90.0
## 按住 Q/E 时每秒增加的旋转速度（度/秒²）；越大越快达到最高速度。
## 默认 90，在 1 秒内从 0 加速到最高速度；0 恢复恒定速度输入。
@export_range(0.0, 3600.0, 10.0) var yaw_acceleration_degrees: float = 90.0
## 收尾基准时长（秒）：越大减速越舒缓，按剩余角度与当前速度适配；0 直接停止或吸附。
## 默认 0.75 秒。收尾继承实际速度，再平滑降到 0；起步不再叠加角度延迟。
@export_range(0.0, 2.0, 0.01) var yaw_smoothing_seconds: float = 0.75
## 松开 Q/E 后，沿运动方向停到吸附点；根据当前速度预留减速距离，避免反向拉回或急刹。
## 每一圈的初始朝向始终是吸附点，朝它旋转时可停靠回正。
@export var yaw_snap_enabled: bool = true
## 每圈相对初始朝向的吸附间隔（度）；15 表示 0、15、30 等，每圈 360° 也可停靠。
## 0 禁用吸附；按住 Q/E 时仍可自由旋转。
@export_range(0.0, 180.0, 1.0) var yaw_snap_degrees: float = 15.0

@export_group("景深")
@export var dof_enabled: bool = true
## 深度景深按前后距离虚化；椭圆虚化在画面中保留人物周围的清晰区。
@export_enum("深度景深", "椭圆虚化", "HDR 散景") var dof_mode: int = 1
## 焦点前后保持清晰的距离（米）
@export var dof_far_margin: float = 2.5
@export var dof_far_transition: float = 5.0
@export var dof_near_margin: float = 2.5
@export var dof_near_transition: float = 2.0
@export_range(0.0, 1.0) var dof_amount: float = 0.1

@export_group("椭圆清晰区")
## 清晰区半径：X 相对画面宽度，Y 相对画面高度；0.3 表示该方向全长为画面的 60%。
@export var ellipse_radius := Vector2(0.34, 0.27)
## 椭圆边缘向外过渡的宽度，相对清晰区半径；越大越柔和。
@export_range(0.05, 2.0, 0.01) var ellipse_transition := 0.7
## 相对人物屏幕位置的中心偏移；X 向右、Y 向下，单位为画面宽高比例。
@export var ellipse_center_offset := Vector2.ZERO

## 焦点在地面 XZ 上的活动范围，由 set_world_rect() 根据地图大小计算
var bounds_min := Vector2(-INF, -INF)
var bounds_max := Vector2(INF, INF)
var anchor: Vector3
var focus: Vector3
var _yaw_offset_degrees: float = 0.0
var _yaw_target_degrees: float = 0.0
var _yaw_input_active: bool = false
var _yaw_last_turn: float = 0.0
var _yaw_velocity: float = 0.0
var _yaw_settle_start: float = 0.0
var _yaw_settle_speed: float = 0.0
var _yaw_settle_elapsed: float = 0.0
var _yaw_settle_duration: float = 0.0
var _post_material: ShaderMaterial

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
	_update_horizontal_rotation(delta)
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

func _update_horizontal_rotation(delta: float) -> void:
	if not horizontal_rotation_enabled or get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null:
		_clear_yaw_motion()
		return
	var left := Input.is_physical_key_pressed(KEY_Q)
	var right := Input.is_physical_key_pressed(KEY_E)
	var input_active := left or right
	var turn := float(right) - float(left)
	if input_active:
		if not _yaw_input_active or (turn != 0.0 and turn != _yaw_last_turn):
			# 新输入接管收尾，保留速度；连续点按不会重新从静止起步。
			_yaw_settle_duration = 0.0
		if _yaw_settle_duration > 0.0:
			_advance_yaw_settle(delta)
		else:
			_advance_yaw_input(turn, delta)
	else:
		if _yaw_input_active:
			var direction := signf(_yaw_velocity) if absf(_yaw_velocity) > 0.001 else _yaw_last_turn
			_begin_yaw_settle(direction)
		if _yaw_settle_duration > 0.0:
			_advance_yaw_settle(delta)
	_yaw_input_active = input_active
	if turn != 0.0:
		_yaw_last_turn = turn

func _advance_yaw_input(turn: float, delta: float) -> void:
	var desired := turn * yaw_speed_degrees
	var acceleration := yaw_acceleration_degrees
	# 反向输入或同时按下两键时先制动，随后再向新方向加速。
	if turn == 0.0 or turn * _yaw_velocity < 0.0:
		acceleration *= 2.0
	var travel := desired * delta
	if acceleration > 0.0:
		var ramp_time := minf(delta, absf(desired - _yaw_velocity) / acceleration)
		travel = _yaw_velocity * ramp_time + 0.5 * signf(desired - _yaw_velocity) * acceleration * ramp_time * ramp_time + desired * (delta - ramp_time)
		_yaw_velocity = move_toward(_yaw_velocity, desired, acceleration * delta)
	else:
		_yaw_velocity = desired
	_yaw_offset_degrees += travel
	_yaw_target_degrees = _yaw_offset_degrees

func _begin_yaw_settle(direction: float) -> void:
	var coast := absf(_yaw_velocity) * yaw_smoothing_seconds * 0.5
	var destination := _yaw_offset_degrees + direction * coast
	if yaw_snap_enabled and yaw_snap_degrees > 0.0:
		destination = _snapped_yaw(destination, direction)
	_yaw_target_degrees = destination
	var distance_to_stop := absf(_yaw_target_degrees - _yaw_offset_degrees)
	var speed_at_release := absf(_yaw_velocity)
	if yaw_smoothing_seconds <= 0.0 or distance_to_stop < 0.00001:
		_yaw_offset_degrees = _yaw_target_degrees
		_yaw_velocity = 0.0
		_yaw_settle_duration = 0.0
		return
	_yaw_settle_start = _yaw_offset_degrees
	_yaw_settle_speed = _yaw_velocity
	_yaw_settle_elapsed = 0.0
	# 三次曲线匹配起始速度、终点零速度；限制切线，保证不超速、不反向、不越过终点。
	_yaw_settle_duration = maxf(yaw_smoothing_seconds, 3.0 * distance_to_stop / maxf(speed_at_release + yaw_speed_degrees, 0.001))
	if speed_at_release > 0.001:
		_yaw_settle_duration = minf(_yaw_settle_duration, 3.0 * distance_to_stop / speed_at_release)

func _advance_yaw_settle(delta: float) -> void:
	if _yaw_settle_duration <= 0.0:
		return
	_yaw_settle_elapsed = minf(_yaw_settle_elapsed + delta, _yaw_settle_duration)
	var t := _yaw_settle_elapsed / _yaw_settle_duration
	var gap := _yaw_target_degrees - _yaw_settle_start
	var tangent := _yaw_settle_speed * _yaw_settle_duration
	_yaw_offset_degrees = _yaw_settle_start + gap * (3.0 * t * t - 2.0 * t * t * t) + tangent * (t * t * t - 2.0 * t * t + t)
	_yaw_velocity = (gap * (6.0 * t - 6.0 * t * t) + tangent * (3.0 * t * t - 4.0 * t + 1.0)) / _yaw_settle_duration
	if _yaw_settle_elapsed >= _yaw_settle_duration:
		_yaw_offset_degrees = _yaw_target_degrees
		_yaw_velocity = 0.0
		_yaw_settle_duration = 0.0

func _clear_yaw_motion() -> void:
	_yaw_target_degrees = _yaw_offset_degrees
	_yaw_input_active = false
	_yaw_last_turn = 0.0
	_yaw_velocity = 0.0
	_yaw_settle_duration = 0.0

func _snapped_yaw(angle: float, direction: float) -> float:
	if direction == 0.0:
		return angle
	# 每圈重新开始吸附网格；间隔不整除 360 时也保留初始朝向。
	var cycle_start := floorf(angle / 360.0) * 360.0
	var step := (angle - cycle_start) / yaw_snap_degrees
	var snapped := (ceilf(step) if direction > 0.0 else floorf(step)) * yaw_snap_degrees
	return cycle_start + clampf(snapped, 0.0, 360.0)

func _target_point() -> Vector3:
	return target.get_global_transform_interpolated().origin + Vector3.UP * focus_height

func _clamp_to_bounds(point: Vector3) -> Vector3:
	point.x = clampf(point.x, bounds_min.x, bounds_max.x)
	point.z = clampf(point.z, bounds_min.y, bounds_max.y)
	return point

func _apply_transform() -> void:
	# 绕焦点水平旋转，保持距离和俯角。
	var pitch := deg_to_rad(pitch_degrees)
	# 运镜与收尾保留连续角度，只有计算空间朝向时折回一圈。
	var yaw := deg_to_rad(wrapf(yaw_degrees + _yaw_offset_degrees, -180.0, 180.0))
	global_position = focus + Vector3(0.0, sin(pitch), cos(pitch)).rotated(Vector3.UP, yaw) * distance
	look_at(focus, Vector3.UP)

## 只恢复 Q/E 旋转偏移，保留初始朝向、俯角、距离与景深设置。
func reset_horizontal_rotation() -> void:
	_yaw_offset_degrees = 0.0
	_clear_yaw_motion()
	if target:
		_apply_transform()
		_update_dof()

func get_focus_depth() -> float:
	# Camera-space depth stays on the player's chest when bounds clamp the rig's focus.
	return maxf(near, -(global_transform.affine_inverse() * _target_point()).z)

func _update_dof() -> void:
	var practical := attributes as CameraAttributesPractical
	if not practical:
		return
	var focus_distance := get_focus_depth()
	practical.dof_blur_far_enabled = dof_enabled and dof_mode == 0
	practical.dof_blur_near_enabled = dof_enabled and dof_mode == 0
	practical.dof_blur_far_distance = focus_distance + dof_far_margin
	practical.dof_blur_far_transition = dof_far_transition
	practical.dof_blur_near_distance = maxf(focus_distance - dof_near_margin, 0.1)
	practical.dof_blur_near_transition = dof_near_transition
	practical.dof_blur_amount = dof_amount
	if not _post_material:
		var screen := post_process if post_process else get_parent().get_node_or_null("PostProcess/Screen") as CanvasItem
		if screen and screen.material is ShaderMaterial:
			_post_material = screen.material.duplicate() as ShaderMaterial
			screen.material = _post_material
	if _post_material:
		var viewport_size := get_viewport().get_visible_rect().size
		var center := unproject_position(_target_point()) / viewport_size + ellipse_center_offset
		_post_material.set_shader_parameter("ellipse_enabled", dof_enabled and dof_mode == 1)
		_post_material.set_shader_parameter("ellipse_center", center)
		_post_material.set_shader_parameter("ellipse_radius", Vector2(maxf(ellipse_radius.x, 0.01), maxf(ellipse_radius.y, 0.01)))
		_post_material.set_shader_parameter("ellipse_transition", ellipse_transition)
		_post_material.set_shader_parameter("ellipse_blur_amount", dof_amount)
