class_name SlimeEnemy
extends WaveEnemy

enum State { IDLE, PATROL, CHASE, RETURN }
const DIRECTIONS := ["front","front_right","right","back_right","back","back_left","left","front_left"]
const MIRRORED_FACINGS := [0, 1, 2, 3, 4, 3, 2, 1]
# Only value data is shared: no cameras, SpriteFrames or textures are retained.
static var _projection_valid := false
static var _projection_basis := Basis.IDENTITY
static var _projection_right := Vector3.RIGHT
static var _projection_backward := Vector3.BACK
static var _directional_clips: Dictionary[StringName, Array] = {}
static var _clip_actions: Dictionary[StringName, StringName] = {&"": &""}
signal state_changed(state: State)

@export_group("地图连接")
@export var terrain: Terrain
@export var target: Node3D
@export var camera: Camera3D
@export var animations: SpriteFrames

@export_group("活动与警戒")
## 围绕场景初始位置选择巡逻目标，米。
@export_range(0.0,10.0,0.1) var patrol_radius := 3.0
@export_range(0.1,5.0,0.1) var patrol_speed := 0.9
@export_range(0.1,8.0,0.1) var chase_speed := 1.8
## 可见玩家进入此距离时追踪，米；房屋和墙体会遮挡视线。
@export_range(0.5,20.0,0.1) var detect_distance := 6.0
## 超出出生点此距离的玩家不再追踪；怪物也不会跑出此边界。
@export_range(1.0,30.0,0.1) var leash_distance := 10.0
## 接近玩家后停下，不攻击或挤压玩家。
@export_range(0.5,3.0,0.1) var stop_distance := 0.9
## 失去视线多少秒后返回出生点。
@export_range(0.0,5.0,0.1) var lost_sight_seconds := 1.5
## 停下来休息的最短、最长时间，秒。
@export var idle_seconds := Vector2(1.5,3.5)
@export var random_seed := 12102026

@export_group("移动与外观")
@export_range(0.1,0.6,0.01) var body_radius := 0.28
@export_range(0.4,1.2,0.01) var body_height := 0.7
@export_range(1.0,40.0,0.1) var gravity := 20.0
## 路线刷新间隔，秒；玩家移动时定期重新寻找路线。
@export_range(0.1,2.0,0.05) var route_interval := 0.45
## 动画速度独立于怪物移动速度，1 为美术默认帧率。
@export_range(0.25,2.0,0.05) var animation_speed := 1.0
## 普通追击的同高地面水平扫掠；关闭即恢复 CharacterBody 移动。
@export var ground_movement_enabled := false

@export_group("波次接触攻击")
## 战斗模式持续追击，到此距离停下；展示模式仍使用 Stop Distance。
@export_range(0.3,1.5,0.05) var combat_stop_distance := 0.65
@export_range(0.4,2.0,0.05) var contact_distance := 0.85
@export_range(0.2,1.5,0.05) var contact_height := 0.8
## 旧资源兼容字段；不再使用出生缩放或半透明预警。
@export_storage var warning_scale := 0.35
@export_range(0.0,0.5,0.01) var hit_flash_seconds := 0.15

var state := State.IDLE
var home_position: Vector3
var patrol_goal: Vector3
var _path := TerrainPath.new()
var _route := PackedVector3Array()
var _waypoint := 0
var _route_clock := 0.0
var _idle_clock := 0.0
var _lost_sight := 0.0
var _stuck_clock := 0.0
var _ready_for_ai := false
var _path_rebuild_pending := false
var _random := RandomNumberGenerator.new()
var _look := Vector3.FORWARD
var _facing_sector := -1
var _clip: StringName = &""
var _frame := 0
var _elapsed := 0.0
var _hit_flash := 0.0
var _sprite_scale := Vector3.ONE
var _sprite_color := Color.WHITE
var separation_radius := 1.0
var separation_strength := 1.5
var pursuit_lookahead := 4.0
var pursuit_flank_strength := 0.35
var _yield_side := 0.0
var knockback_multiplier := 1.0
var _push_direction := Vector3.ZERO
var _push_speed := 0.0
var _push_remaining := 0.0
var _push_total := 0.0
var _push_collision: ProjectileCollision
var _orbit: EnemyOrbitPath
var _stun_effect: EnemyStunEffect
var _ground_moved := false
var _ground_real_velocity := Vector3.ZERO
var _flat_motion: FlatGroundMotion
@onready var sprite: Sprite3D = $Sprite

