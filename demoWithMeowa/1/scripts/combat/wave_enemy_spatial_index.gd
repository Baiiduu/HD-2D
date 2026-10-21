class_name WaveEnemySpatialIndex
extends RefCounted

## 世界 XZ 哈希格。只缩小候选集合，不限制邻居数量；调用方继续做精确距离／高度检查。
const CELL_SIZE := 1.0
const EMPTY_CELL: Array = []

var _cells: Dictionary = {}
var _ordered_cells: Array[Vector2i] = []
var _cell_order_dirty := true
## 稳定整数槽位；移除即撤桶并归还槽位，仍在每次 update 时读取实时参数。
## 只保存与旧记录相同精度的值：Vector3 与 float64，不能把间距／体型降为 float32。
var _entries: Dictionary[WaveEnemy, int] = {}
var _owners: Array[WaveEnemy] = []
var _slot_cells: Array[Vector2i] = []
var _positions := PackedVector3Array()
var _ids := PackedInt64Array()
var _active := PackedByteArray()
var _spacing := PackedFloat64Array()
var _bodies := PackedFloat64Array()
var _free_slots: Array[int] = []
## 本次索引生命周期的保守上界；移除大怪后可偏大，不能漏查新加入的大体型。
var _max_crowd_spacing := 0.0
## Candidate-list validity: position-only commits do not change this revision.
## Birth, removal, activation, body and spacing changes always do.
var _crowd_revision := 0
var candidate_checks := 0
## 地图独立开关；0 保留原频率。只调度普通决策，空间提交／命中查询始终实时。
var pursuit_throttle_threshold := 0:
	set(value):
		value = maxi(0, value)
		if pursuit_throttle_threshold == value: return
		pursuit_throttle_threshold = value
		pursuit_epoch += 1
var pursuit_epoch := 0

func pursuit_is_throttled() -> bool:
	return pursuit_throttle_threshold > 0 and _entries.size() >= pursuit_throttle_threshold

func pursuit_due(enemy: WaveEnemy) -> bool:
	var slot: int = _entries.get(enemy, -1)
	return not pursuit_is_throttled() or slot < 0 or slot % 2 == Engine.get_physics_frames() % 2

func pursuit_separation(enemy: WaveEnemy, radius: float) -> Vector3:
	return separation(enemy, radius)

func _key(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / CELL_SIZE), floori(point.z / CELL_SIZE))

func update(enemy: WaveEnemy) -> void:
	if not is_instance_valid(enemy) or enemy.dead or not enemy.is_inside_tree(): return
	var point := enemy.global_position
	var key := _key(point)
	var slot: int = _entries.get(enemy, -1)
	var registered := slot >= 0
	var body := enemy.get_crowd_body_radius()
	var spacing := maxf(enemy.get_crowd_spacing(), body * 2.1)
	var active := 1 if enemy.spawn_delay <= 0.0 else 0
	if not registered or _bodies[slot] != body or _spacing[slot] != spacing or _active[slot] != active:
		_crowd_revision += 1
	if not registered:
		if _free_slots.is_empty():
			slot = _owners.size()
			_owners.append(enemy)
			_slot_cells.append(key)
			_positions.append(point)
			_ids.append(enemy.get_instance_id())
			_active.append(0)
			_spacing.append(spacing)
			_bodies.append(body)
		else:
			slot = _free_slots.pop_back()
			_owners[slot] = enemy
			_ids[slot] = enemy.get_instance_id()
		_entries[enemy] = slot
	_positions[slot] = point
	_active[slot] = active
	_bodies[slot] = body
	_spacing[slot] = spacing
	_max_crowd_spacing = maxf(_max_crowd_spacing, spacing)
	if registered and _slot_cells[slot] == key: return
	if registered:
		var previous := _slot_cells[slot]
		_cells[previous].erase(slot)
		if _cells[previous].is_empty():
			_cells.erase(previous)
			_cell_order_dirty = true
	if not _cells.has(key):
		_cells[key] = []
		_cell_order_dirty = true
	_cells[key].append(slot)
	_slot_cells[slot] = key

func remove(enemy: WaveEnemy) -> void:
	var slot: int = _entries.get(enemy, -1)
	if slot < 0: return
	var key := _slot_cells[slot]
	_cells[key].erase(slot)
	if _cells[key].is_empty():
		_cells.erase(key)
		_cell_order_dirty = true
	_entries.erase(enemy)
	_owners[slot] = null
	_active[slot] = 0
	_free_slots.append(slot)
	_crowd_revision += 1

func clear() -> void:
	pursuit_epoch += 1
	_cells.clear()
	_ordered_cells.clear()
	_cell_order_dirty = true
	_entries.clear()
	_owners.clear()
	_slot_cells.clear()
	_positions.clear()
	_ids.clear()
	_active.clear()
	_spacing.clear()
	_bodies.clear()
	_free_slots.clear()
	_max_crowd_spacing = 0.0
	_crowd_revision += 1
	candidate_checks = 0

func synchronize(enemies: Array[WaveEnemy]) -> void:
	for enemy in enemies: update(enemy)

## 聚群间距至少覆盖身体直径，可复用其保守上界查找扫掠接触，不扫描整场。
func swept_bodies(start: Vector3, end: Vector3, radius: float) -> Array[WaveEnemy]:
	return nearby((start + end) * 0.5, TerrainPath.horizontal_distance(start, end) * 0.5 + radius + _max_crowd_spacing * 0.5)

