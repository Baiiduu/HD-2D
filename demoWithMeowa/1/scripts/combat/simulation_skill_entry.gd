@tool
class_name SimulationSkillEntry
extends Resource

## 巨量怪潮模拟的持有技能；0 级表示不携带，等级上限取技能本身的配置。
@export var skill_definition: CombatSkillDefinition:
	set(value):
		skill_definition = value
		notify_property_list_changed()
@export_range(0, 20, 1) var skill_level := 1

func _validate_property(property: Dictionary) -> void:
	if property.name == "skill_level" and skill_definition:
		property.hint_string = "0,%d,1" % skill_definition.levels.size()

func validation_error() -> String:
	if not skill_definition or skill_definition.id.is_empty(): return "模拟技能需要有效的技能定义"
	if skill_level < 0 or skill_level > skill_definition.levels.size(): return "模拟技能等级超出可用范围：" + skill_definition.display_name
	return ""