func supports_central_update() -> bool:
	return get_script().resource_path in [
		"res://scripts/enemies/slime.gd", "res://scripts/enemies/creature_enemy.gd",
		"res://scripts/enemies/leaf_charger.gd", "res://scripts/enemies/lantern_spitter.gd",
		"res://scripts/enemies/pot_brood.gd", "res://scripts/enemies/bell_frog.gd",
		"res://scripts/enemies/mini_slime.gd"]

func get_crowd_spacing() -> float:
	return separation_radius

func get_crowd_body_radius() -> float:
	return body_radius

var _native_chase_input := PackedFloat64Array()

## One reusable value packet avoids dozens of reflected property reads in C++.
## Values are refreshed on every call, so parameter edits and buffs stay live.
func _try_native_chase(delta: float, stop: float) -> bool:
	if not _native_swarm or not target is Player or not navigation or not spatial_index: return false
	if navigation.get_script() != TerrainPath or spatial_index.get_script().resource_path not in ["res://scripts/combat/wave_enemy_spatial_index.gd", "res://scripts/combat/crowd_batch_enemy_spatial_index.gd"]: return false
	_native_chase_input.resize(15)
	_native_chase_input[0] = _route_clock
	_native_chase_input[1] = route_interval
	_native_chase_input[2] = _waypoint
	_native_chase_input[3] = _yield_side
	_native_chase_input[4] = body_radius
	_native_chase_input[5] = gravity
	_native_chase_input[6] = combat_stop_distance
	_native_chase_input[7] = contact_distance
	_native_chase_input[8] = separation_radius
	_native_chase_input[9] = separation_strength
	_native_chase_input[10] = pursuit_flank_strength
	_native_chase_input[11] = pursuit_lookahead
	_native_chase_input[12] = 1.0 if ground_movement_enabled else 0.0
	_native_chase_input[13] = 1.0 if _ground_moved else 0.0
	_native_chase_input[14] = _push_remaining
	return _native_swarm.move_chase(self, navigation, spatial_index, target, _route, _native_chase_input, _look, effective_move_speed(), (target as Player).crowd_clearance_distance, delta, stop)

func _personal_stop_distance(base_stop: float) -> float:
	if not target is Player or (target as Player).crowd_clearance_distance <= 0.0: return base_stop
	var distance := base_stop + (target as Player).crowd_clearance_distance
	# 接触型留在攻击范围内；原本在范围外停靠的冲锋／远程招式保留自己的距离。
	if base_stop < contact_distance: distance = minf(distance, maxf(base_stop, contact_distance - 0.05))
	return distance

func _personal_space_direction(direction: Vector3, stop: float, away := Vector3.INF, distance := -1.0, speed := NAN) -> Vector3:
	if not target is Player or (target as Player).crowd_clearance_distance <= 0.0: return direction
	# 独立调用仍读实时状态；普通移动只在本次同步规划内传入已计算的值。
	if away == Vector3.INF:
		away = global_position - target.global_position
		away.y = 0.0
	if distance < 0.0: distance = away.length()
	if is_nan(speed): speed = effective_move_speed()
	away = away / distance if distance > 0.00001 else -_look.normalized()
	# 平缓限制向内速度，抵住后排压力；已进入范围时按正常移速让位，不瞬移或推玩家。
	var required := clampf((stop - distance) / (maxf(speed, 0.01) * 0.12), -1.0, 1.0)
	var radial := direction.dot(away)
	if radial < required: direction += away * (required - radial)
	return direction.limit_length(1.0)

