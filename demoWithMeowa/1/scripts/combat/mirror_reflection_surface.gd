extends StaticBody3D

## 独立反射层：走路、怪物导航和不反弹的攻击仍只查询原有层。
const COLLISION_LAYER := 4
signal reflected

var enemy: WaveEnemy
var normal := Vector3.LEFT
var _shape := BoxShape3D.new()
var _follow: RemoteTransform3D

func _init() -> void:
	collision_layer = 0
	collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = _shape
	add_child(collision)

func attach(target: WaveEnemy, surface_normal: Vector3, size: Vector2, height: float) -> void:
	stop()
	if target.dead: return
	enemy = target
	normal = surface_normal.normalized()
	# 镜片画在胸前；竖向延到脚底，让较低的贴地弹丸也能碰镜，宽度仍取原图。
	var collision_height := height + size.y * 0.5
	_shape.size = Vector3(size.x, collision_height, 0.02)
	global_transform = Transform3D(Basis(Vector3.UP.cross(normal), Vector3.UP, normal), target.global_position + Vector3.UP * collision_height * 0.5)
	# 只推送位置，怪物转向／缩放与 Q/E 均不改变首次固定的世界镜面。
	_follow = RemoteTransform3D.new()
	_follow.update_rotation = false
	_follow.update_scale = false
	target.add_child(_follow)
	_follow.global_position = global_position
	_follow.remote_path = _follow.get_path_to(self)
	_follow.force_update_cache()
	target.defeated.connect(_on_defeated)
	target.tree_exiting.connect(stop)
	# 新贴印同一物理帧就可能被另一枚弹丸查询，先提交位置再开放碰撞层。
	force_update_transform()
	collision_layer = COLLISION_LAYER

func _on_defeated(_target: WaveEnemy) -> void:
	stop()

func stop() -> void:
	collision_layer = 0
	if is_instance_valid(enemy):
		if enemy.defeated.is_connected(_on_defeated): enemy.defeated.disconnect(_on_defeated)
		if enemy.tree_exiting.is_connected(stop): enemy.tree_exiting.disconnect(stop)
	enemy = null
	if is_instance_valid(_follow):
		_follow.remote_path = NodePath()
		_follow.queue_free()
	_follow = null

func _exit_tree() -> void:
	stop()
