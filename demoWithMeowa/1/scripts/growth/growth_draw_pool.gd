class_name GrowthDrawPool
extends RefCounted

## A run owns this RNG, independent of enemy spawns. Draw without replacement;
## prefer unseen cards and retain a skill direction whenever one is eligible.
var _random := RandomNumberGenerator.new()

func reset(seed_value := 0) -> void:
	if seed_value == 0: _random.randomize()
	else: _random.seed = seed_value

func valid_pool(options: Array[GrowthChoiceOption]) -> bool:
	var ids := {}
	for option in options:
		if not option or option.id.is_empty() or ids.has(option.id): return false
		ids[option.id] = true
	return true

func can_redraw(pool: Array[GrowthChoiceOption], shown: Array[GrowthChoiceOption]) -> bool:
	var ids := {}
	for option in shown: ids[option.id] = true
	return pool.any(func(option: GrowthChoiceOption): return option.enabled and not ids.has(option.id))

func draw(pool: Array[GrowthChoiceOption], count: int, previous: Array[GrowthChoiceOption] = []) -> Array[GrowthChoiceOption]:
	var remaining: Array[GrowthChoiceOption] = []
	for option in pool:
		if option.enabled: remaining.append(option)
	var avoid := {}
	for option in previous: avoid[option.id] = true
	var result: Array[GrowthChoiceOption] = []
	var skills: Array[GrowthChoiceOption] = []
	for option in remaining:
		if option.category in [GrowthChoiceOption.Category.LEARN_SKILL, GrowthChoiceOption.Category.UPGRADE_SKILL]: skills.append(option)
	if count > 0 and not skills.is_empty():
		var skill := _pick(skills, avoid)
		result.append(skill)
		remaining.erase(skill)
	while result.size() < count and not remaining.is_empty():
		var option := _pick(remaining, avoid)
		result.append(option)
		remaining.erase(option)
	# The reserved skill has no permanent slot or automatic default selection.
	for index in range(result.size() - 1, 0, -1):
		var other := _random.randi_range(0, index)
		var value := result[index]
		result[index] = result[other]
		result[other] = value
	return result

func _pick(options: Array[GrowthChoiceOption], avoid: Dictionary) -> GrowthChoiceOption:
	var fresh: Array[GrowthChoiceOption] = []
	for option in options:
		if not avoid.has(option.id): fresh.append(option)
	var source := fresh if not fresh.is_empty() else options
	return source[_random.randi_range(0, source.size() - 1)]
