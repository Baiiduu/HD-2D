class_name Player
extends CharacterBody3D

signal movement_frame_changed(animation: StringName, frame: int)
signal jumped
signal landed(impact_speed: float)
## 碰撞检查后的真实瞬移路径，世界坐标；只有实际发生位移才发出。
signal blink_travelled(start: Vector3, destination: Vector3)
## 人物出手通知；伤害由基础剑术组件结算，不在运动代码中扣血。
signal normal_attack_requested(direction: Vector3)
## 当前生命、魔力或其上限发生变化；HUD 订阅此信号。
signal vitals_changed

const ANIMATION_REFERENCE_SPEED := 4.0
@export_group("移动与动画")
@export var speed: float = 4.0
@export var animations: SpriteFrames
## 移动参照相机：W/S 沿相机前后方向，A/D 沿相机左右方向，均投影到地面。
@export var movement_camera: Camera3D
@export_group("本体弹射与动作资源")
@export var ricochet_rules: PlayerRicochetRules
@export var action_visuals: PlayerActionVisuals
@export var sword_rules: PlayerSwordRules
@export var flight_trail_settings: PlayerFlightTrailSettings
@export_group("怪群近身留白")
## 普通怪停靠时额外保留的距离，单位米；0 关闭。正式地图先用 0.12。
## 近战怪会限制到仍可命中的距离；普通追击实时读取，不扩大人物碰撞体。
@export_range(0.0, 1.0, 0.01, "suffix:m") var crowd_clearance_distance := 0.0
@export_group("台阶通行")
## 接地行走时自动迈上低台阶；不影响主动跳跃。
@export var auto_step_enabled := true
## 单次允许迈上的最大高度，米；门口每级台阶约 0.14 米。
@export_range(0.05, 0.4, 0.01) var max_step_height := 0.25
@export_group("跳跃与下落")
@export var jump_enabled := true
## 跳跃离地的目标高度，米；由物理速度实现。
@export_range(0.1, 3.0, 0.05) var jump_height := 0.8
## 同时影响起跳与下落，米/秒²；越高，起落越快。
@export_range(1.0, 60.0, 0.5) var gravity := 20.0
## 接地后的短暂屈膝恢复时间，秒；不会锁定水平移动。
@export_range(0.0, 0.3, 0.01) var landing_time := 0.12
@export_group("瞬移闪身")
## Shift 触发；朝向锁定，移动输入决定闪身方向，无输入则沿当前朝向。
@export var blink_enabled := true
@export_subgroup("动作节奏")
## 最大水平位移（米），遇到碰撞体或地图边界提前停止。
@export_range(0.2, 5.0, 0.1, "suffix:m") var blink_distance := 2.4
## 完整动作时长，包含 idle 衔接与中段姿势定格。
@export_range(0.15, 0.8, 0.01, "suffix:s") var blink_duration := 0.20
## 按键到瞬移的起手时间，独立于完整动作时长。
@export_range(0.02, 0.12, 0.005, "suffix:s") var blink_anticipation := 0.025
## 瞬移后保持闪避姿势的时间；之后进入可移动的收尾。
@export_range(0.02, 0.18, 0.005, "suffix:s") var blink_pose_hold := 0.06
## 两次闪身开始之间的最短间隔，且必须等待当前动作结束。
@export_range(0.0, 2.0, 0.01, "suffix:s") var blink_cooldown := 0.28
## 收尾或冷却末段的新按键可短暂等待执行；0 关闭缓存。
@export_range(0.0, 0.15, 0.01, "suffix:s") var blink_input_buffer := 0.12
@export_subgroup("人形残影")
## 在原处与路径上保留的人形残影数量，0 关闭。
@export_range(0, 5, 1) var blink_echo_count := 2
## 残影淡出时间（秒），不会跟随人物继续移动。
@export_range(0.05, 0.6, 0.01, "suffix:s") var blink_echo_lifetime := 0.12
@export var blink_echo_color := Color(0.38, 0.85, 0.95)
@export_range(0.0, 0.8, 0.01) var blink_echo_opacity := 0.42
## 残影的短促轮廓发光，0 关闭；仍受场景遮挡与景深影响。
@export_range(0.0, 1.0, 0.05) var blink_echo_energy := 0.10
@export_group("生命与魔力")
## 本次出生时的生命比例，1 为满血；上限来自基础、装备与训练后的属性。
@export_range(0.0, 1.0, 0.01) var starting_health_ratio := 1.0
## 本次出生时的魔力比例，1 为满蓝；基础上限在 training_rules.tres 中配置。
@export_range(0.0, 1.0, 0.01) var starting_mana_ratio := 1.0
## 可活动范围（XZ），由场景根据地形大小设置
var bounds := Rect2(-INF, -INF, INF, INF)
## 由角色配置界面绑定；统一提供基础、装备与训练后的属性。
var character_state: LoadoutState:
	set(value):
		if character_state == value:
			return
		if character_state and character_state.changed.is_connected(_sync_vitals):
			character_state.changed.disconnect(_sync_vitals)
		character_state = value
		_vitals_initialized = false
		if character_state:
			character_state.changed.connect(_sync_vitals)
		_sync_vitals()

