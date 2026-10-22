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
	var airborne: Array[bool] = []
	effect.presentation_event.connect(func(stage: StringName, _point: Vector3): stages.append(stage))
	effect.airborne_changed.connect(func(subject: Node3D, active: bool):
		check(subject == effect.get_focus_subject(), "起落信号绑定真实尸体快照主体")
		airborne.append(active))
	var sample := spawn()
	var options := player.action_visuals.duplicate() as PlayerActionVisuals
	options.melee_death_landing_enabled = true
	effect.begin(sample.sprite, false, player.movement_camera, options, {"source": &"flight_sword", "motion_velocity": Vector3.RIGHT * 12.0})
	effect.set_process(false)
	check(stages.is_empty() and airborne.is_empty(), "死亡短顿内不提前播放抛飞气流")
	effect._process(effect._pause_seconds + 0.01)
	check(stages.count(&"air") == 1 and stages.count(&"land") == 0, "首次离开短顿时发出一次抛飞事件")
	check(airborne == [true], "离开短顿后主体进入真实空中声音状态")
	effect._process(effect._air_seconds)
	check(stages.count(&"air") == 1 and stages.count(&"land") == 1, "实际进入落地段才发出一次落地事件")
	check(airborne == [true, false], "实际落地时结束该主体的空中声音")
	effect._process(0.01)
	check(stages.count(&"land") == 1, "落地弹跳不逐帧重复触发声音")
	airborne.clear()
	options.melee_death_landing_enabled = false
	effect.begin(sample.sprite, false, player.movement_camera, options)
	effect.set_process(false)
	effect._process(effect._pause_seconds + .01)
	effect._process(effect._air_seconds)
	check(airborne == [true, false], "关闭落地装饰时也按真实空中段结束声音")
	airborne.clear()
	effect.begin(sample.sprite, false, player.movement_camera, options)
	effect.set_process(false)
	effect._process(effect._pause_seconds + .01)
	effect.stop()
	effect.stop()
	check(airborne == [true, false], "提前回收只结束一次，复用不串入旧声音")
	stages.clear()
	airborne.clear()
	effect.begin_burst(Vector3.ZERO, .016, player.movement_camera, player.action_visuals)
	effect._process(.1)
	check(stages.is_empty() and airborne.is_empty(), "集中爆点不伪造尸体或重复死亡声音")
	effect.stop()
	sample.cancel()
	session.enemies.erase(sample)
	effect.queue_free()
	await settle(1)