func _update_chase_facing(desired: Vector3) -> void:
	var heading := Vector3(desired.x, 0.0, desired.z).normalized()
	# 围住目标后，整理间距的微小往返不是转身意图；受阻时继续面对目标。
	var real_velocity := _ground_real_velocity if _ground_moved else get_real_velocity()
	if heading.is_zero_approx() or real_velocity.dot(heading) < 0.15:
		if is_instance_valid(target):
			heading = target.global_position - global_position
			heading.y = 0.0
	if not heading.is_zero_approx(): _look = heading.normalized()

func _facing_index(right: Vector3, backward: Vector3) -> int:
	var angle := atan2(_look.dot(right), _look.dot(backward))
	var sector_angle := TAU / 8.0
	var nearest := posmod(roundi(angle / sector_angle), 8)
	# 在相邻方向的分界处多留 6 度，真正转向和 Q/E 旋转仍即时切换。
	if _facing_sector < 0 or absf(wrapf(angle - _facing_sector * sector_angle, -PI, PI)) > sector_angle * 0.5 + deg_to_rad(6.0):
		_facing_sector = nearest
	return _facing_sector

func _camera_facing_index() -> int:
	# A camera or its parent can turn between actors in the same rendered frame.
	# Compare its actual basis, then preserve the original flatten/normalize order.
	var basis := camera.global_basis
	if not _projection_valid or basis != _projection_basis:
		_projection_valid = true
		_projection_basis = basis
		var right := basis.x
		var backward := basis.z
		right.y = 0.0
		backward.y = 0.0
		_projection_right = right.normalized()
		_projection_backward = backward.normalized()
	return _facing_index(_projection_right, _projection_backward)

static func _clips_for(action: StringName) -> Array:
	if not _directional_clips.has(action):
		# Custom actions are allowed; bound the cache without holding game resources.
		if _directional_clips.size() >= 16:
			_directional_clips.clear()
			_clip_actions.clear()
		var clips: Array[StringName] = []
		for direction in DIRECTIONS:
			var clip := StringName("%s_%s" % [action, direction])
			clips.append(clip)
			_clip_actions[clip] = StringName(String(clip).get_slice("_", 0))
		_directional_clips[action] = clips
	return _directional_clips[action]

static func _clip_action(clip: StringName) -> StringName:
	if not _clip_actions.has(clip):
		# The previous clip may precede a cache eviction or use a custom name.
		if _clip_actions.size() >= 144: _clip_actions.clear()
		_clip_actions[clip] = StringName(String(clip).get_slice("_", 0))
	return _clip_actions[clip]

func _crowd_direction(desired: Vector3) -> Vector3:
	if separation_radius <= 0.0 or separation_strength <= 0.0: return desired
	var separation := Vector3.ZERO
	if spatial_index:
		separation = spatial_index.separation(self, separation_radius)
	else:
		for other: WaveEnemy in get_tree().get_nodes_in_group(&"wave_enemies"):
			if other == self or other.dead or other.spawn_delay > 0.0: continue
			var spacing := (maxf(separation_radius, body_radius * 2.1) + maxf(other.get_crowd_spacing(), other.get_crowd_body_radius() * 2.1)) * 0.5
			separation += WaveEnemySpatialIndex.crowd_pair_force(global_position - other.global_position, spacing, body_radius + other.get_crowd_body_radius(), get_instance_id(), other.get_instance_id())
	# 不能 normalized()：抵消前进的避让力应降低速度，后排才能在前排后面停住。
	return (desired + separation * separation_strength).limit_length(1.0)

