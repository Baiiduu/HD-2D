class_name RunBuffs
extends Node

const A := GrowthBuffDefinition.Attribute
const CARD_TEXT := preload("res://scripts/ui/growth_choice_text.gd")
const LABELS := {
	A.DAMAGE: "伤害", A.COOLDOWN: "间隔减幅", A.RANGE: "攻击范围", A.ATTACK_SPEED: "攻速",
	A.RICOCHET_SPEED: "弹射初速", A.RICOCHET_DURATION: "飞行耗速", A.RICOCHET_BOUNCES: "碰撞耗速",
	A.RICOCHET_RETENTION: "最低保速", A.CHARGE_EFFICIENCY: "蓄满", A.RECOVERY_EFFICIENCY: "收势",
	A.RICOCHET_COOLDOWN_EFFICIENCY: "发射间隔", A.PUSH_RADIUS: "拨怪范围", A.PUSH_FORCE: "推力",
	A.PUSH_DURATION: "推力持续", A.PUSH_STUN: "眩晕", A.MOVE_SPEED: "移动", A.PICKUP_RADIUS: "吸取范围",
	A.MOMENTUM_EFFICIENCY: "速度损耗",
	A.SPEED_DAMAGE: "动能增伤", A.MULTISTRIKE: "每次挥剑", A.HEAVY_STRIKE: "伤害",
	A.LIFESTEAL: "吸血比例",
	A.KILL_HASTE: "每层加速",
}

@export_group("本局增益")
@export var session: Node3D
## 地图独立登记各品阶增益；0 级上限表示持续成长。
@export var definitions: Array[GrowthBuffDefinition] = []

var _offered: Dictionary[StringName, GrowthBuffDefinition] = {}

func _ready() -> void:
	(session.get_node("RunGrowth") as RunGrowth).growth_chosen.connect(_choose)
	session.run_started.connect(_clear_offered)
	session.run_ended.connect(func(_reason: String): _clear_offered())

func _clear_offered() -> void:
	_offered.clear()

func _attribute_changed(attribute: A, preview: RunCombatModifiers) -> bool:
	if attribute == A.LIFESTEAL_CAP: return false
	if attribute in [A.SPEED_DAMAGE, A.MULTISTRIKE, A.HEAVY_STRIKE, A.LIFESTEAL, A.KILL_HASTE]:
		if not session.combat_modifiers.growth_rules: return false
		var current: RunCombatModifiers = session.combat_modifiers
		var rules := current.growth_rules
		if attribute in [A.SPEED_DAMAGE, A.MULTISTRIKE]:
			if not is_instance_valid(session.player) or not session.player.body_ricochet or not session.player.body_ricochet.enabled: return false
			if attribute == A.MULTISTRIKE and (not session.player.sword or not session.player.sword.enabled): return false
		if attribute == A.MULTISTRIKE:
			if rules.additional_strike_damage_ratio <= 0.0: return false
			for tier in rules.strike_speed_thresholds.size() + 1:
				if current.strike_count(tier, true) != preview.strike_count(tier, true): return true
			return false
		if attribute == A.SPEED_DAMAGE:
			return not is_equal_approx(current.speed_damage_multiplier(rules.speed_damage_high, true), preview.speed_damage_multiplier(rules.speed_damage_high, true))
		return not is_equal_approx(session.combat_modifiers.bonus(attribute), preview.bonus(attribute))
	var key: String = {A.DAMAGE: "damage", A.COOLDOWN: "interval", A.ATTACK_SPEED: "interval", A.RANGE: "range"}.get(attribute, "")
	if not key.is_empty():
		var before: Array[Dictionary] = session.get_attack_stats()
		var after: Array[Dictionary] = session.get_attack_stats(preview)
		for index in mini(before.size(), after.size()):
			if before[index].has(key) and after[index].has(key) and not is_equal_approx(float(before[index][key]), float(after[index][key])): return true
		return false
	if attribute == A.MOVE_SPEED:
		return is_instance_valid(session.player) and not is_equal_approx(session.player.get_movement_speed(), session.player.get_movement_speed(preview))
	if attribute == A.PICKUP_RADIUS:
		var growth := session.get_node("RunGrowth") as RunGrowth
		return growth.is_enabled() and not is_equal_approx(growth.get_attraction_radius(), growth.get_attraction_radius(preview))
	if not is_instance_valid(session.player) or not session.player.body_ricochet or not session.player.ricochet_rules or not session.player.ricochet_rules.validation_error().is_empty(): return false
	if attribute in [A.PUSH_RADIUS, A.PUSH_FORCE, A.PUSH_DURATION, A.PUSH_STUN] and not session.player.ricochet_rules.enemy_push_enabled: return false
	var body: PlayerRicochet = session.player.body_ricochet
	var before := body.get_stats()
	var after := body.get_stats(preview)
	if attribute == A.MOMENTUM_EFFICIENCY:
		for key_name in [&"flight_deceleration", &"bounce_speed_cost", &"bounce_speed_retention", &"crowd_speed_retention"]:
			if not is_equal_approx(float(before[key_name]), float(after[key_name])): return true
		return false
	var property: StringName = GrowthBuffDefinition.RICOCHET_PROPERTIES.get(attribute, &"")
	if not before.has(property): return false
	if attribute in [A.PUSH_RADIUS, A.PUSH_DURATION, A.PUSH_STUN] and before.push_initial_speed <= 0.0: return false
	if attribute == A.RICOCHET_RETENTION:
		return not is_equal_approx(float(before[property]), float(after[property])) or (session.player.ricochet_rules.crowd_deflection_enabled and not is_equal_approx(float(before.crowd_speed_retention), float(after.crowd_speed_retention)))
	return not is_equal_approx(float(before[property]), float(after[property]))

