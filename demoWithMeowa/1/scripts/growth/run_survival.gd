class_name RunSurvival
extends RefCounted
## 只读真实伤害事件；基础剑术保留滑动一秒预算，全能吸血仅受缺失生命限制。
var rules: RunGrowthRules
var _clock := 0.0
var _basic: Array[Vector2] = []
var _basic_total := 0.0

func reset() -> void:
	_clock = 0.0
	_basic.clear()
	_basic_total = 0.0

func advance(seconds: float) -> void:
	_clock += maxf(seconds, 0.0)
	_basic_total = maxf(0.0, _basic_total - _expire(_basic))

func _expire(entries: Array[Vector2]) -> float:
	var expired := 0.0
	var count := 0
	while count < entries.size() and entries[count].x <= _clock - 1.0:
		expired += entries[count].y
		count += 1
	if count == entries.size(): entries.clear()
	elif count > 0: entries.assign(entries.slice(count))
	return expired

func basic_used() -> float: return _basic_total

func incoming_damage(amount: float, orbiting: bool) -> float:
	return amount * (1.0 - rules.orbit_damage_reduction) if rules and orbiting else amount

func recovery(event: CombatDamageEvent, modifiers: RunCombatModifiers, maximum: float, missing: float) -> float:
	if not rules or event.simulated or not is_finite(event.amount) or event.amount <= 0.0: return 0.0
	var basic := 0.0
	var attack := event.attack_snapshot
	if event.source in [&"basic_sword", &"flight_sword"] and attack and not attack.sword_heal_claimed:
		attack.sword_heal_claimed = true
		basic = minf(maxf(missing, 0.0), minf(maximum * rules.sword_heal_fraction, maxf(0.0, maximum * rules.sword_heal_cap - basic_used())))
		if basic > 0.0:
			_basic.append(Vector2(_clock, basic))
			_basic_total += basic
	var vamp := minf(maxf(missing - basic, 0.0), event.amount * modifiers.bonus(GrowthBuffEffect.Attribute.LIFESTEAL))
	return basic + vamp
