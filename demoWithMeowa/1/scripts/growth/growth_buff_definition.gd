@tool
class_name GrowthBuffDefinition
extends GrowthChoiceOption

const Attribute := GrowthBuffEffect.Attribute
const RICOCHET_PROPERTIES := GrowthBuffEffect.RICOCHET_PROPERTIES

@export_group("本局属性增益")
## 主属性与附加效果统一授予；弹射参数仍在开始蓄力时固定本次快照。
@export var attribute: Attribute = Attribute.DAMAGE
## 同类相加：通常 0.2 为 +20% 效率，速度保留 0.05 为 +5 个百分点。
@export_range(0.0, 2.0, 0.01, "or_greater") var bonus_per_level := 0.2
## 0 表示持续可选；正数用于有限专精或单次奖励。
@export_range(0, 1000, 1, "or_greater") var max_level := 0
## 同类总增幅上限；0 不额外封顶。保速实际仍最多 100%。
@export_range(0.0, 10.0, 0.01, "or_greater") var bonus_cap := 0.0
@export_group("成长节奏与专精")
## 此等级以后温和递减单次比例收益；0 不递减。
@export_range(0, 1000, 1) var diminishing_after := 10
## 每隔若干级获得一次增强收益；0 关闭。
@export_range(0, 100, 1) var breakthrough_every := 5
@export_range(1.0, 4.0, 0.1) var breakthrough_multiplier := 1.5
## 必须先获得的局内条目等级；不消耗前置等级。
@export var required_levels: Dictionary[StringName, int] = {}
## 组合词条的其它收益或代价，与主属性一起确认、取快照和重置。
@export var extra_effects: Array[GrowthBuffEffect] = []

func is_breakthrough(level: int) -> bool:
	return breakthrough_every > 0 and level > 0 and level % breakthrough_every == 0

func gain_scale(current_level: int, _kind: Attribute) -> float:
	var next := current_level + 1
	var scale := breakthrough_multiplier if is_breakthrough(next) else 1.0
	if diminishing_after > 0 and next > diminishing_after:
		scale *= sqrt(float(diminishing_after) / next)
	return scale

func available_gain(current: float, current_level := 0) -> float:
	return GrowthBuffEffect.capped_gain(attribute, maxf(bonus_per_level, 0.0) * gain_scale(current_level, attribute), current, bonus_cap)

func ricochet_property() -> StringName:
	return RICOCHET_PROPERTIES.get(attribute, &"")

func is_ricochet() -> bool:
	return attribute == Attribute.MOMENTUM_EFFICIENCY or not ricochet_property().is_empty()
