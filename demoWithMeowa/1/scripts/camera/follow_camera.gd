class_name FollowCamera
extends Camera3D
const HURT_FEEDBACK := preload("res://scripts/camera/player_hurt_feedback.gd")

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
## 常态跟随的舒适速度；0 沿用不限速。接近安全距离时允许加速追赶。
@export_range(0.0, 80.0, 1.0, "suffix:m/s") var follow_max_speed := 0.0
## 最多允许人物落后多少米；按当前实际视野进一步收紧，避免推近或旋转后出屏。
@export_range(0.5, 8.0, 0.1, "suffix:m") var follow_max_lag := 3.0
## 关闭后停留在当前取景，改由鼠标靠近屏幕边缘移动焦点。
@export var follow_toggle_key: Key = KEY_Y
@export var follow_enabled := true:
	set(value):
		if follow_enabled == value: return
		follow_enabled = value
		if not is_inside_tree(): return
		if _ricochet_camera:
			_ricochet_camera.dispose()
			_ricochet_camera = null
		_impact_offset = Vector3.ZERO
		anchor = _clamp_to_bounds(focus)
		_follow_reacquiring = value
@export_subgroup("鼠标边缘滚动")
@export_range(2.0, 40.0, 1.0, "suffix:m/s") var edge_pan_speed := 12.0
## 按当前视口坐标计算，接近窗口边缘时逐渐加速。
@export_range(8.0, 80.0, 1.0, "suffix:px") var edge_pan_margin := 28.0
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
@export_enum("深度景深", "椭圆虚化") var dof_mode: int = 1
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

@export_group("弹射镜头反馈")
## 弹射时的前视、跟随惯性与撞墙轻震；留空沿用原跟随。
@export var ricochet_camera_settings: RicochetCameraSettings

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
var _hurt_feedback := HURT_FEEDBACK.new()
var _hurt_post: ShaderMaterial
var _hurt_last_tick := 0
var _hurt_applied_offset := Vector3.ZERO
var _ricochet_camera: RicochetCameraFeedback
var _impact_offset := Vector3.ZERO
var _follow_reacquiring := false
## 蓄力与环绕慢动作共用的真实时间请求；镜头和 Q/E 不随世界一起迟缓。
var charge_unscaled_time := false
## 击杀特写与曲线震动叠加在既有跟随之后，按真实时间推进。
var hit_stop_active := false
var hit_shot_active := false
## 只标识真实群杀的取景接管，普通命中／单杀轻震不占用特写资格。
var hit_closeup_active := false
var hit_shot_focus := Vector3.ZERO
var hit_shot_weight := 0.0
var hit_shot_distance_scale := 1.0
var hit_shake_offset := Vector3.ZERO
var hit_shake_roll := 0.0
## 波次镜头叠加在跟随／Q/E 之后，不改写地图保存的构图参数。
var wave_shot_active := false
var wave_shot_focus := Vector3.ZERO
var wave_shot_weight := 0.0
var wave_shot_distance_scale := 1.0
var wave_shot_roll := 0.0
var wave_shot_yaw := 0.0

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
	if _ricochet_camera: _ricochet_camera.reset()
	clear_hurt_feedback()
	_impact_offset = Vector3.ZERO
	_follow_reacquiring = false
	anchor = _clamp_to_bounds(_target_point())
	focus = anchor
	_apply_transform()
	_update_dof()