func _has_effect(definition: GrowthBuffDefinition) -> bool:
	var current: RunCombatModifiers = session.combat_modifiers
	if not current.can_apply(definition): return false
	if definition.is_ricochet() and (not is_instance_valid(session.player) or not session.player.body_ricochet or not session.player.body_ricochet.enabled): return false
	var preview := current.preview_after(definition)
	var has_benefit := false
	var gains := current.gains_for(definition)
	for attribute in gains:
		var changes := _attribute_changed(attribute, preview)
		# 代价被动作下限或属性下限吞掉时整张卡不提供，避免免费叠收益。
		if gains[attribute] < 0.0 and not changes: return false
		if gains[attribute] > 0.0 and changes: has_benefit = true
	return has_benefit

func candidates(initial_only := false) -> Array[GrowthChoiceOption]:
	_offered.clear()
	var result: Array[GrowthChoiceOption] = []
	for definition in definitions:
		if initial_only and (not definition or not definition.available_at_start): continue
		if not definition or not _has_effect(definition): continue
		if _offered.has(definition.id):
			push_error("RunBuffs: 增益 ID 不可重复：%s" % definition.id)
			continue
		var option := GrowthChoiceOption.new()
		option.id = definition.id
		option.epic = definition.epic
		option.growth_level = session.combat_modifiers.level_for(definition.id)
		var level: int = session.combat_modifiers.level_for(definition.id) + 1
		var rank := "Lv.%d" % level
		if definition.max_level > 0: rank += "/%d" % definition.max_level
		if definition.is_breakthrough(level): rank += " · 突破"
		option.title = "%s\n%s" % [definition.title, rank]
		option.icon = definition.icon
		option.illustration = definition.illustration
		option.rarity = definition.rarity
		option.category = GrowthChoiceOption.Category.GLOBAL_BUFF
		option.ricochet_growth = definition.is_ricochet()
		option.description = _description(definition)
		# 只复制可调配置，嵌套收益／代价隔离，图标继续共用原资源。
		var snapshot := definition.duplicate() as GrowthBuffDefinition
		snapshot.required_levels = definition.required_levels.duplicate()
		snapshot.extra_effects = []
		for effect in definition.extra_effects:
			if effect: snapshot.extra_effects.append(effect.duplicate() as GrowthBuffEffect)
		_offered[option.id] = snapshot
		result.append(option)
	return result

func offered_definition(id: StringName) -> GrowthBuffDefinition:
	return _offered.get(id)

func _value(attribute: A, modifiers: RunCombatModifiers) -> float:
	match attribute:
		A.DAMAGE: return modifiers.damage_multiplier()
		A.RANGE: return modifiers.range_multiplier()
		A.ATTACK_SPEED: return 1.0 / modifiers.interval_multiplier()
		A.COOLDOWN: return 1.0 - modifiers.interval_multiplier()
		A.MOVE_SPEED: return session.player.get_movement_speed(modifiers)
		A.PICKUP_RADIUS: return (session.get_node("RunGrowth") as RunGrowth).get_attraction_radius(modifiers)
		A.MOMENTUM_EFFICIENCY: return 1.0 / modifiers.multiplier(attribute)
		A.HEAVY_STRIKE: return modifiers.multiplier(attribute)
		A.SPEED_DAMAGE: return modifiers.speed_damage_strength()
		A.MULTISTRIKE, A.LIFESTEAL, A.KILL_HASTE: return modifiers.bonus(attribute)
	var stats: Dictionary = session.player.body_ricochet.get_stats(modifiers)
	if attribute == A.RICOCHET_RETENTION:
		return minf(stats.bounce_speed_retention, stats.crowd_speed_retention) if session.player.ricochet_rules.crowd_deflection_enabled else stats.bounce_speed_retention
	return stats[GrowthBuffDefinition.RICOCHET_PROPERTIES[attribute]]

