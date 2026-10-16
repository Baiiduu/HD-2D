class_name RunBuffs
extends Node

const A := GrowthBuffDefinition.Attribute
const LABELS := {
	A.DAMAGE: "伤害", A.COOLDOWN: "间隔减幅", A.RANGE: "攻击范围", A.ATTACK_SPEED: "攻速",
	A.RICOCHET_SPEED: "弹射初速", A.RICOCHET_DURATION: "飞行耗速", A.RICOCHET_BOUNCES: "碰撞耗速",
	A.RICOCHET_RETENTION: "最低保速", A.CHARGE_EFFICIENCY: "蓄满", A.RECOVERY_EFFICIENCY: "收势",
	A.RICOCHET_COOLDOWN_EFFICIENCY: "发射间隔", A.PUSH_RADIUS: "拨怪范围", A.PUSH_FORCE: "推力",
	A.PUSH_DURATION: "推力持续", A.PUSH_STUN: "眩晕", A.MOVE_SPEED: "移动", A.PICKUP_RADIUS: "吸取范围",
	A.MOMENTUM_EFFICIENCY: "耗速倍率",
}

@export_group("本局增益")
@export var session: Node3D
## 正式池登记三种通用成长与三种弹射成长；0 级上限表示持续成长。
@export var definitions: Array[GrowthBuffDefinition] = []

var _offered: Dictionary[StringName, GrowthBuffDefinition] = {}

func _ready() -> void:
	(session.get_node("RunGrowth") as RunGrowth).growth_chosen.connect(_choose)
	session.run_started.connect(_clear_offered)
	session.run_ended.connect(func(_reason: String): _clear_offered())

func _clear_offered() -> void:
	_offered.clear()

func _attribute_changed(attribute: A, preview: RunCombatModifiers) -> bool:
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
		return growth.enabled and not is_equal_approx(growth.get_attraction_radius(), growth.get_attraction_radius(preview))
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
	if definition.is_ricochet() and (not is_instance_valid(session.player) or not session.player.ricochet_rules or not session.player.ricochet_rules.enabled): return false
	var preview := current.preview_after(definition)
	var has_benefit := false
	var gains := current.gains_for(definition)
	for attribute in gains:
		var changes := _attribute_changed(attribute, preview)
		# 代价被动作下限或属性下限吞掉时整张卡不提供，避免免费叠收益。
		if gains[attribute] < 0.0 and not changes: return false
		if gains[attribute] > 0.0 and changes: has_benefit = true
	return has_benefit

func candidates() -> Array[GrowthChoiceOption]:
	_offered.clear()
	var result: Array[GrowthChoiceOption] = []
	for definition in definitions:
		if not definition or not _has_effect(definition): continue
		if _offered.has(definition.id):
			push_error("RunBuffs: 增益 ID 不可重复：%s" % definition.id)
			continue
		var option := GrowthChoiceOption.new()
		option.id = definition.id
		var level: int = session.combat_modifiers.level_for(definition.id) + 1
		var rank := "Lv.%d" % level
		if definition.max_level > 0: rank += "/%d" % definition.max_level
		if definition.is_breakthrough(level): rank += " · 突破"
		option.title = "%s\n%s" % [definition.title, rank]
		option.icon = definition.icon
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

func _value(attribute: A, modifiers: RunCombatModifiers) -> float:
	match attribute:
		A.DAMAGE: return modifiers.damage_multiplier()
		A.RANGE: return modifiers.range_multiplier()
		A.ATTACK_SPEED: return 1.0 / modifiers.interval_multiplier()
		A.COOLDOWN: return 1.0 - modifiers.interval_multiplier()
		A.MOVE_SPEED: return session.player.get_movement_speed(modifiers)
		A.PICKUP_RADIUS: return (session.get_node("RunGrowth") as RunGrowth).get_attraction_radius(modifiers)
		A.MOMENTUM_EFFICIENCY: return 1.0 / modifiers.multiplier(attribute)
	var stats: Dictionary = session.player.body_ricochet.get_stats(modifiers)
	if attribute == A.RICOCHET_RETENTION:
		return minf(stats.bounce_speed_retention, stats.crowd_speed_retention) if session.player.ricochet_rules.crowd_deflection_enabled else stats.bounce_speed_retention
	return stats[GrowthBuffDefinition.RICOCHET_PROPERTIES[attribute]]

func _format_value(attribute: A, value: float, include_unit := true) -> String:
	match attribute:
		A.DAMAGE, A.RANGE, A.ATTACK_SPEED: return "×%.2f" % value
		A.COOLDOWN, A.RICOCHET_RETENTION, A.MOMENTUM_EFFICIENCY: return "%d%%" % roundi(value * 100.0)
		A.RICOCHET_DURATION: return "%.2f%s" % [value, "米/秒²" if include_unit else ""]
		A.MOVE_SPEED, A.RICOCHET_SPEED, A.PUSH_FORCE, A.RICOCHET_BOUNCES: return "%.2f%s" % [value, "米/秒" if include_unit else ""]
		A.PICKUP_RADIUS, A.PUSH_RADIUS: return "%.2f%s" % [value, "米" if include_unit else ""]
	return "%.2f%s" % [value, "秒" if include_unit else ""]

func _description(definition: GrowthBuffDefinition) -> String:
	var current: RunCombatModifiers = session.combat_modifiers
	var preview := current.preview_after(definition)
	var lines := PackedStringArray()
	var gains := current.gains_for(definition)
	for attribute in gains:
		if not _attribute_changed(attribute, preview): continue
		var label: String = LABELS[attribute]
		if gains[attribute] < 0.0: label = "代价·" + label
		lines.append("%s\n%s → %s" % [label, _format_value(attribute, _value(attribute, current), false), _format_value(attribute, _value(attribute, preview))])
	if definition.attribute == A.MOMENTUM_EFFICIENCY: lines.append("飞行与碰撞损失同步降低")
	var level := current.level_for(definition.id) + 1
	if definition.is_breakthrough(level): lines.append("突破加成 ×%.1f" % definition.breakthrough_multiplier)
	if definition.is_ricochet(): lines.append("下次蓄力生效")
	elif definition.attribute == A.ATTACK_SPEED: lines.append("完整动作不加速")
	return "\n".join(lines)

func _choose(_level: int, id: StringName) -> void:
	if not _offered.has(id): return
	var definition := _offered[id]
	if _has_effect(definition): session.combat_modifiers.apply_buff(definition)
	_offered.clear()
