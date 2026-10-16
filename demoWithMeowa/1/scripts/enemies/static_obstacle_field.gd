class_name StaticObstacleField
extends Node3D

## Conservative XZ occupancy: any touched cell is occupied, never just its centre.
## It only certifies absence. All uncertain/near-wall moves keep native sweeps.
const BODY_WATCH = preload("res://scripts/enemies/static_obstacle_watch.gd")
const SHAPE_WATCH = preload("res://scripts/enemies/static_shape_watch.gd")
const CELL := 1.0
const PADDING := 0.01
const MAX_DENSE_CELLS := 65536
const NO_EXCLUSIONS: Array[RID] = []
var source: Node3D
var _static: Dictionary = {}
var _polled: Dictionary = {}
var _dynamic: Dictionary = {}
var _occupied: Dictionary[Vector2i, bool] = {}
var _grid_bounds := Rect2i()
var _grid := PackedByteArray()
var _prefix := PackedInt32Array()
var _dirty := true
var _bound_shapes: Dictionary[Shape3D, Array] = {}
var _checked_frame := -1
var _baking := false
var enabled := true

func _ready() -> void:
	var tree := get_tree()
	tree.node_added.connect(_node_added)
	tree.node_removed.connect(_node_removed)
	_baking = true
	for object in tree.root.find_children("*", "PhysicsBody3D", true, false):
		if object.get_world_3d() != get_world_3d() or object == source.call("ground_collision_body"): continue
		if object.collision_layer == 2 and object.get("wave_mode") == true: continue
		if object is StaticBody3D and object.get_script() == null:
			_register_static(object)
		else:
			_dynamic[object] = true
	_baking = false
	_rebuild()

func _register_static(body: StaticBody3D) -> void:
	var shapes: Array[CollisionShape3D] = []
	for child in body.get_children():
		if not child is CollisionShape3D or child.get_script() != null:
			_dynamic[body] = true
			return
		shapes.append(child)
	if shapes.is_empty() or body.get_shape_owners().size() != shapes.size():
		_dynamic[body] = true
		return
	body.force_update_transform()
	body.set_script(BODY_WATCH)
	body.set("obstacle_field", weakref(self))
	var resources: Array[Shape3D] = []
	for collider in shapes:
		collider.force_update_transform()
		collider.set_script(SHAPE_WATCH)
		collider.set("obstacle_field", weakref(self))
		resources.append(collider.shape)
		if collider.shape:
			if not _bound_shapes.has(collider.shape):
				_bound_shapes[collider.shape] = []
				collider.shape.changed.connect(_shape_changed.bind(collider.shape.get_instance_id()))
			var id := body.get_instance_id()
			if not _bound_shapes[collider.shape].has(id):
				_bound_shapes[collider.shape].append(id)
	_static[body] = {"nodes": shapes, "shapes": resources, "layer": body.collision_layer}
	# The generators own managed shape bindings and rebuild whole subtrees.
	# Unknown sources retain the once-per-step identity check as a safety net.
	if not body.get_meta(&"obstacle_layout_managed", false): _polled[body] = _static[body]
	body.script_changed.connect(_binding_script_changed.bind(body.get_instance_id()))
	for collider in shapes:
		collider.script_changed.connect(_binding_script_changed.bind(body.get_instance_id()))

func _binding_script_changed(id: int) -> void:
	var body := instance_from_id(id) as Node
	if body: make_dynamic(body)

func _shape_changed(id: int) -> void:
	# One subscription per shared resource; revoke every owning body's raster.
	# Bind an integer, not the Resource itself, to avoid a reference cycle.
	var shape := instance_from_id(id) as Shape3D
	if not shape: return
	for owner: int in _bound_shapes.get(shape, []):
		var body := instance_from_id(owner) as Node
		if body: make_dynamic(body)

func make_dynamic(body: Node) -> void:
	if _baking or not _static.has(body): return
	_static.erase(body)
	_polled.erase(body)
	_dynamic[body] = true
	_dirty = true

## Use before native shape replacement or PhysicsServer/shape-owner edits.
## Managed generator bindings are immutable until revoked, even across frames.
## Ordinary Node transforms, shape-resource edits and hierarchy changes are watched.
func invalidate_layout() -> void:
	for body in _static.keys(): make_dynamic(body)

func _node_added(node: Node) -> void:
	if node is PhysicsBody3D:
		if node.get_world_3d() != get_world_3d(): return
		if node.collision_layer == 2 and node.get("wave_mode") == true: return
		_dynamic[node] = true
	elif node is CollisionShape3D or node is CollisionPolygon3D:
		make_dynamic(node.get_parent())

func _node_removed(node: Node) -> void:
	if _static.erase(node): _dirty = true
	_polled.erase(node)
	_dynamic.erase(node)
	if node is CollisionShape3D or node is CollisionPolygon3D:
		make_dynamic(node.get_parent())

