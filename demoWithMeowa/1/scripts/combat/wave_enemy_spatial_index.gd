class_name WaveEnemySpatialIndex
extends RefCounted

## 世界 XZ 哈希格。只缩小候选集合，不限制邻居数量；调用方继续做精确距离／高度检查。
const CELL_SIZE := 1.0
var _cells: Dictionary = {}
var _membership: Dictionary = {}
var _positions: Dictionary = {}
var _active: Dictionary = {}
var candidate_checks := 0

func _key(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / CELL_SIZE), floori(point.z / CELL_SIZE))

func update(enemy: WaveEnemy) -> void:
	if not is_instance_valid(enemy) or enemy.dead or not enemy.is_inside_tree(): return
	var point := enemy.global_position
	var key := _key(point)
	_positions[enemy] = point
	_active[enemy] = enemy.spawn_delay <= 0.0
	if _membership.get(enemy, Vector2i(2147483647, 2147483647)) == key: return
	if _membership.has(enemy):
		var previous: Vector2i = _membership[enemy]
		_cells[previous].erase(enemy)
		if _cells[previous].is_empty(): _cells.erase(previous)
	if not _cells.has(key): _cells[key] = []
	_cells[key].append(enemy)
	_membership[enemy] = key

func remove(enemy: WaveEnemy) -> void:
	if not _membership.has(enemy): return
	var key: Vector2i = _membership[enemy]
	_cells[key].erase(enemy)
	if _cells[key].is_empty(): _cells.erase(key)
	_membership.erase(enemy)
	_positions.erase(enemy)
	_active.erase(enemy)

func clear() -> void:
	_cells.clear()
	_membership.clear()
	_positions.clear()
	_active.clear()
	candidate_checks = 0

func synchronize(enemies: Array[WaveEnemy]) -> void:
	for enemy in enemies: update(enemy)

func nearby(point: Vector3, radius: float) -> Array[WaveEnemy]:
	var result: Array[WaveEnemy] = []
	var first := _key(point - Vector3(radius, 0.0, radius))
	var last := _key(point + Vector3(radius, 0.0, radius))
	var squared := radius * radius
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for enemy: WaveEnemy in _cells.get(Vector2i(x, z), []):
				candidate_checks += 1
				if not is_instance_valid(enemy) or enemy.dead: continue
				var offset := Vector2(enemy.global_position.x - point.x, enemy.global_position.z - point.z)
				if offset.length_squared() <= squared: result.append(enemy)
	return result

## 避让直接累计局部候选，避免创建候选数组并重复计算距离。
## 每次实体移动／击退后同步位置，仍逐物理帧处理全部半径内同伴。
func separation(enemy: WaveEnemy, radius: float) -> Vector3:
	var point := enemy.global_position
	var first := _key(point - Vector3(radius, 0.0, radius))
	var last := _key(point + Vector3(radius, 0.0, radius))
	var squared := radius * radius
	var result := Vector3.ZERO
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for other: WaveEnemy in _cells.get(Vector2i(x, z), []):
				candidate_checks += 1
				if other == enemy or not _active.get(other, false): continue
				var other_point: Vector3 = _positions[other]
				var offset := Vector3(point.x - other_point.x, 0.0, point.z - other_point.z)
				var length_squared := offset.length_squared()
				if length_squared > 0.0001 and length_squared < squared:
					result += offset * (radius / sqrt(length_squared) - 1.0)
	return result
