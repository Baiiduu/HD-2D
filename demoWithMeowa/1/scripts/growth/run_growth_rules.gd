@tool
class_name RunGrowthRules
extends Resource
## 地图独立的成长与基础续航；空槽沿用旧地图规则。

@export_range(2, 100, 1) var epic_every := 5
@export_range(0.0, 0.9, 0.01) var orbit_damage_reduction := 0.3
@export_range(0.0, 1.0, 0.001) var sword_heal_fraction := 0.015
@export_range(0.0, 1.0, 0.01) var sword_heal_cap := 0.05
@export_group("动能增伤")
@export var speed_damage_low := 4.0
@export var speed_damage_high := 16.0
@export var speed_damage_min_bonus := 0.2
@export var speed_damage_max_bonus := 1.0
@export_group("千手")
@export var strike_speed_thresholds := PackedFloat32Array([8.0, 12.0])
@export var strike_speed_hysteresis := 0.4
@export_range(2, 16, 1) var maximum_strikes := 8
## 首张千手的 2～4 刀约提供 +33%～100% 剑术输出；追加刀仍独立判定。
@export_range(0.0, 2.0, 0.01, "or_greater") var additional_strike_damage_ratio := 1.0 / 3.0
@export_group("一拳超人")
@export_range(1.0, 10.0, 0.1) var heavy_interval_multiplier := 2.0

func is_epic_level(level: int) -> bool:
	return level > 1 and level % maxi(epic_every, 2) == 0

func candidates(pool: Array[GrowthChoiceOption], level: int) -> Array[GrowthChoiceOption]:
	var ordinary: Array[GrowthChoiceOption] = []
	var unlocks: Array[GrowthChoiceOption] = []
	var upgrades: Array[GrowthChoiceOption] = []
	for item in pool:
		if not item or not item.enabled: continue
		if not item.epic: ordinary.append(item)
		elif item.growth_level > 0:
			ordinary.append(item)
			upgrades.append(item)
		else: unlocks.append(item)
	if is_epic_level(level):
		if not unlocks.is_empty(): return unlocks
		if not upgrades.is_empty(): return upgrades
	return ordinary

func speed_damage_bonus(speed: float) -> float:
	var progress := clampf(inverse_lerp(speed_damage_low, maxf(speed_damage_high, speed_damage_low + 0.01), speed), 0.0, 1.0)
	return lerpf(speed_damage_min_bonus, speed_damage_max_bonus, progress)

func speed_tier(speed: float, previous := -1) -> int:
	var tier := clampi(previous, 0, strike_speed_thresholds.size())
	if previous < 0:
		tier = 0
		for threshold in strike_speed_thresholds:
			if speed >= threshold: tier += 1
		return tier
	while tier < strike_speed_thresholds.size() and speed >= strike_speed_thresholds[tier] + strike_speed_hysteresis: tier += 1
	while tier > 0 and speed < strike_speed_thresholds[tier - 1] - strike_speed_hysteresis: tier -= 1
	return tier

func validation_error() -> String:
	if epic_every < 2 or maximum_strikes < 2: return "史诗间隔与千手上限至少为 2"
	for key in ["orbit_damage_reduction", "sword_heal_fraction", "sword_heal_cap", "speed_damage_low", "speed_damage_high", "speed_damage_min_bonus", "speed_damage_max_bonus", "strike_speed_hysteresis", "additional_strike_damage_ratio", "heavy_interval_multiplier"]:
		if not is_finite(get(key)) or get(key) < 0.0: return key + " 须为有限非负数"
	if orbit_damage_reduction >= 1.0 or heavy_interval_multiplier < 1.0 or speed_damage_high <= speed_damage_low or speed_damage_max_bonus < speed_damage_min_bonus: return "成长区间或减伤参数无效"
	var last := 0.0
	for threshold in strike_speed_thresholds:
		if not is_finite(threshold) or threshold <= last: return "千手速度门槛须为递增正数"
		last = threshold
	return ""
