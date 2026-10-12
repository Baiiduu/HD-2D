class_name SlimeEnemy
extends CharacterBody3D

enum State { IDLE, PATROL, CHASE, RETURN }
const DIRECTIONS := ["front","front_right","right","back_right","back","back_left","left","front_left"]
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
var _clip: StringName = &""
var _frame := 0
var _elapsed := 0.0
@onready var sprite: Sprite3D = $Sprite

func _ready() -> void:
	add_to_group(&"enemies")
	_random.seed = random_seed
	var shape := $Collision.shape.duplicate() as CapsuleShape3D
	$Collision.shape = shape
	shape.radius = body_radius
	shape.height = maxf(body_height,body_radius*2.0)
	$Collision.position.y = shape.height*0.5
	home_position = global_position
	_idle_clock = _rest_time()
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

func _process(delta: float) -> void:
	if not animations or not camera: return
	var right := camera.global_basis.x
	var backward := camera.global_basis.z
	right.y = 0.0; backward.y = 0.0
	var angle := atan2(_look.dot(right.normalized()),_look.dot(backward.normalized()))
	var facing := posmod(roundi(angle/(TAU/8.0)),8)
	var moving := Vector2(velocity.x,velocity.z).length() > 0.05
	var clip := StringName(("hop_" if moving else "idle_")+DIRECTIONS[facing])
	if not animations.has_animation(clip): return
	if clip != _clip:
		# Keep the motion phase when Q/E changes the observed direction.
		if String(_clip).get_slice("_",0) != String(clip).get_slice("_",0):
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
	sprite.texture = animations.get_frame_texture(_clip,_frame)