## 大范围稀疏查询改查有怪的格子，避免范围成长后遍历整片空桶。
## 排序只跟随占用格变化，保留原 z/x/桶内顺序；不缓存怪物位置。
func _wide_query(first: Vector2i, last: Vector2i) -> bool:
	return (last.x - first.x + 1) * (last.y - first.y + 1) > maxi(64, _cells.size() * 8)

func _ordered_occupied_cells() -> Array[Vector2i]:
	if _cell_order_dirty:
		_ordered_cells.assign(_cells.keys())
		_ordered_cells.sort_custom(_cell_precedes)
		_cell_order_dirty = false
	return _ordered_cells

static func _cell_precedes(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)

func nearby(point: Vector3, radius: float) -> Array[WaveEnemy]:
	var result: Array[WaveEnemy] = []
	if _cells.is_empty(): return result
	var first := _key(point - Vector3(radius, 0.0, radius))
	var last := _key(point + Vector3(radius, 0.0, radius))
	var squared := radius * radius
	if _wide_query(first, last):
		for key in _ordered_occupied_cells():
			if key.y < first.y or key.y > last.y or key.x < first.x or key.x > last.x: continue
			for slot: int in _cells[key]:
				candidate_checks += 1
				var enemy := _owners[slot]
				if not is_instance_valid(enemy) or enemy.dead: continue
				var position := enemy.global_position
				var offset := Vector2(position.x - point.x, position.z - point.z)
				if offset.length_squared() <= squared: result.append(enemy)
		return result
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for slot: int in _cells.get(Vector2i(x, z), EMPTY_CELL):
				candidate_checks += 1
				var enemy := _owners[slot]
				if not is_instance_valid(enemy) or enemy.dead: continue
				var position := enemy.global_position
				var offset := Vector2(position.x - point.x, position.z - point.z)
				if offset.length_squared() <= squared: result.append(enemy)
	return result

## 绕群与怪群遍历复用调用方缓冲；已处理 ID 在读取实时位置、算距离前排除。
## 不缓存位置或挡墙结果，候选顺序及精确距离判定与 nearby 一致。
func nearby_into(point: Vector3, radius: float, excluded: Dictionary[int, bool], result: Array[WaveEnemy]) -> void:
	result.clear()
	if _cells.is_empty(): return
	var first := _key(point - Vector3(radius, 0.0, radius))
	var last := _key(point + Vector3(radius, 0.0, radius))
	var squared := radius * radius
	if _wide_query(first, last):
		for key in _ordered_occupied_cells():
			if key.y < first.y or key.y > last.y or key.x < first.x or key.x > last.x: continue
			for slot: int in _cells[key]:
				candidate_checks += 1
				if excluded.has(_ids[slot]): continue
				var enemy := _owners[slot]
				if not is_instance_valid(enemy) or enemy.dead: continue
				var position := enemy.global_position
				var offset := Vector2(position.x - point.x, position.z - point.z)
				if offset.length_squared() <= squared: result.append(enemy)
		return
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for slot: int in _cells.get(Vector2i(x, z), EMPTY_CELL):
				candidate_checks += 1
				if excluded.has(_ids[slot]): continue
				var enemy := _owners[slot]
				if not is_instance_valid(enemy) or enemy.dead: continue
				var position := enemy.global_position
				var offset := Vector2(position.x - point.x, position.z - point.z)
				if offset.length_squared() <= squared: result.append(enemy)

## 避让直接累计局部候选，避免创建候选数组并重复计算距离。
## 每次实体移动／击退后同步位置，仍逐物理帧处理全部半径内同伴。
func separation(enemy: WaveEnemy, radius: float) -> Vector3:
	if radius <= 0.0: return Vector3.ZERO
	var point := enemy.global_position
	var own_body := enemy.get_crowd_body_radius()
	var own_space := maxf(radius, own_body * 2.1)
	var own_id := enemy.get_instance_id()
	var search := (own_space + _max_crowd_spacing) * 0.5
	var first := _key(point - Vector3(search, 0.0, search))
	var last := _key(point + Vector3(search, 0.0, search))
	var result := Vector3.ZERO
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for slot: int in _cells.get(Vector2i(x, z), EMPTY_CELL):
				candidate_checks += 1
				var other_id := _ids[slot]
				if other_id == own_id or _active[slot] == 0: continue
				var spacing := (own_space + _spacing[slot]) * 0.5
				var other_point := _positions[slot]
				var offset := point - other_point
				if offset.x * offset.x + offset.z * offset.z >= spacing * spacing: continue
				result += crowd_pair_force(offset, spacing, own_body + _bodies[slot], own_id, other_id)
	return result

static func crowd_pair_force(offset: Vector3, spacing: float, contact: float, own_id: int, other_id: int) -> Vector3:
	if absf(offset.y) > maxf(contact, 0.35): return Vector3.ZERO
	offset.y = 0.0
	var distance := offset.length()
	if distance >= spacing: return Vector3.ZERO
	var direction: Vector3
	if distance > 0.00001:
		direction = offset / distance
	else:
		# 完全同点也能解开，成对方向严格相反，不依赖逐帧随机数。
		var seed := mini(own_id, other_id) ^ (maxi(own_id, other_id) << 1)
		var angle := posmod(seed, 4096) * TAU / 4096.0
		direction = Vector3(cos(angle), 0, sin(angle)) * (1.0 if own_id < other_id else -1.0)
	var skin := maxf(spacing * 0.1, 0.02)
	return direction * (spacing - distance) / maxf(distance - contact + skin, skin)
