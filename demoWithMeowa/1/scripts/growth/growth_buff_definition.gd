@tool
class_name GrowthBuffDefinition
extends GrowthChoiceOption

enum Attribute { DAMAGE, COOLDOWN, RANGE }

@export_group("本局属性增益")
## 伤害系数、攻击间隔减幅、覆盖范围增幅；只影响支持该属性的攻击。
@export var attribute: Attribute = Attribute.DAMAGE
## 每级增加的基础值比例；0.2 表示 +20%，同类按基础值相加。
@export_range(0.0, 2.0, 0.01) var bonus_per_level := 0.2
## 同一条目反复选择的上限；满级后退出候选池。
@export_range(1, 100, 1) var max_level := 3
## 同类总增幅上限；0 表示不额外封顶。冷却仍不能减到 0。
@export_range(0.0, 5.0, 0.01) var bonus_cap := 0.0

func available_gain(current: float) -> float:
	var gain := maxf(bonus_per_level, 0.0)
	if bonus_cap > 0.0: gain = minf(gain, maxf(0.0, bonus_cap - current))
	if attribute == Attribute.COOLDOWN: gain = minf(gain, maxf(0.0, 0.99 - current))
	return gain
