class_name CombatSkillLevel
extends Resource

## 这一等级的可见行为变化；实际数值由攻击组件读取同一份配置。
@export_multiline var description := ""
## 倍率以攻击组件的基础参数为准；各技能只解释自己支持的参数。
@export var parameters: Dictionary[String, float] = {}