## 只用于普通追击：沿局部压力较小的一侧让行，不改停步整理、退步或锁线招式。
func _pursuit_crowd_direction(desired: Vector3, origin := Vector3.INF, target_distance := -1.0) -> Vector3:
	var direction := _crowd_direction(desired)
	if desired.is_zero_approx() or pursuit_flank_strength <= 0.0 or separation_strength <= 0.0: return direction
	var pressure := clampf(1.0 - direction.dot(desired), 0.0, 1.0)
	if pressure < 0.35:
		_yield_side = 0.0
		return direction
	if origin == Vector3.INF: origin = global_position
	if target_distance < 0.0: target_distance = TerrainPath.horizontal_distance(origin, target.global_position)
	var spacing := maxf(separation_radius, body_radius * 2.1)
	var approach := smoothstep(combat_stop_distance + spacing * 0.3, combat_stop_distance + spacing * 1.5, target_distance)
	var amount := pursuit_flank_strength * pressure * approach
	if amount < 0.02:
		_yield_side = 0.0
		return direction
	var side := Vector3.UP.cross(desired)
	if _yield_side == 0.0:
		var lateral := direction.dot(side)
		_yield_side = signf(lateral) if absf(lateral) > 0.08 else (1.0 if hash(get_instance_id()) % 2 == 0 else -1.0)
	for choice in [_yield_side, -_yield_side]:
		var candidate: Vector3 = (direction + side * choice * amount).limit_length(1.0)
		var next := origin + candidate * maxf(0.35, body_radius)
		if navigation.data and not navigation.can_walk_direct(origin, navigation.ground_position(next)): continue
		_yield_side = choice
		return candidate
	return direction

## 史莱姆及其具体怪物子类共用实际显示高度，换素材或缩放后自动适配。
func get_damage_feedback_position() -> Vector3:
	if is_instance_valid(sprite) and sprite.texture:
		var pixel := sprite.pixel_size * sprite.global_basis.y.length()
		return sprite.global_position + Vector3.UP * (sprite.texture.get_height() * pixel * 0.5 + pixel * 3.0)
	return global_position + Vector3.UP * body_height

func _enter_tree() -> void:
	if wave_mode: $Sprite.set("shared_materials", true)

func configure_wave(context: Dictionary, definition: WaveEnemyDefinition, warning: float) -> void:
	super.configure_wave(context, definition, warning)
	terrain = context.terrain
	target = wave_target
	camera = context.camera
	_path = navigation
	if definition is WaveMeleeEnemyDefinition:
		var melee := definition as WaveMeleeEnemyDefinition
		body_radius = melee.body_radius
		body_height = melee.body_height
		gravity = melee.gravity
		route_interval = melee.route_interval
		separation_radius = melee.separation_radius
		separation_strength = melee.separation_strength
		pursuit_lookahead = melee.pursuit_lookahead
		pursuit_flank_strength = melee.pursuit_flank_strength
		knockback_multiplier = melee.knockback_multiplier
		combat_stop_distance = melee.combat_stop_distance
		contact_distance = melee.contact_distance
		contact_height = melee.contact_height
		animation_speed = melee.animation_speed
		hit_flash_seconds = melee.hit_flash_seconds

func _ready() -> void:
	super._ready()
	add_to_group(&"enemies")
	_random.seed = random_seed
	var shape := $Collision.shape.duplicate() as CapsuleShape3D
	$Collision.shape = shape
	shape.radius = body_radius
	shape.height = maxf(body_height,body_radius*2.0)
	$Collision.position.y = shape.height*0.5
	home_position = global_position
	_idle_clock = _rest_time()
	_sprite_scale = sprite.scale
	_sprite_color = sprite.modulate
	if wave_mode:
		_set_state(State.CHASE)
	else:
		_initialize.call_deferred()

func _initialize() -> void:
	for frame in 3: await get_tree().physics_frame
	if not terrain or not terrain.data: return
	var cell := terrain.data.world_to_cell(terrain.to_local(global_position))
	global_position.y = _path_height(cell)+0.02
	home_position = global_position
	_rebuild_path()
	terrain.data.changed.connect(_queue_path_rebuild)
	_ready_for_ai = true

