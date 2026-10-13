class_name RunBuffs
extends Node

@export_group("本局增益")
@export var session: Node3D
## 共用现有升级候选池；每个增益有独立数值、等级上限和总增幅上限。
@export var definitions: Array[GrowthBuffDefinition] = []

var _offered: Dictionary[StringName, GrowthBuffDefinition] = {}

func _ready() -> void:
	(session.get_node("RunGrowth") as RunGrowth).growth_chosen.connect(_choose)
	session.run_started.connect(_clear_offered)
	session.run_ended.connect(func(_reason: String): _clear_offered())

func _clear_offered() -> void:
	_offered.clear()

func _stat_key(definition: GrowthBuffDefinition) -> String:
	return ["damage", "interval", "range"][definition.attribute]

func _has_effect(definition: GrowthBuffDefinition) -> bool:
	if not session.combat_modifiers.can_apply(definition): return false
	var before: Array[Dictionary] = session.get_attack_stats()
	var after: Array[Dictionary] = session.get_attack_stats(session.combat_modifiers.preview_after(definition))
	var key := _stat_key(definition)
	for index in mini(before.size(), after.size()):
		if before[index].has(key) and after[index].has(key) and not is_equal_approx(float(before[index][key]), float(after[index][key])): return true
	return false

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
		option.title = "%s  %d/%d" % [definition.title, session.combat_modifiers.level_for(definition.id) + 1, definition.max_level]
		option.icon = definition.icon
		option.description = _description(definition)
		# 保留卡面生成时的配置，远程调参不改变已经展示的奖励。
		_offered[option.id] = definition.duplicate() as GrowthBuffDefinition
		result.append(option)
	return result

func _description(definition: GrowthBuffDefinition) -> String:
	var current: RunCombatModifiers = session.combat_modifiers
	var preview := current.preview_after(definition)
	var lines := PackedStringArray(["本局共享增益"])
	match definition.attribute:
		GrowthBuffDefinition.Attribute.DAMAGE:
			lines.append("伤害系数\n×%.2f → ×%.2f" % [current.damage_multiplier(), preview.damage_multiplier()])
		GrowthBuffDefinition.Attribute.COOLDOWN:
			lines.append("减幅 %d%% → %d%%" % [roundi((1.0 - current.interval_multiplier()) * 100), roundi((1.0 - preview.interval_multiplier()) * 100)])
		GrowthBuffDefinition.Attribute.RANGE:
			lines.append("增幅 %d%% → %d%%" % [roundi((current.range_multiplier() - 1.0) * 100), roundi((preview.range_multiplier() - 1.0) * 100)])
	var before: Array[Dictionary] = session.get_attack_stats()
	var after: Array[Dictionary] = session.get_attack_stats(preview)
	var key := _stat_key(definition)
	var suffix := {"damage": "", "interval": "秒", "range": "米"}
	for index in mini(before.size(), after.size()):
		if not before[index].has(key) or not after[index].has(key): continue
		lines.append("%s\n%.2f → %.2f%s" % [before[index].get("name", "攻击"), before[index][key], after[index][key], suffix[key]])
	if definition.attribute == GrowthBuffDefinition.Attribute.COOLDOWN:
		lines.append("动作下限仍生效")
	elif definition.attribute == GrowthBuffDefinition.Attribute.RANGE:
		lines.append("特效同步扩大")
	return "\n".join(lines)

func _choose(_level: int, id: StringName) -> void:
	if not _offered.has(id): return
	var definition := _offered[id]
	if _has_effect(definition): session.combat_modifiers.apply_buff(definition)
	_offered.clear()
