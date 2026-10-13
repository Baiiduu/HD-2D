class_name ExperienceRules
extends Resource

@export_group("本局经验曲线")
## 1 → 2 级需要的经验，后续按线性及二次增量计算。
@export_range(1, 10000, 1) var first_level_experience := 10
@export_range(0, 10000, 1) var per_level_increase := 5
@export_range(0, 1000, 1) var curve_increase := 0
## 可调的框架上限，非正式成长平衡；达到后不继续积累升级经验。
@export_range(2, 1000, 1) var level_cap := 100

func required_for(level: int) -> int:
	var step := maxi(level - 1, 0)
	return maxi(1, first_level_experience + per_level_increase * step + curve_increase * step * step)