func _process(delta: float) -> void:
	if _hurt_feedback.active: _tick_hurt_feedback(Time.get_ticks_usec())
	if not target:
		clear_hurt_feedback()
		return
	# 冻结保留完整已渲染取景，避免用上一帧反弹偏航重新投影局部构图。
	if target is Player and is_instance_valid(target.body_ricochet) and target.body_ricochet.is_frozen(): return
	# 命中定格只播放叠加冲击；不推进基础跟随或按新倍率放大切入帧的旧 delta。
	if target is Player and target.hit_stop_active:
		_apply_transform()
		return
	var real_delta := maxf(delta, 0.0) / maxf(Engine.time_scale, 0.001)
	if not follow_enabled or charge_unscaled_time or wave_shot_active or hit_stop_active or hit_shot_active: delta /= maxf(Engine.time_scale, 0.001)
	var previous_focus := focus
	_update_horizontal_rotation(delta)
	if not follow_enabled:
		if _can_edge_pan(): _advance_edge_pan(delta, get_viewport().get_mouse_position(), get_viewport().get_visible_rect())
		anchor = _clamp_to_bounds(anchor)
		focus = _clamp_to_bounds(focus.lerp(anchor, 1.0 - exp(-smoothing * delta)))
		_apply_transform()
		_update_dof()
		return
	var point := _target_point()
	_bind_ricochet_camera()
	_impact_offset = Vector3.ZERO
	if _ricochet_camera:
		var view := Basis.looking_at(-_orbit_offset(), Vector3.UP)
		var viewport_size := get_viewport().get_visible_rect().size
		var short_side := minf(viewport_size.x, viewport_size.y)
		var span := _short_side_span()
		_ricochet_camera.advance(delta, point, view, span, short_side)
		span = _short_side_span()
		if _ricochet_camera.active:
			anchor = _clamp_to_bounds(point)
			var framing := _ricochet_camera.framing * span
			var addition := view.x * framing.x + view.y * framing.y + _ricochet_camera.collision_offset
			if ricochet_camera_settings.impact_shot_enabled: addition = addition.limit_length(span * 0.085)
			focus = _follow_step(_clamp_to_bounds(point + addition + _ricochet_camera.carry), point, real_delta)
			var impact := _ricochet_camera.shake * span
			_impact_offset = view.x * impact.x + view.y * impact.y
			_apply_transform()
			_update_dof()
			if delta > 0.0: _ricochet_camera.focus_velocity = (focus - previous_focus) / delta
			return
	var offset := Vector2(point.x - anchor.x, point.z - anchor.z)
	if offset.length() > dead_zone:
		var push := offset.normalized() * (offset.length() - dead_zone)
		anchor.x += push.x
		anchor.z += push.y
	anchor.y = point.y
	anchor = _clamp_to_bounds(anchor)
	focus = _follow_step(focus.lerp(anchor, 1.0 - exp(-smoothing * delta)), point, real_delta)
	_apply_transform()
	_update_dof()
	if _ricochet_camera and delta > 0.0: _ricochet_camera.focus_velocity = (focus - previous_focus) / delta

func _follow_step(desired: Vector3, player_point: Vector3, delta: float) -> Vector3:
	if follow_max_speed <= 0.0: return desired
	if delta <= 0.0: return focus
	var point := _clamp_to_bounds(player_point)
	# 使用当前推近后的视野，保持人物在画面内；不改变地图边界或角色速度。
	var leash := minf(follow_max_lag, _short_side_span() * 0.22)
	var lag := focus.distance_to(point)
	var catchup := smoothstep(leash * 0.55, leash, lag)
	var offset := desired - focus
	var step := offset.limit_length(follow_max_speed * delta).lerp(offset, catchup)
	var next := focus + step
	if _follow_reacquiring:
		# 远处解锁后按 Y：先沿原有平滑追上，避免安全绳第一帧把画面拉回。
		_follow_reacquiring = next.distance_to(point) > leash
	else:
		next = point + (next - point).limit_length(leash)
	return _clamp_to_bounds(next)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.physical_keycode != follow_toggle_key and not (event.physical_keycode == 0 and event.keycode == follow_toggle_key): return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed: return
	if not is_current() or not is_processing() or wave_shot_active or get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null: return
	var control := get_viewport().gui_get_focus_owner()
	if control is LineEdit or control is TextEdit: return
	if target is Player and is_instance_valid(target.body_ricochet) and target.body_ricochet.is_frozen(): return
	follow_enabled = not follow_enabled
	get_viewport().set_input_as_handled()

func _bind_ricochet_camera() -> void:
	if not follow_enabled: return
	if _ricochet_camera and (not ricochet_camera_settings or not _ricochet_camera.follows(target)):
		_ricochet_camera.dispose()
		_ricochet_camera = null
	if ricochet_camera_settings and not _ricochet_camera and target is Player and is_instance_valid((target as Player).body_ricochet):
		_ricochet_camera = RicochetCameraFeedback.new()
		_ricochet_camera.bind(self, target)

func edge_pan_input(cursor: Vector2, viewport: Rect2) -> Vector2:
	if not viewport.has_area() or not viewport.has_point(cursor): return Vector2.ZERO
	var margin := minf(edge_pan_margin, minf(viewport.size.x, viewport.size.y) * 0.25)
	var direction := Vector2(
		maxf(0.0, 1.0 - (viewport.end.x - cursor.x) / margin) - maxf(0.0, 1.0 - (cursor.x - viewport.position.x) / margin),
		maxf(0.0, 1.0 - (viewport.end.y - cursor.y) / margin) - maxf(0.0, 1.0 - (cursor.y - viewport.position.y) / margin))
	return direction.limit_length(1.0)

func _advance_edge_pan(delta: float, cursor: Vector2, viewport: Rect2) -> void:
	var input := edge_pan_input(cursor, viewport)
	if input.is_zero_approx(): return
	var view := Basis.looking_at(-_orbit_offset(true), Vector3.UP)
	var backward := Vector3(view.z.x, 0.0, view.z.z).normalized()
	anchor = _clamp_to_bounds(anchor + (view.x * input.x + backward * input.y) * edge_pan_speed * maxf(delta, 0.0))

