extends "res://tests/test_charge_staging.gd"

func silhouette(subject: GeometryInstance3D) -> float:
	var value: Variant = subject.get_instance_shader_parameter(&"charge_silhouette_amount")
	return float(value) if value != null else 0.0

func actor(point: Vector3) -> SlimeEnemy:
	var definition := load("res://data/enemies/wave_slime.tres") as WaveEnemyDefinition
	var enemy := definition.scene.instantiate() as SlimeEnemy
	enemy.configure_wave({"player":player, "terrain":null, "camera":camera, "navigation":session._path,
		"attack_root":null, "spatial_index":session._spatial_index, "combat_active":session.combat_active,
		"damage_player":Callable(), "request_spawn":Callable()}, definition, 0.0)
	world.add_child(enemy)
	enemy.global_position = point
	enemy.set_wave_tick_enabled(false)
	enemy.set_process(false)
	session._enemy_roster.register(enemy)
	session._spatial_index.update(enemy)
	return enemy

func settings_checks() -> void:
	var presentation := ChargePresentation.new()
	if not "charge_drama_enabled" in presentation:
		check(false, "蓄力需要地图独立的持续慢放开关")
		presentation.free()
		return
	check(not presentation.charge_drama_enabled, "共享默认关闭，不自动改变其它地图")
	await reset()
	player.ricochet_rules.full_charge_seconds = 0.5
	presentation.player = player
	presentation.enabled = true
	presentation.set("charge_drama_enabled", true)
	world.add_child(presentation)
	presentation.owner = world
	var parameters: Array[Dictionary] = load("res://addons/parameter_hub/catalog.gd").new().collect(world)
	for property in ["charge_drama_enabled", "charge_drama_start_fraction", "charge_drama_slow_scale", "charge_drama_enter_seconds", "charge_drama_fade_seconds"]:
		check(parameters.any(func(item): return item.property == property and item.common and item.category == "视觉" and item.label != property), "参数总览提供可调中文入口：" + property)
	await settle(3)
	presentation.set_process(false)
	var first := actor(Vector3(2, 0, 0))
	var second := actor(Vector3(3, 0, 0))
	var far := actor(Vector3(12, 0, 0))
	var health := first.health
	var original := first.global_transform
	check(body.begin_charge(Vector3.RIGHT), "真实人物开始本次蓄力")
	for frame in 4:
		body.advance(0.05, Vector3.ZERO, false)
		presentation.advance(0.05, 0.05)
	check(Engine.time_scale == 1.0 and silhouette(first.sprite) == 0.0, "起手保持原速与怪物原色")
	var slowed := false
	for frame in 6:
		var delta := 0.05 * Engine.time_scale
		body.advance(delta, Vector3.ZERO, false)
		presentation.advance(delta, 0.05)
		slowed = slowed or Engine.time_scale < 0.95
	check(slowed and body.charge_fraction > 0.999, "后半段进入慢放，真实半秒仍能达到满蓄")
	check(silhouette(first.sprite) == 0.0 and silhouette(second.sprite) == 0.0 and silhouette(far.sprite) == 0.0, "蓄力期间远近怪物均保留原色")
	check(silhouette(player.sprite) == 0.0 and first.health == health and first.global_transform == original, "蓄力表现不修改人物原色、怪物生命或移动")
	check(first.sprite.material_override == second.sprite.material_override, "附近怪物继续共享材质")
	var held_slow := true
	for frame in 100:
		var delta := 0.05 * Engine.time_scale
		body.advance(delta, Vector3.ZERO, false)
		presentation.advance(delta, 0.05)
		held_slow = held_slow and is_equal_approx(Engine.time_scale, presentation.charge_drama_slow_scale)
	check(held_slow and body.charging, "满蓄持续按住五秒始终保持慢放，不按固定时长恢复")
	check(silhouette(first.sprite) == 0.0 and silhouette(second.sprite) == 0.0, "满蓄长按也不使怪物变为剪影")
	first.sprite.set_instance_shader_parameter(&"wave_finish_silhouette", 0.7)
	check(body.release_charge() and Engine.time_scale == 1.0, "松手即时开始弹射，并恢复世界时间")
	presentation.advance(0.15, 0.15)
	check(silhouette(first.sprite) == 0.0 and is_equal_approx(body.get("charge_time_scale"), 1.0), "发射后保留怪物原色，移交普通飞行时钟")
	check(is_equal_approx(first.sprite.get_instance_shader_parameter(&"wave_finish_silhouette"), 0.7), "蓄力强调退去不清除其它独立剪影所有者")
	first.sprite.set_instance_shader_parameter(&"wave_finish_silhouette", 0.0)
	body.cancel(true)
	await reset()
	check(body.begin_charge(Vector3.RIGHT), "取消恢复用例重新蓄力")
	body.advance(0.4, Vector3.ZERO, false)
	presentation.advance(0.02, 0.02)
	presentation.set_wave_finish_override(true)
	check(Engine.time_scale == 1.0 and silhouette(first.sprite) == 0.0, "清波特写接管时立即释放时间和剪影")
	presentation.set_wave_finish_override(false)
	body.cancel(true)
	check(body.begin_charge(Vector3.RIGHT), "主动取消用例重新蓄力")
	body.advance(0.4, Vector3.ZERO, false)
	presentation.advance(0.05, 0.05)
	presentation.advance(0.05, 0.05)
	check(Engine.time_scale < 1.0, "取消前确实持有慢放")
	body.cancel(true)
	check(Engine.time_scale == 1.0 and body.charge_time_scale == 1.0, "主动取消立即归还世界与蓄力时钟")
	check(body.begin_charge(Vector3.RIGHT), "冻结恢复用例重新蓄力")
	body.advance(0.4, Vector3.ZERO, false)
	presentation.advance(0.04, 0.04)
	session.set_combat_frozen(true)
	check(Engine.time_scale == 1.0 and silhouette(first.sprite) == 0.0, "升级冻结清理额外慢放与强调")
	session.set_combat_frozen(false)
	presentation.reset()
	body.cancel(true)
	await reset()
	Engine.time_scale = 0.8
	check(body.begin_charge(Vector3.RIGHT), "外部已有慢动作时可开始蓄力")
	body.advance(0.32, Vector3.ZERO, false)
	presentation.advance(0.032, 0.04)
	presentation.advance(0.032, 0.04)
	var before := body.charge_fraction
	body.advance(0.05 * Engine.time_scale, Vector3.ZERO, false)
	check(is_equal_approx(body.charge_fraction - before, 0.05 * 0.8 / 0.5), "蓄力仅补偿自己引入的慢放，不抵消外部时间基准")
	presentation.reset()
	check(is_equal_approx(Engine.time_scale, 0.8), "退出本次慢放恢复外部原有时间比例")
	Engine.time_scale = 1.0
	body.cancel(true)
	check(body.begin_charge(Vector3.RIGHT), "管理界面用例重新蓄力")
	body.advance(0.4, Vector3.ZERO, false)
	presentation.advance(0.05, 0.05)
	presentation.advance(0.05, 0.05)
	var blocker := Node.new()
	world.add_child(blocker)
	blocker.add_to_group(&"gameplay_input_blockers")
	presentation.advance(0.05, 0.05)
	check(Engine.time_scale == 1.0, "管理界面占用输入时归还世界时间")
	blocker.free()
	presentation.advance(0.05, 0.05)
	presentation.advance(0.05, 0.05)
	check(Engine.time_scale < 1.0, "退出组件前确实持有慢放")
	for enemy in [first, second, far]:
		session._enemy_roster.remove(enemy)
		enemy.cancel()
	presentation.free()
	check(Engine.time_scale == 1.0 and body.charge_time_scale == 1.0, "组件退出立即归还世界时间，不遗留慢放")
	body.cancel(true)
	await settle(2)
	var state: SceneState = load("res://scenes/world/world.tscn").get_state()
	var configured := false
	for index in state.get_node_count():
		if state.get_node_name(index) != &"ChargePresentation": continue
		for property in state.get_node_property_count(index):
			if state.get_node_property_name(index, property) == &"charge_drama_enabled": configured = state.get_node_property_value(index, property)
	check(configured, "World 明确启用新反馈，共享默认不影响其它地图")
