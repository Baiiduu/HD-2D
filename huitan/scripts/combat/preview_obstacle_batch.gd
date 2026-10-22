extends RefCounted
## One synchronous prediction/outline query. Native overlap collects conservative obstacle
## bounds; contained rays missing all bounds can omit their individual ray query.
## Never retain this across a trace, frame, await or gameplay callback.
var _terrain: Terrain
var _query := PhysicsShapeQueryParameters3D.new()
var _shape := BoxShape3D.new()
var _bounds := AABB()
var _bounded := false
var _obstacles: Array[AABB] = []
var tests := 0
var empty_volumes := 0
var proved_rays := 0

func _init(terrain: Terrain, excluded: Array[RID]) -> void:
	_terrain = terrain
	_query.shape = _shape
	_query.collision_mask = ProjectileCollision.REFLECTION_MASK
	_query.exclude = excluded
	_query.collide_with_bodies = true
	_query.collide_with_areas = false
	_query.margin = 0.0

func cover(points: PackedVector3Array) -> void:
	_bounded = false
	_obstacles.clear()
	if points.size() < 4: return
	var minimum := points[0]
	var maximum := minimum
	for point in points:
		if not point.is_finite(): return
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	# Non-zero padding also keeps rays on the boundary inside the tested volume.
	_bounds = AABB(minimum, maximum - minimum).grow(0.01)
	_shape.size = _bounds.size
	_query.transform = Transform3D(Basis.IDENTITY, _bounds.get_center())
	tests += 1
	# The finite limit is a proof guard: saturation/unknown shapes keep native
	# rays. All shape data/transforms are read from live PhysicsServer bindings.
	var hits := _terrain.get_world_3d().direct_space_state.intersect_shape(_query, 16)
	if hits.size() >= 16: return
	for hit in hits:
		var body: RID = hit.rid
		var shape: RID = PhysicsServer3D.body_get_shape(body, hit.shape)
		var transform: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM) * PhysicsServer3D.body_get_shape_transform(body, hit.shape)
		var bounds := _native_bounds(shape, transform)
		if not bounds.position.is_finite():
			_obstacles.clear()
			return
		_obstacles.append(bounds)
	_bounded = true
	if hits.is_empty(): empty_volumes += 1

func proves(from: Vector3, to: Vector3) -> bool:
	if not _bounded or not _bounds.has_point(from) or not _bounds.has_point(to): return false
	for obstacle in _obstacles:
		if obstacle.intersects_segment(from, to) != null: return false
	proved_rays += 1
	return true

## 水平扇面共用一次角度判定；0 为已证明无障碍，1 仍须原生精查。
## 障碍包围盒在本次 cover() 内读取，不保存到下一次显示或物理步。
func fan_candidates(from: Vector3, basis: Basis, radius: float, angle: float, steps: int) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(steps + 1)
	result.fill(1)
	var extent := Vector3(radius, 0.0, radius)
	if not _bounded or angle <= 0.0 or angle > TAU + 0.000001: return result
	if not _bounds.has_point(from - extent) or not _bounds.has_point(from + extent): return result
	if not basis.y.is_equal_approx(Vector3.UP) or not basis.is_equal_approx(basis.orthonormalized()): return result
	result.fill(0)
	var inverse := basis.inverse()
	var half := angle * 0.5
	var increment := angle / steps
	for obstacle in _obstacles:
		var low := obstacle.position
		var high := obstacle.end
		if from.y < low.y or from.y > high.y: continue
		if from.x >= low.x and from.x <= high.x and from.z >= low.z and from.z <= high.z:
			result.fill(1)
			return result
		var anchor := NAN
		var first := INF
		var last := -INF
		# 盒外观察凸矩形的方向锥小于半圈，四角围出所有可能命中的方向。
		for x in [low.x, high.x]:
			for z in [low.z, high.z]:
				var local := inverse * (Vector3(x, from.y, z) - from)
				var theta := atan2(local.x, -local.z)
				if is_nan(anchor): anchor = theta
				theta = anchor + wrapf(theta - anchor, -PI, PI)
				first = minf(first, theta)
				last = maxf(last, theta)
		if last - first >= PI - 0.0001:
			result.fill(1)
			return result
		for shift in [-TAU, 0.0, TAU]:
			# 两端多保留一个原采样方向，含掠过边角及浮点舍入的余量。
			var begin := maxi(0, floori((first + shift + half) / increment) - 1)
			var end := mini(steps, ceili((last + shift + half) / increment) + 1)
			for index in range(begin, end + 1): result[index] = 1
	proved_rays += result.count(0)
	return result

static func _native_bounds(shape: RID, transform: Transform3D) -> AABB:
	var kind := PhysicsServer3D.shape_get_type(shape)
	if kind not in [PhysicsServer3D.SHAPE_BOX, PhysicsServer3D.SHAPE_SPHERE, PhysicsServer3D.SHAPE_CAPSULE, PhysicsServer3D.SHAPE_CYLINDER, PhysicsServer3D.SHAPE_CONVEX_POLYGON]: return AABB(Vector3.INF, Vector3.ZERO)
	var data: Variant = PhysicsServer3D.shape_get_data(shape)
	var half := Vector3.ZERO
	var local := AABB()
	match kind:
		PhysicsServer3D.SHAPE_BOX: half = data
		PhysicsServer3D.SHAPE_SPHERE: half = Vector3.ONE * float(data)
		PhysicsServer3D.SHAPE_CAPSULE, PhysicsServer3D.SHAPE_CYLINDER:
			half = Vector3(data.radius, data.height * 0.5, data.radius)
		PhysicsServer3D.SHAPE_CONVEX_POLYGON:
			# Read the current server vertices, including native edits without a
			# Resource.changed signal. Their enclosing box only proves absence.
			if not data is PackedVector3Array or data.is_empty(): return AABB(Vector3.INF, Vector3.ZERO)
			local = AABB(data[0], Vector3.ZERO)
			for point: Vector3 in data:
				if not point.is_finite(): return AABB(Vector3.INF, Vector3.ZERO)
				local = local.expand(point)
		_: return AABB(Vector3.INF, Vector3.ZERO)
	if not half.is_finite() or minf(half.x, minf(half.y, half.z)) < 0.0: return AABB(Vector3.INF, Vector3.ZERO)
	var scale := Vector3(transform.basis.x.length(), transform.basis.y.length(), transform.basis.z.length())
	if minf(scale.x, minf(scale.y, scale.z)) <= 0.0: return AABB(Vector3.INF, Vector3.ZERO)
	var axes := Basis(transform.basis.x / scale.x, transform.basis.y / scale.y, transform.basis.z / scale.z)
	if not axes.is_equal_approx(axes.orthonormalized()): return AABB(Vector3.INF, Vector3.ZERO)
	if kind not in [PhysicsServer3D.SHAPE_BOX, PhysicsServer3D.SHAPE_CONVEX_POLYGON] and (not is_equal_approx(scale.x, scale.y) or not is_equal_approx(scale.x, scale.z)): return AABB(Vector3.INF, Vector3.ZERO)
	if kind != PhysicsServer3D.SHAPE_CONVEX_POLYGON: local = AABB(-half, half * 2.0)
	local = local.grow(maxf(0.0, PhysicsServer3D.shape_get_margin(shape)))
	return (transform * local).grow(0.01)
