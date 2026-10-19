extends "res://tests/test_melee_death_feedback.gd"

func extra_feedback_checks() -> void:
	await super.extra_feedback_checks()
	var effect := EnemyDeathEffect.new()
	check(effect.has_signal("presentation_event"), "死亡声音消费真实演出阶段信号")
	if not effect.has_signal("presentation_event"):
		effect.free()
		return
	world.add_child(effect)
	var stages: Array[StringName] = []
	effect.presentation_event.connect(func(stage: StringName, _point: Vector3): stages.append(stage))
	var sample := spawn()
	var options := player.action_visuals.duplicate() as PlayerActionVisuals
	options.melee_death_landing_enabled = true
	effect.begin(sample.sprite, false, player.movement_camera, options, {"source": &"flight_sword", "motion_velocity": Vector3.RIGHT * 12.0})
	effect.set_process(false)
	check(stages.is_empty(), "死亡短顿内不提前播放抛飞气流")
	effect._process(effect._pause_seconds + 0.01)
	check(stages.count(&"air") == 1 and stages.count(&"land") == 0, "首次离开短顿时发出一次抛飞事件")
	effect._process(effect._air_seconds)
	check(stages.count(&"air") == 1 and stages.count(&"land") == 1, "实际进入落地段才发出一次落地事件")
	effect._process(0.01)
	check(stages.count(&"land") == 1, "落地弹跳不逐帧重复触发声音")
	stages.clear()
	effect.begin_burst(Vector3.ZERO, .016, player.movement_camera, player.action_visuals)
	effect._process(.1)
	check(stages.is_empty(), "集中爆点不伪造尸体或重复死亡声音")
	effect.stop()
	sample.cancel()
	session.enemies.erase(sample)
	effect.queue_free()
	await settle(1)
