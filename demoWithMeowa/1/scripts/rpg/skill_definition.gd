class_name SkillDefinition
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
## 可选的技能展示数值；实际施放逻辑后续使用同一份配置。
@export var values: Dictionary[String, float] = {}
