extends RefCounted

## 一场战斗共用的地面特效查询。缓存仅覆盖当前物理帧的静态地形资格；
## 挡墙碰撞每次实时检查，不缓存障碍结果。
var _terrain: Terrain
var _data: TerrainData
var _frame := -1
var _flat_regions: Dictionary = {}
var _query := PhysicsShapeQueryParameters3D.new()
var _shape := CylinderShape3D.new()

func _init() -> void:
	_shape.height = 0.04
	_query.shape = _shape
	_query.collision_mask = 1

func configure(source: Terrain, excluded: Array[RID]) -> void:
	_terrain = source
	_query.exclude = excluded
	_bind_data()

func _bind_data() -> void:
	var data := _terrain.data if is_instance_valid(_terrain) else null
	if _data == data: return
	if _data and _data.changed.is_connected(clear_cache): _data.changed.disconnect(clear_cache)
	_data = data
	if _data: _data.changed.connect(clear_cache)
	clear_cache()

func clear_cache() -> void:
	_flat_regions.clear()
	_frame = -1

func dispose() -> void:
	if _data and _data.changed.is_connected(clear_cache): _data.changed.disconnect(clear_cache)
	_data = null
	_terrain = null
	clear_cache()

## 平地资格与障碍独立：有墙的平地仍可省去逐点高度采样。
func flat_ground(origin: Vector3, radius: float) -> bool:
	if not is_instance_valid(_terrain) or not _terrain.global_basis.is_equal_approx(Basis.IDENTITY): return false
	_bind_data()
	if not _data: return false
	var frame := Engine.get_physics_frames()
	if _frame != frame:
		_flat_regions.clear()
		_frame = frame
	var local := _terrain.to_local(origin)
	var extent := Vector3(radius, 0, radius)
	var first := _data.world_to_cell(local - extent) - Vector2i.ONE
	var last := _data.world_to_cell(local + extent) + Vector2i.ONE
	var key := [first, last, local.y]
	if not _flat_regions.has(key): _flat_regions[key] = _same_height(first, last, local.y)
	return _flat_regions[key]

func unclipped_flat(origin: Vector3, radius: float) -> bool:
	if not flat_ground(origin, radius): return false
	if not is_equal_approx(_shape.radius, radius): _shape.radius = radius
	_query.transform = Transform3D(Basis.IDENTITY, origin + Vector3.UP * 0.45)
	return _terrain.get_world_3d().direct_space_state.intersect_shape(_query, 1).is_empty()

func _same_height(first: Vector2i, last: Vector2i, height: float) -> bool:
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, z)
			if not _data.has_cell(cell): return false
			var bridge := _data.has_overlay(cell, TerrainData.OVERLAY_BRIDGE)
			if _data.has_overlay(cell, TerrainData.OVERLAY_WATER) and not bridge: return false
			for corner in _terrain._corner_heights(cell):
				if not is_equal_approx(corner + (_data.layer_height if bridge else 0.0), height): return false
	return true