var max_health: float:
	get: return _max_health
var max_mana: float:
	get: return _max_mana
var current_health: float:
	get: return _health
	set(value):
		if not is_finite(value):
			return
		value = clampf(value, 0.0, max_health)
		if is_equal_approx(_health, value):
			return
		_health = value
		vitals_changed.emit()
var current_mana: float:
	get: return _mana
	set(value):
		if not is_finite(value):
			return
		value = clampf(value, 0.0, max_mana)
		if is_equal_approx(_mana, value):
			return
		_mana = value
		vitals_changed.emit()

var _max_health := 100.0
var _max_mana := 100.0
var _health := 100.0
var _mana := 100.0
var _vitals_initialized := false
@onready var sprite: Sprite3D = $Sprite
var _animation: StringName = &"idle"
var _animation_frame := 0
var _animation_elapsed := 0.0
var _movement_speed := 0.0
## 命中定格的明确持有状态；防止切入帧仍携带变速前的 delta。
var hit_stop_active := false
var _run_session: WavePrototype
var _controls: Node
var skill_manager: CharacterSkillManager
var _facing: StringName = &"side"
var _side_flip_h := false
var _landing_remaining := 0.0
var _has_landed_once := false
var _blink: PlayerBlink
var body_ricochet: PlayerRicochet
var flight_trail: PlayerFlightTrail
var motion_feedback: PlayerMotionFeedback
var surface_feedback: PlayerSurfaceFeedback
var bounce_effect: PlayerBounceEffect
var fire_trail: PlayerFireTrail
var action_animator: PlayerActionAnimator
var sword: PlayerSword

func get_movement_speed(modifiers: RunCombatModifiers = null) -> float:
	if not modifiers and is_instance_valid(_run_session): modifiers = _run_session.combat_modifiers
	return speed * modifiers.multiplier(GrowthBuffDefinition.Attribute.MOVE_SPEED) if modifiers else speed

func get_attributes() -> Dictionary[String, float]:
	if character_state:
		return character_state.get_character_attributes()
	var empty: Dictionary[String, float] = {}
	return empty

func _sync_vitals() -> void:
	var attributes := get_attributes()
	var next_health := maxf(1.0, attributes.get("health", 100.0))
	var next_mana := maxf(1.0, attributes.get("mana", 100.0))
	var health := clampf(_health + next_health - _max_health, 0.0, next_health)
	var mana := clampf(_mana + next_mana - _max_mana, 0.0, next_mana)
	if not _vitals_initialized:
		health = next_health * clampf(starting_health_ratio, 0.0, 1.0)
		mana = next_mana * clampf(starting_mana_ratio, 0.0, 1.0)
		_vitals_initialized = true
	var changed := not is_equal_approx(_max_health, next_health) or not is_equal_approx(_max_mana, next_mana) or not is_equal_approx(_health, health) or not is_equal_approx(_mana, mana)
	_max_health = next_health
	_max_mana = next_mana
	_health = health
	_mana = mana
	if changed:
		vitals_changed.emit()

## 传入已经结算的伤害；只更新血量，不在这里决定防御或战斗规则。
func take_damage(amount: float) -> float:
	if not is_finite(amount) or amount < 0.0:
		return 0.0
	var before := current_health
	current_health -= amount
	return before - current_health

