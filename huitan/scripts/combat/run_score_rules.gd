class_name RunScoreRules
extends Resource

@export var rules_version: StringName = &"score_v2"
@export_group("基础计分")
@export_range(0, 10000, 1) var common_points := 10
@export_range(0, 10000, 1) var special_points := 20
## 稳定怪物 ID 独立配置，不随经验、生命或无尽倍率增加。
@export var enemy_points: Dictionary[StringName, int] = {&"mini_slime": 2, &"pot_brood": 20}
## 这些怪物只给基础分，不推进／维持连杀，也不参与成片奖励。
@export var performance_excluded: Array[StringName] = [&"mini_slime"]
@export_range(0, 10000, 1) var wave_points := 100
@export_group("连杀倍率")
@export var combo_enabled := true
## 门槛须递增，与倍率一一对应；到档后下一次攻击使用新倍率。
@export var combo_thresholds := PackedInt32Array([5, 15, 30])
@export var combo_multipliers := PackedFloat32Array([1.25, 1.5, 2.0])
@export_range(0.1, 30.0, 0.1, "suffix:s") var combo_grace_seconds := 4.0
@export_range(0.1, 10.0, 0.1, "suffix:s") var combo_decay_seconds := 1.0
@export_group("成片击杀")
@export var burst_enabled := true
## 同刀／同片累计奖励，只补到当前最高档，不叠乘连杀倍率。
@export var burst_thresholds := PackedInt32Array([5, 10, 20])
@export var burst_rewards := PackedInt32Array([25, 50, 100])

func points_for(definition: WaveEnemyDefinition) -> int:
	if not definition: return 0
	return maxi(0, enemy_points.get(definition.enemy_id, special_points if definition.role != WaveEnemyDefinition.Role.COMMON else common_points))

func combo_tier(kills: int) -> int:
	if not combo_enabled: return 0
	var result := 0
	for index in mini(combo_thresholds.size(), combo_multipliers.size()):
		if combo_thresholds[index] > 0 and kills >= combo_thresholds[index] and is_finite(combo_multipliers[index]) and combo_multipliers[index] >= 1.0:
			result = index + 1
	return result

func combo_multiplier_milli(kills: int) -> int:
	var tier := combo_tier(kills)
	return roundi(clampf(combo_multipliers[tier - 1], 1.0, 100.0) * 1000.0) if tier > 0 else 1000

func combo_threshold(tier: int) -> int:
	return maxi(0, combo_thresholds[tier - 1]) if tier > 0 and tier <= combo_thresholds.size() else 0

func burst_reward(kills: int) -> int:
	if not burst_enabled: return 0
	var result := 0
	for index in mini(burst_thresholds.size(), burst_rewards.size()):
		if burst_thresholds[index] > 0 and kills >= burst_thresholds[index]: result = maxi(result, burst_rewards[index])
	return maxi(result, 0)
