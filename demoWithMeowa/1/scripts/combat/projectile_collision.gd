class_name ProjectileCollision
extends RefCounted

## 连续球形扫掠；墙面与敌人分别查询，调用方按墙前的真实进入顺序结算。
## 查询器复用，障碍和怪物位置每次读取当前物理世界，不缓存动态结果。
var _sphere := SphereShape3D.new()
var _capsule := CapsuleShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var _broad := PhysicsShapeQueryParameters3D.new()

func _init() -> void:
	_query.shape = _sphere
	_broad.shape = _capsule
	_broad.collision_mask = 2

func wall_contact(space: PhysicsDirectSpaceState3D, start: Vector3, end: Vector3, radius: float, excluded: Array[RID]) -> Dictionary:
	_sphere.radius = radius
	_query.collision_mask = 1
	_query.exclude = excluded
	_query.transform = Transform3D(Basis.IDENTITY, start)
	_query.motion = Vector3.ZERO
	# cast_motion 忽略起点已重叠的物体；单独检查，不能把嵌墙弹丸放出去。
	var overlaps := space.intersect_shape(_query, 1)
	if not overlaps.is_empty():
		return {"distance": 0.0, "overlap": true, "normal": Vector3.ZERO, "point": start, "collider": overlaps[0].collider}
	var motion := end - start
	if motion.is_zero_approx(): return {}
	_query.motion = motion
	var fractions := space.cast_motion(_query)
	if fractions[0] >= 1.0: return {}
	# 在不安全位置取得真实接触法线，包含旋转面、圆柱和凸体的边角。
	_query.transform.origin = start + motion * minf(1.0, fractions[1] + 0.001 / motion.length())
	_query.motion = Vector3.ZERO
	var rest := space.get_rest_info(_query)
	return {"distance": motion.length() * fractions[0], "overlap": false,
		"normal": rest.get("normal", Vector3.ZERO), "point": rest.get("point", _query.transform.origin),
		"collider": instance_from_id(rest.collider_id) if rest.has("collider_id") else null}

func enemy_contacts(space: PhysicsDirectSpaceState3D, start: Vector3, end: Vector3, radius: float, eligible: Callable) -> Array[Dictionary]:
	var motion := end - start
	var length := motion.length()
	var direction := motion.normalized() if length > 0.00001 else Vector3.FORWARD
	_capsule.radius = radius
	_capsule.height = length + radius * 2.0
	_broad.transform = Transform3D(Basis(Quaternion(Vector3.UP, direction)), (start + end) * 0.5)
	_broad.exclude = []
	var excluded: Array[RID] = []
	var candidates: Array[Dictionary] = []
	# 不依赖固定返回上限；密集敌人也逐一检查真实碰撞体。
	while true:
		var found := space.intersect_shape(_broad, 1)
		if found.is_empty(): break
		var contact: Dictionary = found[0]
		excluded.append(contact.rid)
		_broad.exclude = excluded
		var enemy := contact.collider as WaveEnemy
		if enemy and eligible.call(enemy): candidates.append({"enemy": enemy, "rid": contact.rid})
	_sphere.radius = radius
	_query.collision_mask = 2
	_query.transform = Transform3D(Basis.IDENTITY, start)
	var result: Array[Dictionary] = []
	for contact in candidates:
		var others := excluded.duplicate()
		others.erase(contact.rid)
		_query.exclude = others
		_query.motion = Vector3.ZERO
		if not space.intersect_shape(_query, 1).is_empty(): contact.distance = 0.0
		elif length > 0.00001:
			_query.motion = motion
			var fraction := space.cast_motion(_query)[0]
			if fraction >= 1.0: continue
			contact.distance = length * fraction
		else: continue
		result.append(contact)
	result.sort_custom(func(a: Dictionary, b: Dictionary): return a.distance < b.distance)
	return result

## 水面、断层和地图边界终止飞行；地形不作为可弹射的墙体。
func ground_limit(path: TerrainPath, start: Vector3, direction: Vector3, distance: float, plane_height: float, tolerance: float) -> float:
	var terrain := path.terrain
	var steps := maxi(1, ceili(distance / 0.15))
	for index in steps + 1:
		var travel := distance * index / steps
		var point := start + direction * travel
		var cell := terrain.data.world_to_cell(terrain.to_local(point))
		if not terrain.data.has_cell(cell) or (terrain.data.has_overlay(cell, TerrainData.OVERLAY_WATER) and not terrain.data.has_overlay(cell, TerrainData.OVERLAY_BRIDGE)) or absf(path.ground_position(point).y - plane_height) > tolerance:
			return distance * maxi(index - 1, 0) / steps
	return distance