func heal(amount: float) -> float:
	if not is_finite(amount) or amount < 0.0:
		return 0.0
	var before := current_health
	current_health += amount
	return current_health - before

## 不足时返回 false，且不扣除任何魔力。
func spend_mana(amount: float) -> bool:
	if not is_finite(amount) or amount < 0.0 or amount > current_mana:
		return false
	current_mana -= amount
	return true

func restore_mana(amount: float) -> float:
	if not is_finite(amount) or amount < 0.0:
		return 0.0
	var before := current_mana
	current_mana += amount
	return current_mana - before

func _ready() -> void:
	_controls = get_node("/root/GameControls")
	_run_session = get_parent().get_node_or_null("WavePrototype") as WavePrototype
	_sync_vitals()
	if animations:
		sprite.texture = animations.get_frame_texture(_animation, 0)
	action_animator = PlayerActionAnimator.new()
	action_animator.player = self
	action_animator.visuals = action_visuals
	skill_manager = get_node_or_null("CharacterSkillManager") as CharacterSkillManager
	if not skill_manager:
		skill_manager = load("res://scenes/player/character_skills.tscn").instantiate() as CharacterSkillManager
		add_child(skill_manager)
	_blink = skill_manager.dash
	body_ricochet = skill_manager.body_ricochet
	body_ricochet.impact_recorded.connect(func(impact: RicochetImpact): action_animator.request_bounce(impact.outgoing_velocity.normalized()))
	if flight_trail_settings:
		flight_trail = PlayerFlightTrail.new()
		flight_trail.name = "FlightTrail"
		add_child(flight_trail)
	if sword_rules:
		sword = PlayerSword.new()
		sword.name = "BasicSword"
		add_child(sword)
	skill_manager.configure(ricochet_rules != null and ricochet_rules.enabled, blink_enabled)
	if _run_session:
		_run_session.combat_frozen_changed.connect(skill_manager.set_combat_frozen)
		_run_session.phase_changed.connect(_on_skill_phase_changed)
		skill_manager.set_combat_frozen(_run_session.combat_frozen)

	if action_visuals:
		motion_feedback = PlayerMotionFeedback.new()
		motion_feedback.name = "MotionFeedback"
		add_child(motion_feedback)
		surface_feedback = PlayerSurfaceFeedback.new()
		surface_feedback.name = "SurfaceFeedback"
		add_child(surface_feedback)
		bounce_effect = PlayerBounceEffect.new()
		bounce_effect.name = "BounceEffect"
		add_child(bounce_effect)
		fire_trail = PlayerFireTrail.new()
		fire_trail.name = "GroundFireTrail"
		add_child(fire_trail)

func _on_skill_phase_changed(phase: WavePrototype.Phase) -> void:
	if phase == WavePrototype.Phase.READY: skill_manager.reset()
	elif phase == WavePrototype.Phase.RESULT: skill_manager.cancel_actions()

func _process(delta: float) -> void:
	if hit_stop_active: return
	if _blink.active and _blink.movement_locked:
		_blink.apply_pose()
		return
	if action_animator:
		action_animator.visuals = action_visuals
		var frozen := body_ricochet.is_frozen()
		if action_animator.render(0.0 if frozen else delta): return
		if frozen and (body_ricochet.charging or body_ricochet.flying): return
	if not animations:
		return
	var playback_speed := _movement_speed / ANIMATION_REFERENCE_SPEED if _animation.begins_with("run") else 1.0
	_animation_elapsed += delta * playback_speed
	var frame_duration := animations.get_frame_duration(_animation, _animation_frame) / animations.get_animation_speed(_animation)
	while _animation_elapsed >= frame_duration:
		_animation_elapsed -= frame_duration
		if animations.get_animation_loop_mode(_animation) == SpriteFrames.LOOP_NONE and _animation_frame == animations.get_frame_count(_animation) - 1:
			_animation_elapsed = 0.0
			break
		_animation_frame = (_animation_frame + 1) % animations.get_frame_count(_animation)
		movement_frame_changed.emit(_animation, _animation_frame)
		frame_duration = animations.get_frame_duration(_animation, _animation_frame) / animations.get_animation_speed(_animation)
	sprite.texture = animations.get_frame_texture(_animation, _animation_frame)
	sprite.flip_h = _side_flip_h if _facing == &"side" else false

