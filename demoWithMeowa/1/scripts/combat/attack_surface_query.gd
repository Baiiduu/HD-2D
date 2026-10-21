extends RefCounted

## 一场战斗共用的地面特效查询。缓存仅覆盖当前物理帧的静态地形资格；
## 挡墙碰撞每次实时检查，不缓存障碍结果。
const BLOCK_SIZE := 4
var _terrain: Terrain
var _data: TerrainData
var _frame := -1
var _flat_regions: Dictionary = {}
var _flat_blocks: Dictionary = {}
var _cell_size := 0.0
var _layer_height := 0.0
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
	_flat_blocks.clear()
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
	if _frame != frame or _cell_size != _data.cell_size or _layer_height != _data.layer_height:
		_flat_regions.clear()
		_flat_blocks.clear()
		_frame = frame
		_cell_size = _data.cell_size
		_layer_height = _data.layer_height
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
	if (last.x - first.x + 1) * (last.y - first.y + 1) <= BLOCK_SIZE * BLOCK_SIZE:
		return _same_height_block(first, last, height)
	# 对齐的内部块由同帧的剑光／余迹共用；边缘仍只检查本次覆盖的格子。
	var block_first := Vector2i(floori(float(first.x) / BLOCK_SIZE), floori(float(first.y) / BLOCK_SIZE))
	var block_last := Vector2i(floori(float(last.x) / BLOCK_SIZE), floori(float(last.y) / BLOCK_SIZE))
	for z in range(block_first.y, block_last.y + 1):
		for x in range(block_first.x, block_last.x + 1):
			var start := Vector2i(maxi(first.x, x * BLOCK_SIZE), maxi(first.y, z * BLOCK_SIZE))
			var end := Vector2i(mini(last.x, (x + 1) * BLOCK_SIZE - 1), mini(last.y, (z + 1) * BLOCK_SIZE - 1))
			var key := [start, end, height]
			if not _flat_blocks.has(key): _flat_blocks[key] = _same_height_block(start, end, height)
			if not _flat_blocks[key]: return false
	return true

func _same_height_block(first: Vector2i, last: Vector2i, height: float) -> bool:
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, z)
			if not _data.has_cell(cell): return false
			var bridge := _data.has_overlay(cell, TerrainData.OVERLAY_BRIDGE)
			if _data.has_overlay(cell, TerrainData.OVERLAY_WATER) and not bridge: return false
			for corner in _terrain._corner_heights(cell):
				if not is_equal_approx(corner + (_data.layer_height if bridge else 0.0), height): return false
	return true
