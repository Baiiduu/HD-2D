@tool
class_name SceneCombatConfiguration
extends Resource
## 每张地图拥有独立配置资源；共用战斗代码，不修改其它地图的平衡值。

@export_group("人物基础战斗")
@export var ricochet_rules: PlayerRicochetRules
@export var sword_rules: PlayerSwordRules
@export var action_visuals: PlayerActionVisuals
@export var flight_trail_settings: PlayerFlightTrailSettings
@export var ricochet_camera_settings: RicochetCameraSettings
@export var crowd_clearance_distance := 0.12
@export_group("怪物与波次")
@export var enemy_catalog: WaveEnemyCatalog
@export var default_enemy: WaveEnemyDefinition
@export var population_rules: WavePopulationRules
@export var health_growth_rules: WaveHealthGrowthRules
@export var waves: Array[WaveDefinition] = []
@export var endless_mode := true
@export var max_active_enemies := 128
@export var batch_crowd_enabled := true
@export var native_chase_enabled := true
@export var slime_ground_movement_enabled := true
@export_group("经验与成长")
@export var experience_rules: ExperienceRules
@export var growth_definitions: Array[GrowthBuffDefinition] = []
@export var skill_definitions: Array[CombatSkillDefinition] = []
@export var cards_per_draw := 3
@export var rerolls_per_run := 3
@export_group("奔雷涌潮")
@export var storm_damage := 50.0
@export var storm_attack_interval := 0.9
@export var storm_trigger_radius := 1.25
@export var storm_spread_radius := 1.5
@export var storm_max_propagation_radius := 3.6
@export var storm_spread_layers := 2
@export var storm_targets_per_layer := 3
@export var storm_layer_interval := 0.085
@export_group("伤害数字")
@export var number_styles: Array[DamageNumberStyle] = []

## 仅检查数据，不修改资源或实例化地图。空的可选槽与空池继续使用原有禁用／回退规则。
func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	for property in ["crowd_clearance_distance", "storm_damage", "storm_trigger_radius", "storm_spread_radius", "storm_max_propagation_radius", "storm_layer_interval"]:
		var value: float = get(property)
		if not is_finite(value) or value < 0.0: errors.append(property + ": 须为有限非负数")
	if not is_finite(storm_attack_interval) or storm_attack_interval <= 0.0:
		errors.append("storm_attack_interval: 须为有限正数")
	for property in ["max_active_enemies", "cards_per_draw", "storm_targets_per_layer"]:
		if int(get(property)) < 1: errors.append(property + ": 须至少为 1")
	for property in ["rerolls_per_run", "storm_spread_layers"]:
		if int(get(property)) < 0: errors.append(property + ": 不能为负数")
	for property in ["ricochet_rules", "sword_rules", "flight_trail_settings", "enemy_catalog", "default_enemy", "population_rules", "health_growth_rules"]:
		var resource: Resource = get(property)
		if resource:
			var error: String = resource.validation_error()
			if not error.is_empty(): errors.append(property + ": " + error)
	if experience_rules and (experience_rules.first_level_experience < 1 or experience_rules.per_level_increase < 0 or experience_rules.curve_increase < 0 or experience_rules.level_cap < 2):
		errors.append("experience_rules: 经验门槛须为正数、增量非负、等级上限至少为 2")
	var skill_ids := {}
	for index in skill_definitions.size():
		var definition := skill_definitions[index]
		var path := "skill_definitions[%d]" % index
		if not definition:
			errors.append(path + ": 条目为空")
			continue
		var id_error := _id_error(definition.id, path, skill_ids)
		if not id_error.is_empty(): errors.append(id_error)
		if definition.id in [&"body_ricochet", &"dash", &"basic_sword", &"blink"]:
			errors.append(path + ".id: 这里只接受局内可选技能，角色固有技能与普攻另行管理")
		if definition.levels.is_empty(): errors.append(path + ".levels: 至少需要一个等级")
		for level in definition.levels.size():
			var data := definition.levels[level]
			if not data:
				errors.append(path + ".levels[%d]: 等级为空" % level)
				continue
			for parameter in data.parameters:
				if not is_finite(data.parameters[parameter]):
					errors.append(path + ".levels[%d].parameters.%s: 须为有限数值" % [level, parameter])
	var growth_ids := {}
	for index in growth_definitions.size():
		var definition := growth_definitions[index]
		var path := "growth_definitions[%d]" % index
		if not definition:
			errors.append(path + ": 条目为空")
			continue
		var id_error := _id_error(definition.id, path, growth_ids)
		if not id_error.is_empty(): errors.append(id_error)
		for property in ["bonus_per_level", "bonus_cap"]:
			var value: float = definition.get(property)
			if not is_finite(value) or value < 0.0: errors.append(path + "." + property + ": 须为有限非负数")
		if definition.max_level < 0: errors.append(path + ".max_level: 不能为负数")
	var style_ids := {}
	for index in number_styles.size():
		var style := number_styles[index]
		var path := "number_styles[%d]" % index
		if style:
			var id_error := _id_error(style.style_id, path, style_ids)
			if not id_error.is_empty(): errors.append(id_error)
		else: errors.append(path + ": 条目为空")
	# 地形、入口与实际批次容量仍由 WavePrototype 在建立本局快照时检查。
	return errors

func validation_error() -> String:
	return "；".join(validation_errors())

func _id_error(id: StringName, path: String, seen: Dictionary) -> String:
	if id == &"": return path + ".id: 不能为空"
	if seen.has(id): return path + ".id: 重复标识 " + String(id)
	seen[id] = true
	return ""
