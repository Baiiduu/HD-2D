extends "res://tests/test_crowd_deflection.gd"

const DEBUG_UI = preload("res://scripts/ui/orbit_debug_ui.gd")

func path_checks() -> void:
	terrain.data.resize(Vector2i(-16, -16), Vector2i(32, 32))
	player.ricochet_rules = load("res://data/player/body_ricochet.tres").duplicate()
	player.ricochet_rules.flight_deceleration = 4.0
	player.sword.rules.enabled = false
	group(Vector3(2.6, 0, 0), 5, 5)
	var debug = DEBUG_UI.new()
	debug.player = player
	debug.session = session
	world.add_child(debug)
	check(not debug.debug_enabled and not debug.is_processing() and not body.orbit_debug_enabled, "调试默认关闭且没有逐帧处理")
	debug.set_debug_enabled(true)
	check(body.orbit_debug_enabled and debug.is_processing() and not debug._panel.visible and debug._overlay.visible and debug._details_button.visible, "开启默认只显示线路和小入口，读数面板保持收起")
	debug.set_details_visible(true)
	check(debug._panel.visible, "按需展开读数")
	var panel_position: Vector2 = debug._panel.position
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	debug._drag_input(press)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(-140, 20)
	debug._drag_input(motion)
	press.pressed = false
	debug._drag_input(press)
	check(debug._panel.position.x < panel_position.x and not debug._dragging, "可拖动标题把面板移开，释放鼠标结束拖动")
	debug.set_details_visible(false)
	check(not debug._panel.visible and body.orbit_debug_enabled, "收起面板保持调试运行")
	check(get_first_node_in_group(&"gameplay_input_blockers") == null and not session.combat_frozen, "调试视图不阻断输入或冻结战斗")
	await predict()
	check(body.release_charge(), "调试开启时正常发射")
	for frame in 200:
		body.advance(1.0 / 120.0, Vector3.ZERO, false)
		if body.orbiting: break
	debug._process(0.0)
	check(body.orbiting and body._crowd.debug_enabled, "从首个实际接触开始捕获诊断")
	check(debug.trail.size() > 2 and debug.snapshot.orbiting, "轨迹读取真实移动段，状态来自实际环绕")
	var recorded: int = debug.trail.size()
	debug.set_details_visible(true)
	debug.set_details_visible(false)
	check(debug.trail.size() == recorded and body.orbiting, "展开或收起读数不清空轨迹或打断环绕")
	check(debug.snapshot.outline.size() > 3 and debug.snapshot.planned == body._crowd._points.slice(body._crowd._cursor), "安全外沿和待走路线与实际几何完全一致")
	check(debug.snapshot.members.size() == body._crowd._orbit_members.size() and debug.snapshot.replans == 1, "成员和规划计数读取已捕获群")
	check(is_equal_approx(debug.snapshot.contact, 1.05) and is_equal_approx(debug.snapshot.capture, 1.3) and debug.snapshot.storm == 0.0, "范围区分普通接触与提前捕获，未学奔雷不画伪范围")
	var speed := body.flight_speed
	var heading := body.direction
	var cursor := body._crowd._cursor
	var points := body._crowd._points.duplicate()
	var health := session.enemies[0].health
	for count in 10: debug._read_snapshot()
	check(body.flight_speed == speed and body.direction == heading and body._crowd._cursor == cursor and body._crowd._points == points and session.enemies[0].health == health, "诊断读取不改路线进度、速度、方向或伤害")
	debug._lock.button_pressed = true
	var locked_position: Vector3 = debug.snapshot.position
	var trail_count: int = debug.trail.size()
	body.advance(0.1, Vector3.ZERO, false)
	debug._process(0.0)
	check(debug.locked and debug.snapshot.position == locked_position and debug.trail.size() == trail_count and player.position != locked_position, "锁定仅保留记录，真实人物继续运动")
	debug._lock.button_pressed = false
	debug._process(0.0)
	check(not debug.locked and debug.snapshot.position == player.position and debug.trail.is_empty(), "解锁从当前位置重新记录，不拼接旧轨迹")
	check(body.detach_from_crowd(), "非阻塞调试中仍能主动脱离")
	debug._process(0.0)
	check(debug.snapshot.detached and "右键" in debug.snapshot.reason, "界面显示主动脱离及本次停止捕获的原因")
	for frame in 600:
		if not body.flying: break
		body.advance(1.0 / 120.0, Vector3.ZERO, false)
	debug._process(0.0)
	check(not body.flying and debug.snapshot.end == "余速耗尽", "结束时保存最后一段路线与真实结束原因")
	var ended_position: Vector3 = debug.snapshot.position
	player.position += Vector3.FORWARD
	debug._process(0.0)
	check(debug.snapshot.position == ended_position, "落地后走路不把上一发路线错误连接到人物当前位置")
	debug.set_debug_enabled(false)
	check(not body.orbit_debug_enabled and debug.trail.is_empty() and debug.snapshot.is_empty() and not debug.is_processing(), "关闭立即清理记录并停止绘制与采集")
	await predict()
	fly(1.0 / 120.0)
	var baseline := player.position
	var baseline_contacts := body.crowd_deflection_count
	await predict()
	debug.set_debug_enabled(true)
	fly(1.0 / 120.0)
	check(player.position.is_equal_approx(baseline) and body.crowd_deflection_count == baseline_contacts, "开关调试不改变整次飞行轨迹与接群次数")
	for index in range(debug.MAX_SEGMENTS + 4):
		debug._travelled(Vector3.RIGHT * index, Vector3.RIGHT * (index + 1), Vector3.RIGHT, 0.01)
	check(debug.trail.size() == debug.MAX_SEGMENTS * 2, "长续航轨迹数量有界，不随持续试玩无限增长")
	debug.free()
	await clear()

func target_checks() -> void:
	pass