func _physics_process(delta: float) -> void:
	if hit_stop_active: return
	# 面板只占用控制输入，人物物理、动画与整个世界继续更新。
	var input_blocked := get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null
	var movement_keys: int = _controls.movement_mask()
	# 每四位依次为四个方向的主键与备选键，分别跟踪新按下，兼用键不叠加速度。
	var direction := Vector2(
		float(bool(movement_keys & 0x88)) - float(bool(movement_keys & 0x22)),
		float(bool(movement_keys & 0x44)) - float(bool(movement_keys & 0x11))
	).normalized()
	if input_blocked:
		direction = Vector2.ZERO
	var movement := Vector3(direction.x, 0.0, direction.y)
	if movement_camera:
		var right := movement_camera.global_basis.x
		var backward := movement_camera.global_basis.z
		right.y = 0.0
		backward.y = 0.0
		movement = (right.normalized() * direction.x + backward.normalized() * direction.y).normalized()
	_blink.advance(delta)
	if body_ricochet.advance(delta, movement, input_blocked, movement_keys):
		# 飞行期间只由胶囊连续扫掠移动；占位画面保持现有人物，不伪装成快放跑步。
		_movement_speed = 0.0
		var pose: StringName = &"idle_back" if _facing == &"back" else &"idle"
		if animations and animations.has_animation(pose) and _animation != pose:
			_animation = pose
			_animation_frame = 0
			_animation_elapsed = 0.0
		return
	if not input_blocked and not skill_manager.combat_frozen and skill_manager.is_skill_enabled(CharacterSkillManager.DASH) and Input.is_action_just_pressed(&"blink"):
		body_ricochet.cancel()
		skill_manager.request_dash(movement)
	if body_ricochet.charging and (not is_on_floor() or Input.is_action_just_pressed(&"jump")): body_ricochet.cancel()
	if _blink.active:
		# 朝向与跳跃锁定；瞬移定格结束后，收尾阶段可立即恢复走路。
		direction = Vector2.ZERO
		if _blink.movement_locked:
			movement = Vector3.ZERO
	var movement_speed := get_movement_speed()
	velocity.x = movement.x * movement_speed
	velocity.z = movement.z * movement_speed
	var was_on_floor := is_on_floor()
	var was_falling := velocity.y < -0.1
	var started_jump := jump_enabled and not _blink.active and not input_blocked and was_on_floor and Input.is_action_just_pressed(&"jump")
	if started_jump:
		# 补偿首帧的离散步长，使实际最高点接近设置的高度。
		velocity.y = sqrt(2.0 * gravity * jump_height) - gravity * delta * 0.5
	elif not was_on_floor:
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0
	# 斜向移动以横向为主；松开按键后保留最后朝向。
	if direction != Vector2.ZERO:
		if absf(direction.x) >= absf(direction.y):
			_facing = &"side"
			_side_flip_h = direction.x < 0.0
			sprite.flip_h = _side_flip_h
		elif direction.y < 0.0:
			_facing = &"back"
			sprite.flip_h = false
		else:
			_facing = &"side"
			sprite.flip_h = _side_flip_h
	var previous_position := position
	var impact_speed := maxf(-velocity.y, 0.0)
	var previous_snap := floor_snap_length
	if auto_step_enabled and was_on_floor and not started_jump:
		_try_step_up(movement * movement_speed * delta)
		# 下台阶时也贴住地面；超过此高差仍按原有重力下落。
		floor_snap_length = maxf(previous_snap, max_step_height + safe_margin)
	move_and_slide()
	if auto_step_enabled and was_on_floor and not started_jump and not is_on_floor():
		_snap_to_step()
	floor_snap_length = previous_snap
	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.z = clampf(position.z, bounds.position.y, bounds.end.y)
	_movement_speed = Vector2(position.x - previous_position.x, position.z - previous_position.z).length() / delta
	var next_animation: StringName = &"run" if _movement_speed > 0.05 else &"idle"
	_landing_remaining = maxf(_landing_remaining - delta, 0.0)
	if started_jump:
		_landing_remaining = 0.0
		jumped.emit()
	elif is_on_floor() and not was_on_floor and was_falling:
		_landing_remaining = landing_time
		if _has_landed_once:
			landed.emit(impact_speed)
	if is_on_floor():
		_has_landed_once = true
	if not is_on_floor():
		next_animation = &"jump" if velocity.y > 0.0 else &"fall"
	elif _landing_remaining > 0.0:
		next_animation = &"land"
	if _facing != &"side":
		next_animation = StringName(str(next_animation) + "_" + str(_facing))
	# 允许换回只包含待机/跑步的旧资源。
	if not animations or not animations.has_animation(next_animation):
		next_animation = &"run" if _movement_speed > 0.05 else &"idle"
		if _facing != &"side":
			next_animation = StringName(str(next_animation) + "_" + str(_facing))
	if next_animation != _animation:
		_animation = next_animation
		_animation_frame = 0
		_animation_elapsed = 0.0
		movement_frame_changed.emit(_animation, _animation_frame)
	if body_ricochet.charging: face_world_direction(body_ricochet.direction)

