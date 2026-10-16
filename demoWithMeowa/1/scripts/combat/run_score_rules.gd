class_name RunScoreRules
extends Resource

@export var rules_version: StringName = &"score_v1"
@export_range(0, 10000, 1) var common_points := 10
@export_range(0, 10000, 1) var special_points := 20
## 稳定怪物 ID 独立配置，不随经验、生命或无尽倍率增加。
@export var enemy_points: Dictionary[StringName, int] = {&"mini_slime": 2, &"pot_brood": 20}
@export var performance_excluded: Array[StringName] = [&"mini_slime"]
@export_range(0, 10000, 1) var wave_points := 100
## 累计奖励，晋档只补差额；同次弹射最多获得末档奖励。
@export var performance_thresholds := PackedInt32Array([3, 6, 10])
@export var performance_rewards := PackedInt32Array([5, 10, 20])

func points_for(definition: WaveEnemyDefinition) -> int:
	if not definition: return 0
	return maxi(0, enemy_points.get(definition.enemy_id, special_points if definition.role != WaveEnemyDefinition.Role.COMMON else common_points))

func performance_reward(kills: int) -> int:
	var result := 0
	for index in mini(performance_thresholds.size(), performance_rewards.size()):
		if kills >= performance_thresholds[index]: result = maxi(result, performance_rewards[index])
	return maxi(result, 0)
