class_name WaveEnemyRoster
extends RefCounted
## 存活对象与容量统一登记；死亡、移除和整局清理均只能释放一次。
var enemies: Array[WaveEnemy] = []
var by_definition: Dictionary = {}
var by_role := PackedInt32Array([0, 0, 0, 0])
var cost := 0
var spatial_index: WaveEnemySpatialIndex = WaveEnemySpatialIndex.new()
var _registered: Dictionary[WaveEnemy, Dictionary] = {}

func register(enemy: WaveEnemy) -> bool:
	if _registered.has(enemy): return false
	var definition := enemy.definition
	if enemy not in enemies: enemies.append(enemy)
	_registered[enemy] = {"definition": definition, "role": definition.role, "cost": definition.population_cost}
	by_definition[definition] = int(by_definition.get(definition, 0)) + 1
	by_role[definition.role] += 1
	cost += definition.population_cost
	return true

func remove(enemy: WaveEnemy) -> bool:
	if enemy not in enemies: return false
	enemies.erase(enemy)
	if _registered.has(enemy):
		var entry := _registered[enemy]
		by_definition[entry.definition] -= 1
		by_role[entry.role] -= 1
		cost -= int(entry.cost)
		_registered.erase(enemy)
	spatial_index.remove(enemy)
	return true

func take_all() -> Array[WaveEnemy]:
	var remaining := enemies.duplicate()
	enemies.clear()
	_registered.clear()
	by_definition.clear()
	by_role.fill(0)
	cost = 0
	spatial_index.clear()
	return remaining

func can_fit(definition: WaveEnemyDefinition, count: int, active_limit: int, population: WavePopulationRules, reserved: Dictionary, batch: Dictionary = {}) -> bool:
	var slots := 0
	var reserved_cost := 0
	var reserved_role := 0
	var reserved_kind := 0
	if not reserved.is_empty() and reserved.id != batch.get("id", -1):
		slots = reserved.remaining
		reserved_cost = reserved.cost
		reserved_role = reserved.roles[definition.role]
		reserved_kind = int(reserved.counts.get(definition, 0))
	if enemies.size() + slots + count > active_limit: return false
	if definition.max_alive > 0 and int(by_definition.get(definition, 0)) + reserved_kind + count > definition.max_alive: return false
	if population:
		if cost + reserved_cost + count * definition.population_cost > population.max_population_cost: return false
		if by_role[definition.role] + reserved_role + count > population.role_limits[definition.role]: return false
	return true

func can_fit_batch(batch: Dictionary, active_limit: int, population: WavePopulationRules) -> bool:
	if enemies.size() + int(batch.remaining) > active_limit: return false
	for definition: WaveEnemyDefinition in batch.counts:
		if definition.max_alive > 0 and int(by_definition.get(definition, 0)) + int(batch.counts[definition]) > definition.max_alive: return false
	if population:
		if cost + int(batch.cost) > population.max_population_cost: return false
		for role in 4:
			if by_role[role] + int(batch.roles[role]) > population.role_limits[role]: return false
	return true
