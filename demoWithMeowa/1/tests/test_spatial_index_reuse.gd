extends SceneTree

## Frozen Array-record oracle: compare exact forces and candidate order through sequential mutations.
class LegacyIndex extends RefCounted:

	## 世界 XZ 哈希格。只缩小候选集合，不限制邻居数量；调用方继续做精确距离／高度检查。
	const CELL_SIZE := 1.0
	const EMPTY_CELL: Array = []

	enum Field { ENEMY, ID, CELL, POSITION, ACTIVE, SPACING, BODY }

	var _cells: Dictionary = {}
	## 每只怪物一个记录；仍在每次 update 时读取位置、预告与可调体型，不跨更新缓存参数。
	var _entries: Dictionary[WaveEnemy, Array] = {}
	## 本次索引生命周期的保守上界；移除大怪后可偏大，不能漏查新加入的大体型。
	var _max_crowd_spacing := 0.0
	var candidate_checks := 0

	func _key(point: Vector3) -> Vector2i:
		return Vector2i(floori(point.x / CELL_SIZE), floori(point.z / CELL_SIZE))

	func update(enemy: WaveEnemy) -> void:
		if not is_instance_valid(enemy) or enemy.dead or not enemy.is_inside_tree(): return
		var point := enemy.global_position
		var key := _key(point)
		var entry: Array = _entries.get(enemy, EMPTY_CELL)
		var registered := not entry.is_empty()
		var body := enemy.get_crowd_body_radius()
		var spacing := maxf(enemy.get_crowd_spacing(), body * 2.1)
		if not registered:
			# Array 不分配 ObjectID，保留后续怪物用于同点拆分与稳定绕行的原有 ID。
			entry = [enemy, enemy.get_instance_id(), key, point, enemy.spawn_delay <= 0.0, spacing, body]
			_entries[enemy] = entry
		else:
			entry[Field.POSITION] = point
			entry[Field.ACTIVE] = enemy.spawn_delay <= 0.0
			entry[Field.BODY] = body
			entry[Field.SPACING] = spacing
		_max_crowd_spacing = maxf(_max_crowd_spacing, spacing)
		if registered and entry[Field.CELL] == key: return
		if registered:
			var previous: Vector2i = entry[Field.CELL]
			_cells[previous].erase(entry)
			if _cells[previous].is_empty(): _cells.erase(previous)
		if not _cells.has(key): _cells[key] = []
		_cells[key].append(entry)
		entry[Field.CELL] = key

	func remove(enemy: WaveEnemy) -> void:
		var entry: Array = _entries.get(enemy, EMPTY_CELL)
		if entry.is_empty(): return
		var key: Vector2i = entry[Field.CELL]
		_cells[key].erase(entry)
		if _cells[key].is_empty(): _cells.erase(key)
		_entries.erase(enemy)

	func clear() -> void:
		_cells.clear()
		_entries.clear()
		_max_crowd_spacing = 0.0
		candidate_checks = 0

	func synchronize(enemies: Array[WaveEnemy]) -> void:
		for enemy in enemies: update(enemy)

	## 聚群间距至少覆盖身体直径，可复用其保守上界查找扫掠接触，不扫描整场。
	func swept_bodies(start: Vector3, end: Vector3, radius: float) -> Array[WaveEnemy]:
		return nearby((start + end) * 0.5, TerrainPath.horizontal_distance(start, end) * 0.5 + radius + _max_crowd_spacing * 0.5)

	func nearby(point: Vector3, radius: float) -> Array[WaveEnemy]:
		var result: Array[WaveEnemy] = []
		var first := _key(point - Vector3(radius, 0.0, radius))
		var last := _key(point + Vector3(radius, 0.0, radius))
		var squared := radius * radius
		for z in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				for entry: Array in _cells.get(Vector2i(x, z), EMPTY_CELL):
					candidate_checks += 1
					var enemy: WaveEnemy = entry[Field.ENEMY]
					if not is_instance_valid(enemy) or enemy.dead: continue
					var position := enemy.global_position
					var offset := Vector2(position.x - point.x, position.z - point.z)
					if offset.length_squared() <= squared: result.append(enemy)
		return result

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
				for entry: Array in _cells.get(Vector2i(x, z), EMPTY_CELL):
					candidate_checks += 1
					var other_id: int = entry[Field.ID]
					if other_id == own_id or not entry[Field.ACTIVE]: continue
					var spacing := (own_space + float(entry[Field.SPACING])) * 0.5
					var other_point: Vector3 = entry[Field.POSITION]
					var offset := point - other_point
					if offset.x * offset.x + offset.z * offset.z >= spacing * spacing: continue
					result += crowd_pair_force(offset, spacing, own_body + float(entry[Field.BODY]), own_id, other_id)
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

