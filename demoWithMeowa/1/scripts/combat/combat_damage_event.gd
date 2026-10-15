class_name CombatDamageEvent
extends RefCounted

## 已结算的命中快照；显示层只读，不持有怪物或武器节点。
var amount := 0.0
var requested_amount := 0.0
var target_id := 0
var world_position := Vector3.ZERO
var direction := Vector3.ZERO
var source: StringName = &""
## 表现标签，与伤害公式独立；未知标签回退普通样式。
var style: StringName = &"normal"
var lethal := false

static func from_hit(enemy: WaveEnemy, dealt: float, requested: float, context: Dictionary) -> CombatDamageEvent:
	var event := CombatDamageEvent.new()
	event.amount = dealt
	event.requested_amount = requested
	event.target_id = enemy.get_instance_id()
	event.world_position = enemy.get_damage_feedback_position()
	event.direction = context.get("direction", Vector3.ZERO)
	if not event.direction.is_finite(): event.direction = Vector3.ZERO
	event.source = context.get("source", &"")
	event.style = context.get("style", &"normal")
	event.lethal = enemy.health <= 0.0
	return event
