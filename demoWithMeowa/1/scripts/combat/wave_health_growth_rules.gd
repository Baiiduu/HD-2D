class_name WaveHealthGrowthRules
extends Resource

## 无尽模式生命曲线；每只怪物仍使用自己的基础生命，倍率最多十倍。
const HARD_MAX_MULTIPLIER := 10.0
@export_range(1, 10000, 1) var start_wave := 4
## 每波增加基础生命的比例，0.15 表示每波加基础生命的 15%，不逐波复利。
@export_range(0.0, 1.0, 0.01) var bonus_per_wave := 0.15
@export_range(1.0, 10.0, 0.1) var minimum_multiplier := 1.0
@export_range(1.0, 10.0, 0.1) var maximum_multiplier := 10.0

func multiplier(number: int) -> float:
	if bonus_per_wave <= 0.0: return minimum_multiplier
	# 浮点步数避免极端波号的整数溢出；最终倍率始终封顶。
	var steps := maxf(float(number) - start_wave + 1.0, 0.0)
	return clampf(1.0 + steps * bonus_per_wave, minimum_multiplier, minf(maximum_multiplier, HARD_MAX_MULTIPLIER))

func validation_error() -> String:
	if start_wave < 1: return "生命成长起始波次须为正数"
	if not is_finite(bonus_per_wave) or bonus_per_wave < 0.0: return "生命每波增幅不能为负数"
	if not is_finite(minimum_multiplier) or not is_finite(maximum_multiplier) or minimum_multiplier < 1.0 or maximum_multiplier < minimum_multiplier or maximum_multiplier > HARD_MAX_MULTIPLIER:
		return "生命成长倍率须在 1～10 倍内，下限不能超过上限"
	return ""
