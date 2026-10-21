class_name WaveHealthGrowthRules
extends Resource

## 默认保持旧线性曲线；地图可独立开启后期复合成长，每只怪物仍使用自己的基础生命。
const HARD_MAX_MULTIPLIER := 100.0
const HARD_SUSTAINED_MAX_MULTIPLIER := 1000.0
@export_range(1, 10000, 1) var start_wave := 4
## 每波增加基础生命的比例，0.15 表示每波加基础生命的 15%，不逐波复利。
@export_range(0.0, 1.0, 0.01) var bonus_per_wave := 0.15
@export_range(1.0, 100.0, 0.1) var minimum_multiplier := 1.0
@export_range(1.0, 100.0, 0.1) var maximum_multiplier := 10.0
@export_group("后期复合生命成长")
@export_range(1, 10000, 1) var late_start_wave := 10
## 0 保持旧曲线；0.15 表示起始波及之后每波额外乘 1.15。
@export_range(0.0, 1.0, 0.01) var late_bonus_per_wave := 0.0
@export_group("成型窗口后的生命成长")
## 0 关闭，保留原曲线；开启后按已算出的生命基底逐波线性增长。
@export_range(0, 10000, 1) var sustained_start_wave := 0
@export_range(0.0, 1.0, 0.01) var sustained_bonus_per_wave := 0.0
@export_range(1.0, 1000.0, 1.0) var sustained_maximum_multiplier := 1000.0

func multiplier(number: int) -> float:
	var base := _base_multiplier(number)
	if sustained_start_wave <= 0 or sustained_bonus_per_wave <= 0.0 or number < sustained_start_wave: return base
	var steps := maxf(float(number) - sustained_start_wave + 1.0, 0.0)
	return minf(base * (1.0 + steps * sustained_bonus_per_wave), minf(sustained_maximum_multiplier, HARD_SUSTAINED_MAX_MULTIPLIER))

func _base_multiplier(number: int) -> float:
	# 浮点步数避免极端波号的整数溢出；最终倍率始终封顶。
	var steps := maxf(float(number) - start_wave + 1.0, 0.0)
	var maximum := minf(maximum_multiplier, HARD_MAX_MULTIPLIER)
	var value := maxf(1.0, 1.0 + steps * bonus_per_wave)
	if late_bonus_per_wave > 0.0 and number >= late_start_wave:
		# 在对数域先封顶，极大波号和极小增幅均不会先产生溢出的 pow。
		var late_steps := maxf(float(number) - late_start_wave + 1.0, 0.0)
		var logarithm := log(value) + late_steps * log(1.0 + late_bonus_per_wave)
		if logarithm >= log(maximum): return maximum
		value = exp(logarithm)
	return clampf(value, minimum_multiplier, maximum)

func validation_error() -> String:
	if sustained_start_wave < 0 or not is_finite(sustained_bonus_per_wave) or sustained_bonus_per_wave < 0.0 or sustained_bonus_per_wave > 1.0: return "成型后成长起始波须非负，每波增幅须在 0～1 之间"
	if not is_finite(sustained_maximum_multiplier) or sustained_maximum_multiplier < maximum_multiplier or sustained_maximum_multiplier > HARD_SUSTAINED_MAX_MULTIPLIER: return "成型后生命上限须不低于前段上限且不超过 1000 倍"
	if start_wave < 1 or late_start_wave < 1: return "生命成长起始波次须为正数"
	if not is_finite(bonus_per_wave) or bonus_per_wave < 0.0: return "生命每波增幅不能为负数"
	if not is_finite(late_bonus_per_wave) or late_bonus_per_wave < 0.0 or late_bonus_per_wave > 1.0: return "后期每波复合增幅须在 0～1 之间"
	if not is_finite(minimum_multiplier) or not is_finite(maximum_multiplier) or minimum_multiplier < 1.0 or maximum_multiplier < minimum_multiplier or maximum_multiplier > HARD_MAX_MULTIPLIER:
		return "生命成长倍率须在 1～100 倍内，下限不能超过上限"
	return ""
