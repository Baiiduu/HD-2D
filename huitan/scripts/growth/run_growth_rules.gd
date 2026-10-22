@tool
class_name RunGrowthRules
extends Resource
## 地图独立的成长与基础续航；空槽沿用旧地图规则。

@export_range(2, 100, 1) var epic_every := 5
@export_range(2, 100, 1) var legendary_every := 10
@export var guarantee_initial_legendary := true
## 普通轮按有效候选的单卡相对权重抽取，不是固定的品阶出现百分比。
@export var ordinary_rarity_weights: Dictionary[int, float] = {0:1.0, 1:0.65, 2:0.35, 3:0.15}
@export_group("击杀加速")
@export_range(0.1, 30.0, 0.1) var kill_haste_seconds := 4.0
@export_range(1, 100, 1) var kill_haste_max_stacks := 10
@export_group("基础续航")
@export_range(0.0, 0.9, 0.01) var orbit_damage_reduction := 0.3
@export_range(0.0, 1.0, 0.001) var sword_heal_fraction := 0.015
@export_range(0.0, 1.0, 0.01) var sword_heal_cap := 0.05
@export_group("伤害成长收敛")
## 地图独立启用；首张史诗保持原效果，后续名义收益平滑递减。
@export var soften_damage_growth := false
@export_range(0.1, 1.0, 0.05) var damage_growth_exponent := 0.5
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

func is_legendary_level(level: int) -> bool:
	return level > 1 and level % maxi(legendary_every, 2) == 0

func candidates(pool: Array[GrowthChoiceOption], level: int) -> Array[GrowthChoiceOption]:
	var ordinary: Array[GrowthChoiceOption] = []
	var unlocks: Array[GrowthChoiceOption] = []
	var upgrades: Array[GrowthChoiceOption] = []
	var legendary_unlocks: Array[GrowthChoiceOption] = []
	var legendary_upgrades: Array[GrowthChoiceOption] = []
	for item in pool:
		if not item or not item.enabled: continue
		var rarity := item.get_card_rarity()
		if rarity == GrowthChoiceOption.Rarity.COMMON or item.growth_level > 0: ordinary.append(item)
		if rarity == GrowthChoiceOption.Rarity.EPIC:
			if item.growth_level > 0: upgrades.append(item)
			else: unlocks.append(item)
		elif rarity == GrowthChoiceOption.Rarity.LEGENDARY:
			if item.growth_level > 0: legendary_upgrades.append(item)
			else: legendary_unlocks.append(item)
	if is_legendary_level(level) and (not legendary_unlocks.is_empty() or not legendary_upgrades.is_empty()):
		var base := unlocks if not unlocks.is_empty() else upgrades
		if base.is_empty(): base = ordinary.filter(func(card): return card.get_card_rarity() != GrowthChoiceOption.Rarity.LEGENDARY)
		var result: Array[GrowthChoiceOption] = base.duplicate()
		result.append_array(legendary_unlocks if not legendary_unlocks.is_empty() else legendary_upgrades)
		return result
	if is_epic_level(level) or is_legendary_level(level):
		if not unlocks.is_empty(): return unlocks
		if not upgrades.is_empty(): return upgrades
	return ordinary.filter(func(card): return ordinary_rarity_weights.get(card.get_card_rarity(), 1.0) > 0.0)

func damage_growth_bonus(value: float, first_bonus: float) -> float:
	if not soften_damage_growth or value <= first_bonus: return value
	return first_bonus * pow(value / first_bonus, damage_growth_exponent)

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
	if not is_finite(damage_growth_exponent) or damage_growth_exponent < 0.1 or damage_growth_exponent > 1.0: return "伤害成长指数须在 0.1～1 之间"
	if epic_every < 2 or legendary_every < 2 or maximum_strikes < 2: return "高阶成长间隔与千手上限至少为 2"
	if not is_finite(kill_haste_seconds) or kill_haste_seconds <= 0.0 or kill_haste_max_stacks < 1: return "击杀加速持续时间与层数须为正数"
	for rarity in ordinary_rarity_weights:
		if rarity < 0 or rarity > 3 or not is_finite(ordinary_rarity_weights[rarity]) or ordinary_rarity_weights[rarity] < 0.0: return "品阶权重须为有限非负数，品阶须在 0～3 范围"
	for key in ["orbit_damage_reduction", "sword_heal_fraction", "sword_heal_cap", "speed_damage_low", "speed_damage_high", "speed_damage_min_bonus", "speed_damage_max_bonus", "strike_speed_hysteresis", "additional_strike_damage_ratio", "heavy_interval_multiplier"]:
		if not is_finite(get(key)) or get(key) < 0.0: return key + " 须为有限非负数"
	if orbit_damage_reduction >= 1.0 or heavy_interval_multiplier < 1.0 or speed_damage_high <= speed_damage_low or speed_damage_max_bonus < speed_damage_min_bonus: return "成长区间或减伤参数无效"
	var last := 0.0
	for threshold in strike_speed_thresholds:
		if not is_finite(threshold) or threshold <= last: return "千手速度门槛须为递增正数"
		last = threshold
	return ""
