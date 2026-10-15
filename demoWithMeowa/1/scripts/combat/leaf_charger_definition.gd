class_name LeafChargerDefinition
extends WaveMeleeEnemyDefinition

@export_group("锁线冲撞")
@export_range(1.0, 10.0, 0.1) var trigger_distance := 4.8
@export_range(0.4, 2.0, 0.05) var windup_seconds := 0.8
@export_range(1.0, 12.0, 0.1) var charge_speed := 6.0
@export_range(1.0, 10.0, 0.1) var charge_distance := 5.0
@export_range(0.2, 3.0, 0.05) var recovery_seconds := 0.9
@export_range(0.5, 8.0, 0.1) var attack_interval := 3.2

func validation_error() -> String:
	var error := super.validation_error()
	if not error.is_empty(): return error
	for value in [trigger_distance, windup_seconds, charge_speed, charge_distance, recovery_seconds, attack_interval]:
		if not is_finite(value) or value <= 0.0: return "冲撞距离、速度与各阶段时间须为正数"
	return ""
