class_name WaveSchedulePlanner
extends RefCounted
## 波次资源的纯计算：不访问场景树、怪物实例、导航、UI 或会话状态。

static func total(definition: WaveDefinition) -> int:
	var count := 0
	for entry in definition.entries: count += entry.count
	return count

static func endless_total(initial: int, opening_waves: int, number: int, growth: int, cap: int) -> int:
	# 有界步数避免极端波号的乘法溢出，与运行期容量限制独立。
	var steps := mini(maxi(number - opening_waves, 0), cap)
	return mini(initial + steps * growth, cap)

static func extend_wave(template: WaveDefinition, count: int, interval_scale: float, minimum_interval: float, batch_limit: Callable) -> WaveDefinition:
	var base_total := total(template)
	var definition := WaveDefinition.new()
	definition.description = "%d 只 · 末波分区与增援节奏" % count
	var cumulative := 0
	var allocated := 0
	for index in template.entries.size():
		var entry := template.entries[index]
		var copy := entry.duplicate() as WaveSpawnEntry
		copy.spawn_zone_ids = entry.spawn_zone_ids.duplicate()
		cumulative += entry.count
		var next_allocation := roundi(float(cumulative) * count / base_total)
		copy.count = next_allocation - allocated
		allocated = next_allocation
		if entry.batch_size > 1:
			copy.batch_size = mini(int(batch_limit.call(entry)), ceili(float(entry.batch_size) * copy.count / entry.count))
		# 已短于下限的间隔保持原值，增长不会意外减慢出怪。
		copy.interval = minf(entry.interval, maxf(minimum_interval, entry.interval * interval_scale))
		if index > 0:
			var previous := template.entries[index - 1]
			var gap := entry.start_delay - previous.start_delay - previous.spawn_duration()
			if gap >= 0.0:
				var previous_copy := definition.entries[index - 1]
				copy.start_delay = previous_copy.start_delay + previous_copy.spawn_duration() + gap
		definition.entries.append(copy)
	return definition
