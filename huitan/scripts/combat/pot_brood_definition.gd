class_name PotBroodDefinition
extends WaveMeleeEnemyDefinition

@export_group("一代裂殖")
@export var child_enemy_id: StringName = &"mini_slime"
@export_range(0.1, 2.0, 0.05) var split_delay := 0.4

func validation_error() -> String:
	var error := super.validation_error()
	if not error.is_empty(): return error
	if child_enemy_id.is_empty() or child_enemy_id == enemy_id: return "裂殖幼体需要独立目录标识，不能再次生成母体"
	if not is_finite(split_delay) or split_delay <= 0.0: return "分裂延迟须为正数"
	return ""

func catalog_error(registered: Dictionary) -> String:
	if not registered.has(child_enemy_id): return "裂瓷壶兽的幼体未登记：" + String(child_enemy_id)
	if registered[child_enemy_id] is PotBroodDefinition: return "裂瓷壶兽的幼体不能继续裂殖"
	return ""
