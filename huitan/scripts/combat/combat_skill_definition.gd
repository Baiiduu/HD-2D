class_name CombatSkillDefinition
extends Resource

@export_group("本局技能")
@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D
## 选卡专用插画；留空时使用原图标，不影响技能栏图标。
@export var illustration: Texture2D
## 数组第一个条目是 1 级；数组长度就是当前技能的等级上限。
@export var levels: Array[CombatSkillLevel] = []

func level_data(level: int) -> CombatSkillLevel:
	return levels[level - 1] if level >= 1 and level <= levels.size() else null
