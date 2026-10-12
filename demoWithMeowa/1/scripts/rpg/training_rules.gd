class_name TrainingRules
extends Resource

const ATTRIBUTES := ["health", "attack", "defense"]

@export_group("基础属性")
@export_range(1, 10000, 1) var base_health := 100.0
## 魔力基础上限；与装备加成共同提供蓝条上限，当前不增加训练项目。
@export_range(1, 10000, 1) var base_mana := 100.0
@export_range(0, 1000, 1) var base_attack := 10.0
@export_range(0, 1000, 1) var base_defense := 5.0
@export_group("训练消耗与等级")
## 首次建立角色存档时赠送的训练点；已有存档不会重复领取。
@export_range(0, 10000, 1) var initial_points := 12
## 每项属性独立的训练等级上限。
@export_range(1, 100, 1) var level_cap := 5
## 从 0 级升到 1 级的训练点消耗。
@export_range(1, 1000, 1) var first_cost := 1
## 每已有一级增加的训练点消耗，0 表示每级同价。
@export_range(0, 1000, 1) var cost_growth := 1
@export_group("每级增量")
@export_range(0, 1000, 1) var health_gain := 10.0
@export_range(0, 1000, 1) var attack_gain := 2.0
@export_range(0, 1000, 1) var defense_gain := 1.0

func get_base_attributes() -> Dictionary[String, float]:
	return {"health": base_health, "mana": base_mana, "attack": base_attack, "defense": base_defense}

func get_gain(attribute: String) -> float:
	return {"health": health_gain, "attack": attack_gain, "defense": defense_gain}.get(attribute, 0.0)

func get_cost(level: int) -> int:
	return maxi(1, first_cost + maxi(0, level) * cost_growth)
