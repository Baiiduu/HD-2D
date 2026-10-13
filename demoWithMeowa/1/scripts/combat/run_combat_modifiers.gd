class_name RunCombatModifiers
extends Resource

## 一局唯一的进攻属性状态；不改写武器基础参数、装备或训练存档。
var levels: Dictionary[StringName, int] = {}
var _bonuses: Dictionary[int, float] = {}

func reset() -> void:
	levels.clear()
	_bonuses.clear()
	emit_changed()

func level_for(id: StringName) -> int:
	return levels.get(id, 0)

func bonus(attribute: GrowthBuffDefinition.Attribute) -> float:
	return _bonuses.get(attribute, 0.0)

func can_apply(definition: GrowthBuffDefinition) -> bool:
	return definition != null and definition.enabled and not definition.id.is_empty() and level_for(definition.id) < definition.max_level and definition.available_gain(bonus(definition.attribute)) > 0.00001

func apply_buff(definition: GrowthBuffDefinition) -> bool:
	if not can_apply(definition): return false
	_bonuses[definition.attribute] = bonus(definition.attribute) + definition.available_gain(bonus(definition.attribute))
	levels[definition.id] = level_for(definition.id) + 1
	emit_changed()
	return true

func preview_after(definition: GrowthBuffDefinition) -> RunCombatModifiers:
	var preview := RunCombatModifiers.new()
	preview.levels = levels.duplicate()
	preview._bonuses = _bonuses.duplicate()
	preview.apply_buff(definition)
	return preview

func damage_multiplier() -> float:
	return 1.0 + bonus(GrowthBuffDefinition.Attribute.DAMAGE)

func interval_multiplier() -> float:
	return 1.0 - bonus(GrowthBuffDefinition.Attribute.COOLDOWN)

func range_multiplier() -> float:
	return 1.0 + bonus(GrowthBuffDefinition.Attribute.RANGE)
