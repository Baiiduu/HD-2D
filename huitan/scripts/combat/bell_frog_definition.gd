class_name BellFrogDefinition
extends WaveMeleeEnemyDefinition

@export_group("有限鼓舞")
@export_range(1.0, 6.0, 0.1) var boost_radius := 3.2
@export_range(1.05, 1.8, 0.05) var speed_multiplier := 1.35
@export_range(0.3, 3.0, 0.1) var boost_seconds := 1.8
@export_range(0.3, 2.0, 0.05) var windup_seconds := 0.55
@export_range(0.1, 2.0, 0.05) var recovery_seconds := 0.35
@export_range(1.0, 8.0, 0.1) var attack_interval := 3.5

func validation_error() -> String:
	var error := super.validation_error()
	if not error.is_empty(): return error
	for value in [boost_radius, boost_seconds, windup_seconds, recovery_seconds, attack_interval]:
		if not is_finite(value) or value <= 0.0: return "鼓舞范围与各阶段时间须为正数"
	if not is_finite(speed_multiplier) or speed_multiplier <= 1.0 or speed_multiplier > 1.8: return "鼓舞倍率须大于 1 且不超过 1.8"
	return ""