func facing_direction() -> Vector3:
	var basis := movement_camera.global_basis if movement_camera else Basis.IDENTITY
	var heading := -basis.z if _facing == &"back" else basis.x * (-1.0 if _side_flip_h else 1.0)
	heading.y = 0.0
	return heading.normalized()

func face_world_direction(heading: Vector3) -> void:
	var basis := movement_camera.global_basis if movement_camera else Basis.IDENTITY
	var right := basis.x
	var back := basis.z
	right.y = 0.0
	back.y = 0.0
	var x := heading.dot(right.normalized())
	var z := heading.dot(back.normalized())
	if absf(x) >= absf(z):
		_facing = &"side"
		_side_flip_h = x < 0.0
	elif z < 0.0: _facing = &"back"
	else: _facing = &"side" # 旧人物没有正面素材；独立动作槽可使用 front。
	sprite.flip_h = _side_flip_h if _facing == &"side" else false

func _try_step_up(motion: Vector3) -> void:
	if motion.is_zero_approx():
		return
	var obstacle := KinematicCollision3D.new()
	if not test_move(global_transform, motion, obstacle, safe_margin):
		return
	if obstacle.get_normal().dot(up_direction) >= cos(floor_max_angle):
		return
	# 先确认头顶和抬高后的前方都能容纳整个角色胶囊。
	var lift := up_direction * max_step_height
	if test_move(global_transform, lift, null, safe_margin):
		return
	var raised := global_transform
	raised.origin += lift
	if test_move(raised, motion, null, safe_margin):
		return
	raised.origin += motion
	var landing := KinematicCollision3D.new()
	if not test_move(raised, -lift, landing, safe_margin):
		return
	var rise := max_step_height + landing.get_travel().dot(up_direction)
	if rise <= safe_margin or rise > max_step_height:
		return
	# 胶囊碰到台阶棱角的法线可能很陡，改查棱角前方的真实顶面。
	var point := landing.get_position() + motion.normalized() * 0.01
	var query := PhysicsRayQueryParameters3D.create(point + lift, point - up_direction * safe_margin, collision_mask, [get_rid()])
	var floor_hit := get_world_3d().direct_space_state.intersect_ray(query)
	if floor_hit.is_empty() or floor_hit.normal.dot(up_direction) < cos(floor_max_angle):
		return
	# 仅抬高，水平移动和最终贴地仍由 move_and_slide 处理。
	global_position += lift

func _snap_to_step() -> void:
	var query := PhysicsRayQueryParameters3D.create(global_position + up_direction * safe_margin,
		global_position - up_direction * floor_snap_length, collision_mask, [get_rid()])
	var floor_hit := get_world_3d().direct_space_state.intersect_ray(query)
	if floor_hit.is_empty() or floor_hit.normal.dot(up_direction) < cos(floor_max_angle):
		return
	# 脚下已确认有平面；仅在贴地查询中接受胶囊与台阶棱角的斜法线。
	var previous_angle := floor_max_angle
	floor_max_angle = deg_to_rad(89.0)
	apply_floor_snap()
	floor_max_angle = previous_angle