func _queue_path_rebuild() -> void:
	if _path_rebuild_pending: return
	_path_rebuild_pending = true
	_rebuild_after_physics.call_deferred()

func _rebuild_after_physics() -> void:
	# Terrain rebuilds its physics body after data changes; use the new RID.
	for frame in 2: await get_tree().physics_frame
	_path_rebuild_pending = false
	_rebuild_path()

func _path_height(cell: Vector2i) -> float:
	var heights := terrain._corner_heights(cell)
	return terrain.global_position.y+(heights[0]+heights[1]+heights[2]+heights[3])*0.25

func _rebuild_path() -> void:
	var exclude: Array[RID] = [get_rid()]
	if target is CollisionObject3D: exclude.append(target.get_rid())
	for enemy in get_tree().get_nodes_in_group(&"enemies"):
		if enemy is CollisionObject3D and enemy != self: exclude.append(enemy.get_rid())
	_path.build(terrain,body_radius,exclude)
	_route.clear()
	_route_clock = 0.0

func _rest_time() -> float:
	return _random.randf_range(maxf(0.1,idle_seconds.x),maxf(idle_seconds.x,idle_seconds.y))

func _set_state(value: State) -> void:
	if state == value: return
	state = value
	_route_clock = 0.0
	_route.clear()
	_stuck_clock = 0.0
	if state == State.IDLE: _idle_clock = _rest_time()
	state_changed.emit(state)

func _can_see_target() -> bool:
	if not is_instance_valid(target): return false
	if absf(target.global_position.y-global_position.y) > 1.6: return false
	var exclude: Array[RID] = [get_rid()]
	if target is CollisionObject3D: exclude.append(target.get_rid())
	var query := PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*0.5,target.global_position+Vector3.UP*0.7,1,exclude)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _pick_patrol() -> void:
	for attempt in 12:
		var angle := _random.randf()*TAU
		var goal := home_position+Vector3(cos(angle),0,sin(angle))*_random.randf_range(0.5,maxf(0.5,patrol_radius))
		var route := _path.route(global_position,goal)
		if route.size() < 2: continue
		patrol_goal = route[-1]
		if TerrainPath.horizontal_distance(patrol_goal,home_position) > minf(patrol_radius,leash_distance)+0.05: continue
		_set_state(State.PATROL)
		_route = route
		_waypoint = 1
		_route_clock = route_interval
		return
	_idle_clock = _rest_time()

func _physics_process(delta: float) -> void:
	if wave_mode:
		super._physics_process(delta)
		return
	velocity.y = 0.0 if is_on_floor() else velocity.y-gravity*delta
	var direction := Vector3.ZERO
	var speed := patrol_speed
	if _ready_for_ai:
		var distance := TerrainPath.horizontal_distance(global_position,target.global_position) if is_instance_valid(target) else INF
		var in_leash := is_instance_valid(target) and TerrainPath.horizontal_distance(target.global_position,home_position) <= leash_distance
		if state != State.RETURN and state != State.CHASE and distance <= detect_distance and in_leash and _can_see_target():
			_lost_sight = 0.0
			_set_state(State.CHASE)
		if state == State.CHASE:
			_lost_sight = 0.0 if _can_see_target() else _lost_sight+delta
			if not in_leash or TerrainPath.horizontal_distance(global_position,home_position) >= leash_distance or _lost_sight > lost_sight_seconds:
				_set_state(State.RETURN)
		if state == State.IDLE:
			_idle_clock -= delta
			if _idle_clock <= 0.0 and patrol_radius > 0.0: _pick_patrol()
		else:
			var goal := home_position if state == State.RETURN else (target.global_position if state == State.CHASE and is_instance_valid(target) else patrol_goal)
			var arrival := stop_distance if state == State.CHASE else 0.15
			if TerrainPath.horizontal_distance(global_position,goal) <= arrival:
				if state != State.CHASE: _set_state(State.IDLE)
			else:
				_route_clock -= delta
				if _route_clock <= 0.0:
					_route_clock = route_interval
					_route = _path.route(global_position,goal)
					_waypoint = 1 if _route.size() > 1 else 0
					if _route.is_empty():
						if state == State.CHASE: _set_state(State.RETURN)
						elif state == State.PATROL: _set_state(State.IDLE)
				if not _route.is_empty():
					while _waypoint < _route.size()-1 and TerrainPath.horizontal_distance(global_position,_route[_waypoint]) < 0.14: _waypoint += 1
					var point := _route[_waypoint]
					# The last segment ends at the exact goal, rather than oscillating around a cell centre.
					if _waypoint == _route.size()-1: point = goal
					direction = point-global_position
					direction.y = 0.0
					direction = direction.normalized()
					if state == State.CHASE: speed = chase_speed
	velocity.x = direction.x*speed
	velocity.z = direction.z*speed
	if direction != Vector3.ZERO: _look = direction
	var before := global_position
	move_and_slide()
	if direction != Vector3.ZERO and TerrainPath.horizontal_distance(before,global_position) < speed*delta*0.1:
		_stuck_clock += delta
		if _stuck_clock > 1.2:
			if state == State.RETURN:
				_rebuild_path()
				_stuck_clock = 0.0
			else:
				_set_state(State.RETURN if state == State.CHASE else State.IDLE)
	else:
		_stuck_clock = 0.0

