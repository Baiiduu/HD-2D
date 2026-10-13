@tool
class_name GrowthChoiceOption
extends Resource

## 本轮候选项的稳定标识；UI 只回传它，不执行成长效果。
@export var id: StringName
@export var title := ""
@export_multiline var description := ""
@export var icon: Texture2D
@export var enabled := true