func _can_edge_pan() -> bool:
	return get_window().has_focus() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE and not wave_shot_active and get_tree().get_first_node_in_group(&"gameplay_input_blockers") == null

func _short_side_span() -> float:
	var viewport_size := get_viewport().get_visible_rect().size
	var span := 2.0 / get_camera_projection().y.y
	if projection == Camera3D.PROJECTION_PERSPECTIVE: span *= distance * (_ricochet_camera.distance_scale + _ricochet_camera.collision_distance_scale + _ricochet_camera.orbit_distance_scale if _ricochet_camera else 1.0)
	return span * minf(viewport_size.x, viewport_size.y) / maxf(viewport_size.y, 1.0)

func get_flight_focus_weight() -> float:
	return _ricochet_camera.get_flight_focus_weight() if _ricochet_camera else 0.0

func _exit_tree() -> void:
	clear_hurt_feedback(false)
	if _ricochet_camera: _ricochet_camera.dispose()

## 受伤仅叠加短促的画面提示，不接入攻击短顿、特写或人物运动时间线。
func play_hurt_feedback(settings: PlayerActionVisuals, orbiting := false) -> void:
	_hurt_feedback.begin(settings, orbiting, has_priority_impact_feedback())
	_hurt_last_tick = Time.get_ticks_usec()
	_write_hurt_screen()

func has_priority_impact_feedback() -> bool:
	return not follow_enabled or wave_shot_active or hit_shot_active or not hit_shake_offset.is_zero_approx() or not is_zero_approx(hit_shake_roll) or (_ricochet_camera != null and _ricochet_camera.impact_feedback_active())

func _tick_hurt_feedback(now: int) -> void:
	var step := maxf(0.0, (now - _hurt_last_tick) * 0.000001) if _hurt_last_tick > 0 else 0.0
	_hurt_last_tick = now
	advance_hurt_feedback(step)

func advance_hurt_feedback(real_delta: float) -> void:
	if not target is Player or not target.action_visuals:
		clear_hurt_feedback()
		return
	if is_instance_valid(target.body_ricochet) and target.body_ricochet.is_frozen(): return
	_hurt_feedback.advance(real_delta, target.action_visuals, is_instance_valid(target.body_ricochet) and target.body_ricochet.orbiting, has_priority_impact_feedback())
	_write_hurt_screen()
	if is_inside_tree() and target.is_inside_tree(): _apply_transform()

func _write_hurt_screen() -> void:
	var screen := post_process if post_process else get_parent().get_node_or_null("PostProcess/Screen") as CanvasItem
	var material := screen.material as ShaderMaterial if is_instance_valid(screen) else null
	if material != _hurt_post:
		if _hurt_post: _hurt_post.set_shader_parameter("hurt_amount", 0.0)
		_hurt_post = material
	if _hurt_post:
		_hurt_post.set_shader_parameter("hurt_amount", _hurt_feedback.red_amount)
		_hurt_post.set_shader_parameter("hurt_color", _hurt_feedback.color)

func clear_hurt_feedback(apply_transform := true) -> void:
	_hurt_feedback.clear()
	_hurt_last_tick = 0
	if _hurt_post: _hurt_post.set_shader_parameter("hurt_amount", 0.0)
	if apply_transform and is_inside_tree() and is_instance_valid(target) and target.is_inside_tree(): _apply_transform()

func _hurt_world_offset() -> Vector3:
	if _hurt_feedback.shake.is_zero_approx(): return Vector3.ZERO
	if has_priority_impact_feedback(): _hurt_feedback.cancel_shake()
	if _hurt_feedback.shake.is_zero_approx(): return Vector3.ZERO
	var size := get_viewport().get_visible_rect().size
	var pixel := _short_side_span() / maxf(1.0, minf(size.x, size.y))
	var view := Basis.looking_at(-_orbit_offset(), Vector3.UP)
	return (view.x * _hurt_feedback.shake.x + view.y * _hurt_feedback.shake.y) * pixel

func _update_horizontal_rotation(delta: float) -> void:
	if not horizontal_rotation_enabled or get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null:
		_clear_yaw_motion()
		return
	var left := Input.is_action_pressed(&"camera_left")
	var right := Input.is_action_pressed(&"camera_right")
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

func _orbit_offset(base_only := false) -> Vector3:
	# 绕焦点水平旋转，保持距离和俯角。
	var pitch := deg_to_rad(pitch_degrees + (_ricochet_camera.pitch_offset + _ricochet_camera.orbit_pitch_offset if _ricochet_camera and not base_only else 0.0))
	# 运镜与收尾保留连续角度，只有计算空间朝向时折回一圈。
	var impact_yaw := _ricochet_camera.yaw_offset if _ricochet_camera and not base_only else 0.0
	var yaw := deg_to_rad(wrapf(yaw_degrees + _yaw_offset_degrees + impact_yaw, -180.0, 180.0))
	var distance_multiplier := _ricochet_camera.distance_scale + _ricochet_camera.collision_distance_scale + _ricochet_camera.orbit_distance_scale if _ricochet_camera and not base_only else 1.0
	return Vector3(0.0, sin(pitch), cos(pitch)).rotated(Vector3.UP, yaw) * distance * distance_multiplier

