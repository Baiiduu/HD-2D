class_name GrowthDrawPool
extends RefCounted

## 独立于刷怪的局内抽牌。技能、弹射各留一个有效候选，其余随机。
## 跟进只在确认一次升级时计数；开局抽牌与重抽不推进计数。
var _random := RandomNumberGenerator.new()
var _preferred_ricochet: StringName = &""
var _followup_misses := 0

func reset(seed_value := 0) -> void:
	clear_followup()
	if seed_value == 0: _random.randomize()
	else: _random.seed = seed_value

func clear_followup() -> void:
	_preferred_ricochet = &""
	_followup_misses = 0

func record_choice(id: StringName, shown: Array[GrowthChoiceOption]) -> void:
	var chosen: GrowthChoiceOption
	for option in shown:
		if option.id == id and option.enabled: chosen = option; break
	if not chosen: return
	if chosen.ricochet_growth:
		_preferred_ricochet = chosen.id
		_followup_misses = 0
	elif not _preferred_ricochet.is_empty():
		_followup_misses = 0 if shown.any(func(option: GrowthChoiceOption): return option.id == _preferred_ricochet and option.enabled) else _followup_misses + 1

func valid_pool(options: Array[GrowthChoiceOption]) -> bool:
	var ids := {}
	for option in options:
		if not option or option.id.is_empty() or ids.has(option.id): return false
		ids[option.id] = true
	return true

func can_redraw(pool: Array[GrowthChoiceOption], shown: Array[GrowthChoiceOption]) -> bool:
	var ids := {}
	for option in shown: ids[option.id] = true
	var remaining := _available(pool)
	var eligible: Array[GrowthChoiceOption] = []
	var slots := shown.size()
	var skills: Array[GrowthChoiceOption] = remaining.filter(_is_skill)
	if slots > 0 and not skills.is_empty():
		eligible.append_array(skills)
		slots -= 1
	var ricochets: Array[GrowthChoiceOption] = remaining.filter(func(option: GrowthChoiceOption): return option.ricochet_growth and not _is_skill(option))
	if slots > 0 and not ricochets.is_empty():
		var preferred := _followup(ricochets)
		if preferred: eligible.append(preferred)
		else: eligible.append_array(ricochets)
		slots -= 1
	if slots > 0: eligible = remaining
	return eligible.any(func(option: GrowthChoiceOption): return not ids.has(option.id))

func draw(pool: Array[GrowthChoiceOption], count: int, previous: Array[GrowthChoiceOption] = []) -> Array[GrowthChoiceOption]:
	var remaining := _available(pool)
	var avoid := {}
	for option in previous: avoid[option.id] = true
	var result: Array[GrowthChoiceOption] = []
	var skills: Array[GrowthChoiceOption] = remaining.filter(_is_skill)
	if count > 0 and not skills.is_empty():
		var skill := _pick(skills, avoid)
		result.append(skill)
		remaining.erase(skill)
	var ricochets: Array[GrowthChoiceOption] = remaining.filter(func(option: GrowthChoiceOption): return option.ricochet_growth and not _is_skill(option))
	if result.size() < count and not ricochets.is_empty():
		var preferred := _followup(ricochets)
		var ricochet := preferred if preferred else _pick(ricochets, avoid)
		result.append(ricochet)
		remaining.erase(ricochet)
	while result.size() < count and not remaining.is_empty():
		var option := _pick(remaining, avoid)
		result.append(option)
		remaining.erase(option)
	# 分组只决定候选组成，展示位置随机，也不默认选中。
	for index in range(result.size() - 1, 0, -1):
		var other := _random.randi_range(0, index)
		var value := result[index]
		result[index] = result[other]
		result[other] = value
	return result

func _available(pool: Array[GrowthChoiceOption]) -> Array[GrowthChoiceOption]:
	return pool.filter(func(option: GrowthChoiceOption): return option != null and option.enabled)

func _is_skill(option: GrowthChoiceOption) -> bool:
	return option.category in [GrowthChoiceOption.Category.LEARN_SKILL, GrowthChoiceOption.Category.UPGRADE_SKILL]

func _followup(options: Array[GrowthChoiceOption]) -> GrowthChoiceOption:
	if _followup_misses < 2 or _preferred_ricochet.is_empty(): return null
	for option in options:
		if option.id == _preferred_ricochet: return option
	return null

func _pick(options: Array[GrowthChoiceOption], avoid: Dictionary) -> GrowthChoiceOption:
	var fresh: Array[GrowthChoiceOption] = []
	for option in options:
		if not avoid.has(option.id): fresh.append(option)
	var source := fresh if not fresh.is_empty() else options
	return source[_random.randi_range(0, source.size() - 1)]
