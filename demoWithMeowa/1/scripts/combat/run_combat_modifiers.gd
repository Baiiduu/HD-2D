class_name RunCombatModifiers
extends Resource

## 一局唯一的战斗属性状态；不改写武器、弹射基础参数、装备或训练存档。
var levels: Dictionary[StringName, int] = {}
var _bonuses: Dictionary[int, float] = {}
## 巨量怪潮模拟只关闭怪物扣血；基础剑术、技能和成长仍计算真实攻击数值。
var damage_disabled := false
var growth_rules: RunGrowthRules

func reset() -> void:
	damage_disabled = false
	levels.clear()
	_bonuses.clear()
	emit_changed()

func level_for(id: StringName) -> int:
	return levels.get(id, 0)

func bonus(attribute: GrowthBuffDefinition.Attribute) -> float:
	return _bonuses.get(attribute, 0.0)

func can_apply(definition: GrowthBuffDefinition) -> bool:
	if not definition or not definition.enabled or definition.id.is_empty(): return false
	if definition.max_level > 0 and level_for(definition.id) >= definition.max_level: return false
	for id in definition.required_levels:
		if level_for(id) < definition.required_levels[id]: return false
	return gains_for(definition).values().any(func(value: float): return value > 0.00001)

func gains_for(definition: GrowthBuffDefinition) -> Dictionary[int, float]:
	var gains: Dictionary[int, float] = {}
	var level := level_for(definition.id)
	var gain := definition.available_gain(bonus(definition.attribute), level)
	if absf(gain) > 0.00001: gains[definition.attribute] = gain
	for effect in definition.extra_effects:
		if not effect: continue
		gain = effect.available_gain(bonus(effect.attribute) + gains.get(effect.attribute, 0.0), definition.gain_scale(level, effect.attribute))
		if absf(gain) > 0.00001: gains[effect.attribute] = gains.get(effect.attribute, 0.0) + gain
	return gains

func apply_buff(definition: GrowthBuffDefinition) -> bool:
	if not can_apply(definition): return false
	var gains := gains_for(definition)
	for attribute in gains:
		_bonuses[attribute] = bonus(attribute) + gains[attribute]
	levels[definition.id] = level_for(definition.id) + 1
	emit_changed()
	return true

func preview_after(definition: GrowthBuffDefinition) -> RunCombatModifiers:
	var preview := RunCombatModifiers.new()
	preview.levels = levels.duplicate()
	preview._bonuses = _bonuses.duplicate()
	preview.damage_disabled = damage_disabled
	preview.growth_rules = growth_rules
	preview.apply_buff(definition)
	return preview

func damage_multiplier() -> float:
	return multiplier(GrowthBuffDefinition.Attribute.DAMAGE) * multiplier(GrowthBuffDefinition.Attribute.HEAVY_STRIKE)

func interval_multiplier() -> float:
	var heavy := growth_rules.heavy_interval_multiplier if growth_rules and bonus(GrowthBuffDefinition.Attribute.HEAVY_STRIKE) > 0.0 else 1.0
	return heavy * maxf(0.01, 1.0 - bonus(GrowthBuffDefinition.Attribute.COOLDOWN)) / multiplier(GrowthBuffDefinition.Attribute.ATTACK_SPEED)

func speed_damage_multiplier(speed: float, flying: bool) -> float:
	return 1.0 + bonus(GrowthBuffDefinition.Attribute.SPEED_DAMAGE) * growth_rules.speed_damage_bonus(speed) if flying and growth_rules else 1.0

func strike_count(speed_tier: int, flying: bool) -> int:
	var rank := roundi(bonus(GrowthBuffDefinition.Attribute.MULTISTRIKE))
	return mini(growth_rules.maximum_strikes, 1 + rank + maxi(speed_tier, 0)) if flying and growth_rules and rank > 0 else 1

func range_multiplier() -> float:
	return multiplier(GrowthBuffDefinition.Attribute.RANGE)

func multiplier(attribute: GrowthBuffDefinition.Attribute) -> float:
	return maxf(0.1, 1.0 + bonus(attribute))

## 蓄力、收尾与发射冷却以效率相除，避免叠到零；不加速动作动画。
func ricochet_value(attribute: GrowthBuffDefinition.Attribute, base: float) -> float:
	var gain := bonus(attribute)
	var momentum := multiplier(GrowthBuffDefinition.Attribute.MOMENTUM_EFFICIENCY)
	match attribute:
		GrowthBuffDefinition.Attribute.RICOCHET_DURATION, GrowthBuffDefinition.Attribute.RICOCHET_BOUNCES:
			return base / multiplier(attribute) / momentum
		GrowthBuffDefinition.Attribute.RICOCHET_RETENTION:
			# 统一缩减损失，有限正收益不会把基础损失直接加成零。
			return clampf(1.0 - (1.0 - clampf(base + gain, 0.05, 1.0)) / momentum, 0.05, 1.0)
		GrowthBuffDefinition.Attribute.CHARGE_EFFICIENCY, GrowthBuffDefinition.Attribute.RECOVERY_EFFICIENCY, GrowthBuffDefinition.Attribute.RICOCHET_COOLDOWN_EFFICIENCY:
			return base / multiplier(attribute)
	return base * multiplier(attribute)