func _validate_bindings() -> void:
	var frame := Engine.get_physics_frames()
	if frame == _checked_frame: return
	_checked_frame = frame
	# Replacing a native shape property has no changed signal. Check identities,
	# not geometry, once for the entire batch; changed sources become live guards.
	for body in _polled.keys():
		var entry: Dictionary = _polled[body]
		if body.get_script() != BODY_WATCH or body.collision_layer != entry.layer or body.get_child_count() != entry.nodes.size():
			make_dynamic(body)
			continue
		for i in entry.nodes.size():
			if entry.nodes[i].get_script() != SHAPE_WATCH or entry.nodes[i].shape != entry.shapes[i]:
				make_dynamic(body)
				break

static func shape_bounds(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		return AABB(-shape.size * 0.5, shape.size).grow(shape.margin)
	if shape is SphereShape3D:
		return AABB(Vector3.ONE * -shape.radius, Vector3.ONE * shape.radius * 2.0).grow(shape.margin)
	if shape is CapsuleShape3D or shape is CylinderShape3D:
		var half := Vector3(shape.radius, shape.height * 0.5, shape.radius)
		return AABB(-half, half * 2.0).grow(shape.margin)
	if shape is ConvexPolygonShape3D or shape is ConcavePolygonShape3D:
		var points: PackedVector3Array = shape.points if shape is ConvexPolygonShape3D else shape.get_faces()
		if points.is_empty(): return AABB(Vector3.INF, Vector3.ZERO)
		var box := AABB(points[0], Vector3.ZERO)
		for point in points: box = box.expand(point)
		return box.grow(shape.margin)
	return AABB(Vector3.INF, Vector3.ZERO)

static func world_bounds(collider: CollisionShape3D) -> AABB:
	if not collider.shape: return AABB(Vector3.INF, Vector3.ZERO)
	return transformed_bounds(collider.shape, collider.global_transform)

static func transformed_bounds(shape: Shape3D, transform: Transform3D) -> AABB:
	var local := shape_bounds(shape)
	if not local.position.is_finite(): return local
	# Physics may decompose shear/nonuniform rounded shapes differently. Only
	# accept transforms whose physical bound follows the same affine transform.
	if transform.basis != Basis.IDENTITY:
		var scale := Vector3(transform.basis.x.length(), transform.basis.y.length(), transform.basis.z.length())
		if minf(scale.x, minf(scale.y, scale.z)) <= 0.0: return AABB(Vector3.INF, Vector3.ZERO)
		var axes := Basis(transform.basis.x / scale.x, transform.basis.y / scale.y, transform.basis.z / scale.z)
		if not axes.is_equal_approx(axes.orthonormalized()): return AABB(Vector3.INF, Vector3.ZERO)
		if shape is CapsuleShape3D or shape is SphereShape3D or shape is CylinderShape3D:
			if not is_equal_approx(scale.x, scale.y) or not is_equal_approx(scale.x, scale.z): return AABB(Vector3.INF, Vector3.ZERO)
	return (transform * local).grow(PADDING)

func _key(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / CELL), floori(point.z / CELL))

func _rebuild() -> void:
	_occupied.clear()
	for body in _static.keys():
		var entry: Dictionary = _static[body]
		var supported := true
		for collider in entry.nodes:
			var bounds := world_bounds(collider)
			if not bounds.position.is_finite():
				supported = false
				break
			var first := _key(bounds.position)
			var last := _key(bounds.end)
			# Unbounded/huge user shapes should not allocate a world-sized raster.
			if (last.x - first.x + 1) * (last.y - first.y + 1) > 16384:
				supported = false
				break
			for z in range(first.y, last.y + 1):
				for x in range(first.x, last.x + 1): _occupied[Vector2i(x,z)] = true
		if not supported: make_dynamic(body)
	_build_grid()
	_dirty = false

func _build_grid() -> void:
	_grid_bounds = Rect2i()
	_grid.clear()
	_prefix.clear()
	for cell: Vector2i in _occupied:
		var single := Rect2i(cell, Vector2i.ONE)
		_grid_bounds = _grid_bounds.merge(single) if _grid_bounds.has_area() else single
	if not _grid_bounds.has_area() or _grid_bounds.get_area() > MAX_DENSE_CELLS: return
	var width := _grid_bounds.size.x
	var height := _grid_bounds.size.y
	_grid.resize(width * height)
	_grid.fill(0)
	for cell: Vector2i in _occupied:
		var local := cell - _grid_bounds.position
		_grid[local.y * width + local.x] = 1
	var stride := width + 1
	_prefix.resize(stride * (height + 1))
	_prefix.fill(0)
	for z in height:
		var row := 0
		for x in width:
			row += _grid[z * width + x]
			_prefix[(z + 1) * stride + x + 1] = _prefix[z * stride + x + 1] + row