func _on_stun_started() -> void:
	_route.clear()
	_route_clock = 0.0
	if not is_instance_valid(_stun_effect):
		_stun_effect = EnemyStunEffect.new()
		add_child(_stun_effect)
	_stun_effect.begin(self, sprite, body_height)

func _on_stun_ended() -> void:
	_route_clock = 0.0
	if is_instance_valid(_stun_effect): _stun_effect.stop()

func _stunned_tick(delta: float) -> void:
	_ground_moved = false
	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
	move_and_slide()

func _combat_tick(delta: float) -> void:
	if _try_native_chase(delta, combat_stop_distance):
		_combat_contact()
		return
	velocity.y = 0.0 if _ground_moved or is_on_floor() else velocity.y - gravity * delta
	# 规划期间没有移动；完成 move_and_slide 后的朝向与接触判定继续读取实际落点。
	var origin := global_position
	var goal := target.global_position
	var away := origin - goal
	away.y = 0.0
	var target_distance := TerrainPath.horizontal_distance(origin, goal)
	var direction := Vector3.ZERO
	var stop := _personal_stop_distance(combat_stop_distance)
	if target_distance > stop:
		_route_clock -= delta
		if _route_clock <= 0.0:
			_route_clock = route_interval
			_route = _path.chase_route(origin, goal, pursuit_lookahead)
			_waypoint = 1 if _route.size() > 1 else 0
		if not _route.is_empty() and TerrainPath.horizontal_distance(origin, _route[-1]) > 0.1:
			while _waypoint < _route.size() - 1 and TerrainPath.horizontal_distance(origin, _route[_waypoint]) < 0.14:
				_waypoint += 1
			direction = _route[_waypoint] - origin
			direction.y = 0.0
			direction = direction.normalized()
	var intended := direction
	direction = _pursuit_crowd_direction(direction, origin, target_distance)
	var actual_speed := effective_move_speed()
	direction = _personal_space_direction(direction, stop, away, target_distance, actual_speed)
	velocity.x = direction.x * actual_speed
	velocity.z = direction.z * actual_speed
	_move_combat_body(delta)
	_update_chase_facing(intended)
	_combat_contact()

func _combat_contact() -> void:
	# 接触范围、高差和遮挡属于史莱姆招式，不放进通用波次控制器。
	if TerrainPath.horizontal_distance(global_position, target.global_position) < contact_distance and absf(global_position.y - target.global_position.y) < contact_height and (not can_damage_player.is_valid() or can_damage_player.call(attack_damage)) and _can_see_target():
		damage_player.call(attack_damage)

