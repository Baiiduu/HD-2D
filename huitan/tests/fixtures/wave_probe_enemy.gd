extends WaveEnemy

## 无视觉的接口测试怪物：保持原地，用自己的攻击时机造成伤害。
var attack_attempts := 0
var child_definition: WaveEnemyDefinition

func _combat_tick(_delta: float) -> void:
	attack_attempts += 1
	damage_player.call(attack_damage)

func _on_defeated() -> void:
	if child_definition:
		request_spawn.call(child_definition, 2, 0.5, global_position)
