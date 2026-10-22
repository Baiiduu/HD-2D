class_name LanternSpitterDefinition
extends WaveMeleeEnemyDefinition

@export_group("吐籽与退步")
@export_range(1.0, 12.0, 0.1) var shooting_range := 6.5
@export_range(0.8, 6.0, 0.1) var retreat_distance := 2.4
@export_range(0.3, 2.0, 0.05) var windup_seconds := 0.6
@export_range(0.1, 2.0, 0.05) var recovery_seconds := 0.35
@export_range(0.5, 8.0, 0.1) var attack_interval := 2.6
@export_range(1.0, 15.0, 0.1) var projectile_speed := 5.5
@export_range(1.0, 20.0, 0.1) var projectile_distance := 9.0
@export_range(0.03, 0.3, 0.01) var projectile_radius := 0.09

func validation_error() -> String:
	var error := super.validation_error()
	if not error.is_empty(): return error
	for value in [shooting_range, retreat_distance, windup_seconds, recovery_seconds, attack_interval, projectile_speed, projectile_distance, projectile_radius]:
		if not is_finite(value) or value <= 0.0: return "吐籽范围、速度、半径与各阶段时间须为正数"
	if retreat_distance >= shooting_range: return "退步距离须小于射击范围"
	return ""