func _supports_ground_movement() -> bool:
	return true

## Ordinary spacing is solved by pursuit/clearance, not by native recovery
## pushing the monster out of the player and into a neighbouring wall.
## The exception is scoped: charge hit detection and other actions keep the
## original player collider, and externally owned exceptions remain untouched.
func _slide_ordinary() -> void:
	var ignored := wave_target if wave_mode and is_instance_valid(wave_target) else null
	var added := ignored != null and not get_collision_exceptions().has(ignored)
	if added: add_collision_exception_with(ignored)
	move_and_slide()
	if added and is_instance_valid(ignored): remove_collision_exception_with(ignored)

func _move_combat_body(delta: float) -> void:
	_ground_moved = false
	if not ground_movement_enabled or not _supports_ground_movement():
		_slide_ordinary()
		return
	var start := global_position
	# Only ordinary grounded motion opts in. Special actions keep their own solver.
	if navigation and delta > 0.0 and _push_remaining <= 0.0 and global_basis == Basis.IDENTITY and up_direction == Vector3.UP and motion_mode == MOTION_MODE_GROUNDED and velocity.y <= 0.0 and velocity.y >= -gravity * delta * 1.01:
		if _native_swarm:
			if _native_swarm.move_body(self, navigation, delta, body_radius):
				_ground_moved = true
				_ground_real_velocity = (global_position - start) / delta
			else: _slide_ordinary()
			return
		if not _flat_motion: _flat_motion = FlatGroundMotion.new()
		if _flat_motion.try_move(self, navigation, delta, body_radius, wave_target if wave_mode else null):
			_ground_moved = true
			_ground_real_velocity = (global_position - start) / delta
			return
	_slide_ordinary()

func _damage_feedback() -> void:
	_hit_flash = hit_flash_seconds

func apply_push_impulse(heading: Vector3, initial_speed: float, seconds: float) -> bool:
	if not wave_mode or dead or spawn_delay > 0.0 or not navigation or not heading.is_finite() or not is_finite(initial_speed) or not is_finite(seconds) or initial_speed <= 0.0 or seconds <= 0.0 or knockback_multiplier <= 0.0: return false
	if combat_active.is_valid() and not combat_active.call(): return false
	heading.y = 0.0
	if heading.is_zero_approx(): return false
	_push_wave = null
	_orbit = null
	_push_direction = heading.normalized()
	_push_speed = initial_speed * knockback_multiplier
	_push_remaining = seconds
	_push_total = seconds
	if not _push_collision: _push_collision = ProjectileCollision.new()
	return true

func apply_orbit(region: Dictionary, heading: Vector3, speed: float, seconds: float, clockwise: bool) -> bool:
	if not apply_push_impulse(heading, speed, seconds): return false
	_orbit = EnemyOrbitPath.new(region, global_position, heading, clockwise, speed, seconds, knockback_multiplier, body_radius)
	_push_total = _orbit.duration
	_push_remaining = _push_total
	_push_speed = _orbit.initial_speed
	return true

func is_orbiting() -> bool:
	return _orbit != null and _push_remaining > 0.0

func _advance_push(delta: float) -> void:
	if _push_remaining <= 0.0 or dead: return
	if _orbit:
		_advance_orbit(delta)
		return
	var step := minf(delta, _push_remaining)
	# 对线性衰减速度积分，避免推开距离随物理帧率改变。
	var distance := _push_speed * (_push_remaining * step - 0.5 * step * step) / _push_total
	_push_remaining -= step
	var plane := navigation.ground_position(global_position).y
	var allowed := _push_collision.ground_limit(navigation, global_position, _push_direction, distance, plane, 0.2)
	if allowed > 0.00001:
		var motion := _push_direction * allowed
		motion.y = navigation.ground_position(global_position + motion).y + 0.02 - global_position.y
		if move_and_collide(motion): _push_remaining = 0.0
	if allowed < distance: _push_remaining = 0.0
	_route_clock = 0.0
	commit_spatial_state()