## 分段镜头只改变观看方式；鼠标使用同一基础取景投地，保留 Q/E 与人物走位。
func project_charge_aim(cursor: Vector2, ground_height: float) -> Variant:
	var origin := project_ray_origin(cursor)
	var ray := project_ray_normal(cursor)
	if follow_enabled and target is Player and target.body_ricochet.charging and ricochet_camera_settings and ricochet_camera_settings.enabled and ricochet_camera_settings.charge_focus_enabled and (ricochet_camera_settings.charge_staging_enabled or ricochet_camera_settings.charge_tremor_enabled):
		var offset := _orbit_offset(true)
		var entry := _ricochet_camera.aim_focus_offset if _ricochet_camera else Vector3.ZERO
		var neutral := Transform3D(Basis.looking_at(-offset, Vector3.UP), _clamp_to_bounds(_target_point() + entry) + offset)
		ray = neutral.basis * (global_basis.inverse() * ray)
		origin = neutral * (global_transform.affine_inverse() * origin)
	elif target is Player and target.body_ricochet.charging:
		origin -= _hurt_applied_offset
	return Plane(Vector3.UP, ground_height).intersects_ray(origin, ray)

func _apply_transform() -> void:
	var view_focus := focus if _impact_offset.is_zero_approx() else _clamp_to_bounds(focus + _impact_offset)
	if follow_enabled and _ricochet_camera and not _ricochet_camera.orbit_focus_offset.is_zero_approx():
		# 特写直接叠在已平滑的跟随上，避免半秒弧线再次被常态跟随滤掉。
		var view := Basis.looking_at(-_orbit_offset(), Vector3.UP)
		var span := _short_side_span()
		var framing := _ricochet_camera.framing + _ricochet_camera.shake
		var base := (view.x * framing.x + view.y * framing.y) * span
		var addition := (base + _ricochet_camera.orbit_focus_offset).limit_length(span * ricochet_camera_settings.max_offset_ratio) - base
		view_focus = _clamp_to_bounds(view_focus + addition)
	view_focus = view_focus.lerp(hit_shot_focus, hit_shot_weight)
	view_focus = view_focus.lerp(wave_shot_focus, wave_shot_weight)
	view_focus += hit_shake_offset
	_hurt_applied_offset = _hurt_world_offset()
	view_focus += _hurt_applied_offset
	var orbit := _orbit_offset(not follow_enabled)
	var kill_scale := hit_shot_distance_scale
	if kill_scale < 1.0:
		kill_scale = maxf(kill_scale, minf(1.0, distance * 0.65 / maxf(orbit.length(), 0.001)))
	global_position = view_focus + orbit.rotated(Vector3.UP, deg_to_rad(wave_shot_yaw)) * wave_shot_distance_scale * kill_scale
	look_at(view_focus, Vector3.UP)
	if not is_zero_approx(hit_shake_roll): rotate_object_local(Vector3.BACK, deg_to_rad(hit_shake_roll))
	if not is_zero_approx(wave_shot_roll): rotate_object_local(Vector3.BACK, deg_to_rad(wave_shot_roll))
	if follow_enabled and _ricochet_camera and not is_zero_approx(_ricochet_camera.roll_offset):
		rotate_object_local(Vector3.BACK, deg_to_rad(_ricochet_camera.roll_offset))

## 只恢复 Q/E 旋转偏移，保留初始朝向、俯角、距离与景深设置。
func reset_horizontal_rotation() -> void:
	_yaw_offset_degrees = 0.0
	_clear_yaw_motion()
	if target:
		_apply_transform()
		_update_dof()

func _update_dof() -> void:
	var practical := attributes as CameraAttributesPractical
	if not practical:
		return
	var focus_distance := global_position.distance_to(_target_point() if follow_enabled else focus)
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
		var center := unproject_position(_target_point() if follow_enabled else focus) / viewport_size + ellipse_center_offset
		_post_material.set_shader_parameter("ellipse_enabled", dof_enabled and dof_mode == 1)
		_post_material.set_shader_parameter("ellipse_center", center)
		_post_material.set_shader_parameter("ellipse_radius", Vector2(maxf(ellipse_radius.x, 0.01), maxf(ellipse_radius.y, 0.01)))
		_post_material.set_shader_parameter("ellipse_transition", ellipse_transition)
		_post_material.set_shader_parameter("ellipse_blur_amount", dof_amount)