func _format_value(attribute: A, value: float, include_unit := true) -> String:
	match attribute:
		A.DAMAGE, A.RANGE, A.ATTACK_SPEED, A.HEAVY_STRIKE: return "×%.2f" % value
		A.SPEED_DAMAGE, A.LIFESTEAL, A.KILL_HASTE: return "%.1f%%" % (value * 100.0)
		A.MULTISTRIKE: return "%d" % roundi(value)
		A.COOLDOWN, A.RICOCHET_RETENTION, A.MOMENTUM_EFFICIENCY: return "%d%%" % roundi(value * 100.0)
		A.RICOCHET_DURATION: return "%.2f%s" % [value, "米/秒²" if include_unit else ""]
		A.MOVE_SPEED, A.RICOCHET_SPEED, A.PUSH_FORCE, A.RICOCHET_BOUNCES: return "%.2f%s" % [value, "米/秒" if include_unit else ""]
		A.PICKUP_RADIUS, A.PUSH_RADIUS: return "%.2f%s" % [value, "米" if include_unit else ""]
	return "%.2f%s" % [value, "秒" if include_unit else ""]

func _description(definition: GrowthBuffDefinition) -> String:
	var current: RunCombatModifiers = session.combat_modifiers
	var preview := current.preview_after(definition)
	var summary := definition.description
	var rows := PackedStringArray()
	var rules := current.growth_rules
	var gains := current.gains_for(definition)
	for attribute in gains:
		if not _attribute_changed(attribute, preview): continue
		if attribute == A.SPEED_DAMAGE:
			for entry in [["低速增伤", rules.speed_damage_low], ["高速增伤", rules.speed_damage_high]]:
				rows.append("%s %s%% → %s%%" % [entry[0], CARD_TEXT.number((current.speed_damage_multiplier(entry[1], true) - 1.0) * 100.0, 1), CARD_TEXT.number((preview.speed_damage_multiplier(entry[1], true) - 1.0) * 100.0, 1)])
			continue
		if attribute == A.MULTISTRIKE:
			rows.append("每次挥剑 %s → %s 刀" % [_strike_counts(current), _strike_counts(preview)])
			rows.append("追加刀伤害 %s%%" % CARD_TEXT.number(rules.additional_strike_damage_ratio * 100.0, 1))
			continue
		var label: String = LABELS[attribute]
		if gains[attribute] < 0.0: label = "代价·" + label
		var before := current.damage_multiplier() if attribute == A.HEAVY_STRIKE else _value(attribute, current)
		var after := preview.damage_multiplier() if attribute == A.HEAVY_STRIKE else _value(attribute, preview)
		rows.append("%s %s → %s" % [label, _format_value(attribute, before, false), _format_value(attribute, after)])
	if definition.attribute == A.HEAVY_STRIKE:
		if not is_equal_approx(current.interval_multiplier(), preview.interval_multiplier()):
			rows.append("攻速 ×%.2f → ×%.2f" % [1.0 / current.interval_multiplier(), 1.0 / preview.interval_multiplier()])
		else: summary = "继续提高伤害，攻速不再降低"
	if definition.attribute == A.KILL_HASTE and rules:
		rows.append("每层 %s 秒 · 最多 %d 层" % [CARD_TEXT.number(rules.kill_haste_seconds, 1), rules.kill_haste_max_stacks])
		rows.append("满层加速 %s%% → %s%%" % [CARD_TEXT.number(current.bonus(A.KILL_HASTE) * rules.kill_haste_max_stacks * 100.0, 1), CARD_TEXT.number(preview.bonus(A.KILL_HASTE) * rules.kill_haste_max_stacks * 100.0, 1)])
	if definition.is_ricochet(): summary += "\n下次蓄力时生效"
	return CARD_TEXT.compose(summary, rows)

func _strike_counts(modifiers: RunCombatModifiers) -> String:
	var least := modifiers.strike_count(0, true)
	var most := modifiers.strike_count(modifiers.growth_rules.strike_speed_thresholds.size(), true)
	return str(least) if least == most else "%d～%d" % [least, most]

func _choose(_level: int, id: StringName) -> void:
	if not _offered.has(id): return
	var definition := _offered[id]
	if _has_effect(definition): session.combat_modifiers.apply_buff(definition)
	_offered.clear()
