@tool
class_name GrowthBuffEffect
extends Resource

# 编号保持兼容；原时长／次数收益改为飞行／碰撞耗速效率，不再增加硬预算。
enum Attribute {
	DAMAGE, COOLDOWN, RANGE,
	RICOCHET_SPEED, RICOCHET_DURATION, RICOCHET_BOUNCES, RICOCHET_RETENTION,
	CHARGE_EFFICIENCY, RECOVERY_EFFICIENCY, RICOCHET_COOLDOWN_EFFICIENCY,
	PUSH_RADIUS, PUSH_FORCE, PUSH_DURATION, PUSH_STUN,
	ATTACK_SPEED, MOVE_SPEED, PICKUP_RADIUS,
}

const RICOCHET_PROPERTIES := {
	Attribute.RICOCHET_SPEED: &"maximum_launch_speed",
	Attribute.RICOCHET_DURATION: &"flight_deceleration",
	Attribute.RICOCHET_BOUNCES: &"bounce_speed_cost",
	Attribute.RICOCHET_RETENTION: &"bounce_speed_retention",
	Attribute.CHARGE_EFFICIENCY: &"full_charge_seconds",
	Attribute.RECOVERY_EFFICIENCY: &"recovery_seconds",
	Attribute.RICOCHET_COOLDOWN_EFFICIENCY: &"cooldown_seconds",
	Attribute.PUSH_RADIUS: &"push_radius",
	Attribute.PUSH_FORCE: &"push_initial_speed",
	Attribute.PUSH_DURATION: &"push_seconds",
	Attribute.PUSH_STUN: &"push_stun_seconds",
}

@export var attribute: Attribute = Attribute.DAMAGE
## 正值为收益，负值为代价；同一属性按基础值相加。
@export_range(-2.0, 2.0, 0.01, "or_less", "or_greater") var bonus_per_level := 0.1
## 正收益的同类累计上限，0 不额外封顶；负值代价不由此参数截断。
@export_range(0.0, 10.0, 0.01, "or_greater") var bonus_cap := 0.0

func available_gain(current: float, scale := 1.0) -> float:
	return capped_gain(attribute, bonus_per_level * scale, current, bonus_cap)

static func capped_gain(kind: Attribute, amount: float, current: float, cap: float) -> float:
	if not is_finite(amount) or not is_finite(cap) or not is_finite(current): return 0.0
	if amount > 0.0 and cap > 0.0: amount = minf(amount, maxf(0.0, cap - current))
	if kind == Attribute.COOLDOWN and amount > 0.0: amount = minf(amount, maxf(0.0, 0.99 - current))
	return amount