func _advance_orbit(delta: float) -> void:
	_push_remaining = maxf(0.0, _push_remaining - delta)
	var goal := _orbit.distance_at(_push_total - _push_remaining)
	var blocked := false
	while _orbit.cursor < _orbit.points.size() and _orbit.travelled < goal - 0.000001:
		var index := _orbit.cursor
		var reach := minf(goal, _orbit.distances[index])
		var fraction := (reach - _orbit.distances[index - 1]) / maxf(_orbit.distances[index] - _orbit.distances[index - 1], 0.000001)
		var destination := _orbit.points[index - 1].lerp(_orbit.points[index], fraction)
		var start := global_position
		var motion := destination - start
		motion.y = 0.0
		var length := motion.length()
		var heading := motion.normalized()
		var plane := navigation.ground_position(start).y
		var allowed := _push_collision.ground_limit(navigation, start, heading, length, plane, 0.2)
		if allowed > 0.000001:
			motion = heading * allowed
			motion.y = navigation.ground_position(start + motion).y + 0.02 - start.y
			blocked = move_and_collide(motion) != null
		if _push_wave: _push_wave.spread(self, start, global_position, _orbit, _orbit.travelled, _push_layer)
		_orbit.travelled = reach
		if blocked or allowed + 0.000001 < length:
			_push_remaining = 0.0
			break
		if reach >= _orbit.distances[index] - 0.000001: _orbit.cursor += 1
	if _push_remaining <= 0.0:
		_orbit = null
		_push_wave = null
	_route_clock = 0.0
	commit_spatial_state()

func apply_knockback(push: Vector3, distance: float) -> void:
	if not wave_mode or dead or distance <= 0.0 or push == Vector3.ZERO: return
	distance *= knockback_multiplier
	if distance <= 0.0: return
	var destination := navigation.ground_position(global_position + push * distance)
	# 不击落台地，也不跨断层或穿墙。
	if absf(destination.y - navigation.ground_position(global_position).y) > 0.2 or navigation.route(global_position, destination).is_empty(): return
	move_and_collide(push * distance)
	if is_orbiting():
		# 新的独立击退接管运动，避免下一帧被旧的绝对轨迹拉回。
		_orbit = null
		_push_wave = null
		_push_remaining = 0.0
	commit_spatial_state()
	_route_clock = 0.0

func _process(delta: float) -> void:
	if wave_mode:
		_hit_flash = maxf(_hit_flash - delta, 0.0)
		var target_scale := _sprite_scale
		if sprite.scale != target_scale: sprite.scale = target_scale
		var tint := _sprite_color * (1.8 if _hit_flash > 0.0 else 1.0)
		tint.a = _sprite_color.a
		if sprite.modulate != tint: sprite.modulate = tint
	if not animations or not camera: return
	var facing := _camera_facing_index()
	var moving := Vector2(velocity.x,velocity.z).length() > 0.05
	var clip: StringName = _clips_for(&"hop" if moving else &"idle")[facing]
	if not animations.has_animation(clip): return
	if clip != _clip:
		# Keep the motion phase when Q/E changes the observed direction.
		if _clip_action(_clip) != _clip_action(clip):
			_frame = 0; _elapsed = 0.0
		_clip = clip
	var count := animations.get_frame_count(_clip)
	var fps := animations.get_animation_speed(_clip)
	if count == 0 or fps <= 0.0: return
	_frame %= count
	_elapsed += delta*animation_speed
	var duration := animations.get_frame_duration(_clip,_frame)/fps
	while _elapsed >= duration:
		_elapsed -= duration
		_frame = (_frame+1)%count
		duration = animations.get_frame_duration(_clip,_frame)/fps
	var texture := animations.get_frame_texture(_clip,_frame)
	if sprite.texture != texture: sprite.texture = texture
