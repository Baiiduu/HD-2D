class_name CombatAttackSnapshot
extends RefCounted
## 一次原始出手共用；千手各刀独立命中，但共享基础剑术恢复资格。
var remaining_speed := 0.0
var speed_damage_multiplier := 1.0
var strikes := 1
var additional_strike_damage_ratio := 1.0
var sword_heal_claimed := false