func _static_clear(first: Vector2i, last: Vector2i) -> bool:
	if _occupied.is_empty(): return true
	if _prefix.is_empty():
		# Widely separated static bodies retain the bounded sparse fallback.
		if (last.x - first.x + 1) * (last.y - first.y + 1) > 256: return false
		for z in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				if _occupied.has(Vector2i(x,z)): return false
		return true
	first = first.max(_grid_bounds.position)
	last = last.min(_grid_bounds.end - Vector2i.ONE)
	if first.x > last.x or first.y > last.y: return true
	first -= _grid_bounds.position
	last -= _grid_bounds.position
	var width := _grid_bounds.size.x
	# The common short body move touches few cells; avoid four prefix reads.
	if (last.x - first.x + 1) * (last.y - first.y + 1) <= 4:
		for z in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				if _grid[z * width + x] != 0: return false
		return true
	var stride := width + 1
	var low := first.y * stride
	var high := (last.y + 1) * stride
	return _prefix[high + last.x + 1] - _prefix[low + last.x + 1] - _prefix[high + first.x] + _prefix[low + first.x] == 0

func clear_motion(body: CharacterBody3D, support: StaticBody3D, motion: Vector3) -> bool:
	if not enabled: return false
	var collider := body.get_node_or_null("Collision") as CollisionShape3D
	if not collider or collider.disabled or not collider.shape is CapsuleShape3D: return false
	var start := world_bounds(collider)
	if not start.position.is_finite(): return false
	var swept := start.merge(AABB(start.position + motion, start.size)).grow(body.safe_margin)
	var mask := body.collision_mask
	# A raster miss already requires native physics. Avoid shape-owner array
	# allocation and binding reads until there is an actual empty-space candidate.
	if not _fixed_clear(swept, mask): return false
	var owners := body.get_shape_owners()
	if owners.size() != 1 or body.shape_owner_get_shape_count(owners[0]) != 1: return false
	if body.shape_owner_get_owner(owners[0]) != collider or body.shape_owner_get_shape(owners[0], 0) != collider.shape or body.shape_owner_get_transform(owners[0]) != collider.transform: return false
	return _dynamic_clear(swept, mask, NO_EXCLUSIONS, body, support)

## Navigation uses its own shape, margin, height, mask and exclusions. A body
## certificate is never reused as proof for a differently sized query sphere.
func clear_query(query: PhysicsShapeQueryParameters3D) -> bool:
	if not enabled or query.collide_with_areas or not query.collide_with_bodies: return false
	var start := transformed_bounds(query.shape, query.transform)
	if not start.position.is_finite() or not query.motion.is_finite(): return false
	var swept := start.merge(AABB(start.position + query.motion, start.size)).grow(query.margin)
	return clear_query_bounds(swept, query.collision_mask, query.exclude)

## Prepared navigation queries submit value bounds and their own exclusions;
## arbitrary native query parameters continue through clear_query() above.
func clear_query_bounds(swept: AABB, mask: int, excluded: Array[RID]) -> bool:
	if not enabled or not swept.position.is_finite() or not swept.size.is_finite(): return false
	# The known generated floor is intentionally omitted from the raster.
	# Only callers that also exclude it may use this geometric query proof.
	var support: StaticBody3D = source.call("ground_collision_body")
	if not is_instance_valid(support): return false
	if not excluded.has(support.get_rid()): return false
	return _clear_swept(swept, mask, excluded)

func _fixed_clear(swept: AABB, mask: int) -> bool:
	# Wave enemies on layer 2 are deliberately absent from this obstacle field.
	if mask & 2: return false
	if _dirty: _rebuild()
	# Stale fixed occupancy can only reject extra queries: changed bodies become
	# live guards. Reject occupied cells before polling unknown native bindings.
	if not _static_clear(_key(swept.position), _key(swept.end)): return false
	_validate_bindings()
	if not _dirty: return true
	_rebuild()
	return _static_clear(_key(swept.position), _key(swept.end))

func _clear_swept(swept: AABB, mask: int, excluded: Array[RID]) -> bool:
	return _fixed_clear(swept, mask) and _dynamic_clear(swept, mask, excluded)

func _dynamic_clear(swept: AABB, mask: int, excluded: Array[RID],
		body: PhysicsBody3D = null, support: StaticBody3D = null) -> bool:
	# Player, later walls and other unbaked bodies use their CURRENT shape/bounds.
	for other in _dynamic:
		if not is_instance_valid(other) or other == body or other == support: continue
		if (other.collision_layer & mask) == 0 or excluded.has(other.get_rid()): continue
		var live_transform: Transform3D = PhysicsServer3D.body_get_state(other.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM)
		for owner in other.get_shape_owners():
			var shape_transform: Transform3D = live_transform * other.shape_owner_get_transform(owner)
			for index in other.shape_owner_get_shape_count(owner):
				var shape: Shape3D = other.shape_owner_get_shape(owner, index)
				var bounds := transformed_bounds(shape, shape_transform)
				if not bounds.position.is_finite(): return false
				if bounds.intersects(swept): return false
	return true