class ProbeEnemy extends WaveEnemy:
	var spacing := 0.7
	var body := 0.25
	var body_reads := 0
	var spacing_reads := 0

	func get_crowd_spacing() -> float:
		spacing_reads += 1
		return spacing

	func get_crowd_body_radius() -> float:
		body_reads += 1
		return body

var checks := 0
var failures := 0
var actual := WaveEnemySpatialIndex.new()
var legacy := LegacyIndex.new()
var enemies: Array[ProbeEnemy] = []
var world: Node3D

func _initialize() -> void:
	create_timer(25.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func update(enemy: ProbeEnemy) -> void:
	actual.update(enemy)
	legacy.update(enemy)

func compare_forces(label: String) -> void:
	for enemy in enemies:
		for radius in [0.0, 0.2, 0.7, 1.3, 3.1]:
			var before_actual := actual.candidate_checks
			var before_legacy: int = legacy.candidate_checks
			check(actual.separation(enemy, radius) == legacy.separation(enemy, radius), label + ": exact force")
			check(actual.candidate_checks - before_actual <= legacy.candidate_checks - before_legacy, label + ": no extra candidates")
	for point in [Vector3.ZERO, Vector3(-0.5, 0, -0.5), Vector3(1.001, 0, 0.999)]:
		for radius in [0.0, 0.6, 2.4]:
			check(actual.nearby(point, radius) == legacy.nearby(point, radius), label + ": nearby order")
			check(actual.swept_bodies(point, point + Vector3(1.2, 0, -0.8), radius) == legacy.swept_bodies(point, point + Vector3(1.2, 0, -0.8), radius), label + ": swept bodies order")

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	var detached := ProbeEnemy.new()
	actual.update(detached)
	check(actual.nearby(Vector3.ZERO, 5.0).is_empty(), "Detached enemies are not registered")
	detached.free()
	for number in 32:
		var enemy := ProbeEnemy.new()
		enemy.position = Vector3((number % 8 - 3.5) * 0.31, 1.3 if number % 13 == 0 else 0.02, (number / 8 - 1.5) * 0.39)
		enemy.spacing = [0.0, 0.3, 0.7, 1.4, 2.5][number % 5]
		enemy.body = [0.12, 0.25, 0.55, 0.9][number % 4]
		enemy.spawn_delay = 1.0 if number % 7 == 0 else 0.0
		world.add_child(enemy)
		enemy.set_physics_process(false)
		enemies.append(enemy)
		update(enemy)
	compare_forces("Mixed bodies, negative cells and spawn warnings")
	var first := enemies[0]
	first.body_reads = 0
	first.spacing_reads = 0
	actual.update(first)
	check(first.body_reads == 1 and first.spacing_reads == 1, "Update reads adjustable body and spacing once")
	legacy.update(first)
	first.body_reads = 0
	actual.separation(first, 0.7)
	check(first.body_reads == 1, "Separation reads current own body once")
	# Updates retain per-cell insertion order, including leaving and reentering a cell.
	for number in enemies.size():
		var enemy := enemies[number]
		enemy.position += Vector3(-0.43 if number % 2 else 1.17, 0, 0.37)
		update(enemy)
		if number % 8 == 0: compare_forces("Sequential partial moves")
	first.position = Vector3.ZERO
	update(first)
	first.position = Vector3(3, 0, 3)
	update(first)
	first.position = Vector3.ZERO
	update(first)
	compare_forces("Cell reentry")
	# Parameters and spawn eligibility become visible at exactly the original update point.
	for number in enemies.size():
		var enemy := enemies[number]
		enemy.body = 0.1 + number * 0.035
		enemy.spacing = 0.15 + (number % 6) * 0.45
		enemy.spawn_delay = 0.0 if enemy.spawn_delay > 0.0 else 1.0
	compare_forces("Pending parameter edits")
	for enemy in enemies: update(enemy)
	compare_forces("Updated body, spacing and spawn eligibility")
	# Radius supplied by the caller is live even if its own record was not updated yet.
	first.body = 1.7
	for radius in [0.1, 0.7, 3.0]:
		check(actual.separation(first, radius) == legacy.separation(first, radius), "Live own body and caller radius")
	update(first)
	# Nearby intentionally reads current positions while cell membership changes only on update.
	enemies[1].position += Vector3(0.02, 0, 0.01)
	compare_forces("Live nearby positions before movement synchronization")
	update(enemies[1])
	var removed: ProbeEnemy = enemies.pop_back()
	actual.remove(removed)
	legacy.remove(removed)
	actual.remove(removed)
	legacy.remove(removed)
	removed.free()
	compare_forces("Removal, freed target and repeated removal")
	var capacity := actual._owners.size()
	var replacement := ProbeEnemy.new()
	replacement.position = Vector3(0.3, 0.02, -0.2)
	replacement.spawn_delay = 0.0
	world.add_child(replacement)
	replacement.set_physics_process(false)
	enemies.append(replacement)
	update(replacement)
	check(actual._owners.size() == capacity, "A removed slot is reused without growing storage")
	compare_forces("Reused slot has the new owner, ID, position and parameters")
	actual.remove(first)
	legacy.remove(first)
	first.spawn_delay = 0.0
	update(first)
	compare_forces("Removing and readding the same owner appends in original bucket order")
	actual.clear()
	legacy.clear()
	check(actual.candidate_checks == 0 and actual.nearby(Vector3.ZERO, 5.0).is_empty(), "Clear resets cells and diagnostics")
	for enemy in enemies: enemy.free()
	enemies.clear()
	# Zero-distance pair uses the same IDs and deterministic opposite directions.
	for number in 2:
		var enemy := ProbeEnemy.new()
		enemy.spawn_delay = 0.0
		world.add_child(enemy)
		enemy.set_physics_process(false)
		enemies.append(enemy)
		update(enemy)
	compare_forces("Coincident pair")
	var left := actual.separation(enemies[0], 0.7)
	var right := actual.separation(enemies[1], 0.7)
	check(left.is_finite() and left.length() > 0.0 and left == -right, "Coincident pair separates with exact opposite forces")
	# Values on either side of a float32 rounding boundary must keep their original float64 eligibility.
	var near := enemies[0]
	var far := enemies[1]
	near.position = Vector3.ZERO
	near.body = 0.12
	near.spacing = 0.5
	far.position = Vector3.RIGHT
	far.body = 0.12
	far.spacing = 1.500000002
	update(near)
	update(far)
	var precise := actual.separation(near, 0.5)
	check(precise == legacy.separation(near, 0.5) and precise.length() > 0.0, "Float64 spacing keeps a neighbour just inside its true radius")
	near.body = 0.1249999999
	near.spacing = 0.8
	far.body = 0.25
	far.spacing = 0.8
	far.position = Vector3(0.2, 0.375, 0.0)
	update(near)
	update(far)
	check(actual.separation(far, 0.8) == legacy.separation(far, 0.8) and actual.separation(far, 0.8) == Vector3.ZERO, "Float64 body radius preserves the vertical contact boundary")
	actual.clear()
	legacy.clear()
	for enemy in enemies: enemy.free()
	enemies.clear()
	world.free()
	print("Spatial index reuse: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
