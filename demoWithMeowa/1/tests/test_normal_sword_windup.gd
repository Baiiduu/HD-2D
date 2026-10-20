extends "res://tests/test_player_sword.gd"

func keyboard(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_D
	event.physical_keycode = KEY_D
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func attack_button(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tick(seconds := 0.02) -> void:
	player._physics_process(seconds)
	sword._physics_process(seconds)
	player._process(seconds)

func locked(seconds := 0.0) -> bool:
	return sword.call("blocks_normal_movement", seconds)

func manual_checks() -> void:
	check(sword.has_method("blocks_normal_movement"), "普通攻击需要与真实起手、扫刃共用的移动约束")
	if not sword.has_method("blocks_normal_movement"): return
	sword.rules = load("res://data/combat/scenes/world/player/basic_sword.tres").duplicate()
	sword.rules.audio_enabled = false
	player.sword_rules = sword.rules
	player.action_visuals.normal_attack = load("res://data/combat/scenes/world/player/character_attack.tres")
	player.set_process(false)
	check(sword.rules.get("normal_stationary_enabled") and is_equal_approx(sword.rules.get("normal_windup_seconds"), 0.10), "World 明确启用站定攻击与独立 0.10 秒前摇")
	check(not PlayerSwordRules.new().get("normal_stationary_enabled") and not load("res://data/combat/scenes/city/player/basic_sword.tres").get("normal_stationary_enabled"), "共享默认与 City 保留原移动攻击配置")
	await reset()
	var mob := enemy(Vector3(1, 0, 0))
	keyboard(true)
	player._physics_process(0.02)
	check(player.velocity.x > 0.0, "角色原本正在持续按键行走")
	var start := player.global_position
	check(sword.request_manual(Vector3.RIGHT) and locked(), "攻击请求当帧即进入移动约束，不等待下个剑术更新")
	tick()
	check(player.global_position.is_equal_approx(start) and is_zero_approx(player.velocity.x) and is_zero_approx(player.velocity.z), "起手同帧清零水平移动，角色与刀光起点不再漂移")
	check(is_equal_approx(sword._settings.windup_seconds, 0.10) and is_equal_approx(player.action_animator._attack_duration, sword._settings.duration()), "人物动画与真实普攻使用同一完整动作快照")
	for frame in 3: tick()
	check(mob.health == 200.0 and not sword._effect.visible and locked(), "完整前摇只有人物起手，尚不显示刀光或结算伤害")
	for frame in 6:
		tick()
		check(player.global_position.is_equal_approx(start), "真实扫刃期间保持水平站定")
	check(mob.health == 190.0 and damage_events.size() == 1, "前摇后真实扇区只造成一次原有十点伤害")
	check(not locked(), "扫刃结束即释放移动，不等待收刀或余迹消散")
	tick()
	check(player.global_position.x > start.x + 0.001 and player.action_animator._attack == &"normal_attack", "保持方向键即可在收刀动画期间继续行走")
	check(not sword._tail_pool.is_empty() and sword._tail_pool[0].origin.distance_to(session._path.ground_position(start)) < 0.001, "收刀余迹留在真实扫击位置，与仍可造成伤害的刀锋分开")
	keyboard(false)
	await reset()
	keyboard(true)
	attack_button(true)
	sword._tap = false
	sword._since_strike = sword.get_stats(false).interval - 0.005
	start = player.position
	tick()
	check(sword.swinging and player.position.is_equal_approx(start), "按住连击在冷却跨过边界的同帧站定，不额外走出一步")
	attack_button(false)
	keyboard(false)
	await reset()
	sword.request_manual(Vector3.RIGHT)
	tick()
	var clock := sword._since_strike
	player.skill_manager.request_dash(Vector3.RIGHT)
	tick(0.01)
	check(player._blink.active and not sword.swinging and not locked(), "Shift 闪身可以立即打断普攻起手并释放站定")
	check(sword._since_strike < clock + 0.02 and sword._since_strike < sword.get_stats(false).interval and player.action_animator._attack != &"normal_attack", "闪身打断保留剩余攻击冷却，清除普攻显示而不补发旧刀")
	player._blink.cancel()
	await reset()
	sword.request_manual(Vector3.RIGHT)
	tick()
	check(player.body_ricochet.begin_charge(Vector3.RIGHT), "普攻起手允许右键蓄力接管")
	keyboard(true)
	start = player.position
	tick()
	check(not sword.swinging and not locked() and player.body_ricochet.charging and player.position.x > start.x, "蓄力接管撤销旧普攻且保留边走边蓄力")
	keyboard(false)
	await reset()
	sword._begin(Vector3.RIGHT, true)
	keyboard(true)
	start = player.position
	player._physics_process(0.02)
	check(not locked() and player.position.x > start.x and is_equal_approx(sword._settings.windup_seconds, sword.rules.windup_seconds), "弹射挥剑沿用原前摇，站定规则不限制飞行攻击")
	keyboard(false)
	await reset()
	sword.rules.set("normal_stationary_enabled", false)
	sword.request_manual(Vector3.RIGHT)
	keyboard(true)
	tick()
	check(not locked() and player.velocity.x > 0.0 and is_equal_approx(sword._settings.windup_seconds, 0.05), "关闭独立开关恢复原移动攻击与原起手")
	keyboard(false)
	sword.rules.set("normal_stationary_enabled", true)
	await reset()
	for rank in 5: session.combat_modifiers.apply_buff(load("res://data/growth/cooldown.tres"))
	sword.request_manual(Vector3.RIGHT)
	sword._physics_process(0.01)
	check(sword._settings.windup_seconds < 0.10 and is_equal_approx(sword._settings.windup_seconds / sword._settings.sweep_seconds, 1.0), "攻速同步缩短普攻前摇与扫刃，保留新的阶段比例")
	var age := sword._age
	session.set_combat_frozen(true)
	sword._physics_process(0.5)
	check(sword._age == age and locked(), "升级冻结保持动作进度与站定阶段")
	session.set_combat_frozen(false)
	sword.cancel()
	check(not locked(), "取消与重试不遗留移动锁")
	var entries: Array[Dictionary] = load("res://addons/parameter_hub/catalog.gd").new().collect(player)
	for property in ["normal_stationary_enabled", "normal_windup_seconds"]:
		check(entries.any(func(item): return item.property == property and item.common and item.category == "人物" and item.label != property), "参数总览提供中文普攻节奏入口：" + property)

func attack_speed_checks() -> void:
	pass

func flight_checks() -> void:
	pass

func freeze_checks() -> void:
	pass

func input_and_art_checks() -> void:
	pass

func score_checks() -> void:
	pass
