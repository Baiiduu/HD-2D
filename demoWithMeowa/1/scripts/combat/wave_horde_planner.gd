class_name WaveHordePlanner
extends RefCounted

## 只编排类型，不访问地图。先覆盖本批尚未出现的类型，再按权重补齐；
## usage 跨批保留，批次小于目录种类数时也不会永远只选目录前几种。
static func plan(pool: Array[WaveEnemyDefinition], count: int, active_limit: int, cost_limit: int, role_limits: PackedInt32Array, usage: Dictionary) -> Array[WaveEnemyDefinition]:
	var result: Array[WaveEnemyDefinition] = []
	var kinds := {}
	var roles := PackedInt32Array([0, 0, 0, 0])
	var cost := 0
	var total_weight := 0.0
	var total_used := 0
	for enemy in pool:
		total_weight += enemy.horde_weight
		total_used += int(usage.get(enemy, 0))
	if total_weight <= 0.0: return result
	for index in mini(count, active_limit):
		var candidates: Array[WaveEnemyDefinition] = []
		var uncovered: Array[WaveEnemyDefinition] = []
		for enemy in pool:
			if enemy.horde_weight <= 0.0 or cost + enemy.population_cost > cost_limit: continue
			if roles[enemy.role] >= role_limits[enemy.role]: continue
			if enemy.max_alive > 0 and int(kinds.get(enemy, 0)) >= enemy.max_alive: continue
			candidates.append(enemy)
			if not kinds.has(enemy): uncovered.append(enemy)
		if candidates.is_empty(): break
		if not uncovered.is_empty(): candidates = uncovered
		var selected: WaveEnemyDefinition = candidates[0]
		var best := -INF
		for enemy in candidates:
			var score := (total_used + 1) * enemy.horde_weight / total_weight - int(usage.get(enemy, 0))
			if score > best:
				selected = enemy
				best = score
		result.append(selected)
		kinds[selected] = int(kinds.get(selected, 0)) + 1
		roles[selected.role] += 1
		cost += selected.population_cost
		usage[selected] = int(usage.get(selected, 0)) + 1
		total_used += 1
	return result
