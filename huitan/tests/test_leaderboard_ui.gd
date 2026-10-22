extends SceneTree
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func key(code: Key, echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	event.echo = false
	Input.parse_input_event(event)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var client := root.get_node("LeaderboardClient")
	check(not client.save_enabled and not client.network_enabled, "普通无界面测试不访问线上或改写玩家身份")
	var page = load("res://scripts/ui/leaderboard_page.gd").new()
	root.add_child(page)
	await process_frame
	check(page.pending.text.contains("自动"), "排行榜说明结算自动上传")
	var buttons: Array = page.find_children("*", "Button", true, false)
	check(page._enable.disabled and not page._upload_choice.button_pressed and not page._publish_choice.button_pressed, "上传与公开默认不勾选，不能直接启用")
	check(buttons.filter(func(button): return button.text in ["提交成绩", "保存成绩"]).is_empty(), "排行榜没有手动提交或保存成绩按钮")
	check(buttons.filter(func(button): return button.text == "隐私政策").is_empty(), "排行榜不再提供已撤下的隐私政策界面")
	client.set_upload_consent(true, true)
	client.begin_run()
	client.capture_run({"total": 12, "active": false, "simulation": false, "eligible_for_submission": true})
	check("12" in page.pending.text and "自动" in page.pending.text, "结算更新自动上传状态")
	client.busy = true
	client.changed.emit()
	check(page._refresh.disabled, "查询进行时禁用重复刷新")
	client.busy = false
	var world: Node = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("WorldMainMenu").show_on_world_start = false
	world.get_node("GameSettingsUI").save_graphics_settings = false
	world.get_node("MapEffects/BGM").music_enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	root.add_child(world)
	current_scene = world
	for index in 12: await process_frame
	var settings = world.get_node("GameSettingsUI")
	check("排行榜" in settings.PAGE_NAMES and settings._tabs.size() == settings.PAGE_NAMES.size(), "游戏内排行榜保留在完整设置导航")
	if not "排行榜" in settings.PAGE_NAMES:
		world.queue_free()
		page.queue_free()
		for index in 4: await process_frame
		print("Leaderboard UI: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	settings.open_menu()
	settings._tabs[5].pressed.emit()
	check(settings.menu_open and paused and settings._leaderboard_page.is_visible_in_tree() and settings._page_heading.text == "排行榜" and settings.is_in_group(&"gameplay_input_blockers"), "排行榜在设置暂停期间保持可用")
	check(settings.get_children().filter(func(child): return child is Button and child.text == "排行榜").is_empty(), "游戏画面不再显示独立排行榜按钮")
	key(KEY_ESCAPE)
	await process_frame
	check(not settings.menu_open and not paused and get_first_node_in_group(&"gameplay_input_blockers") == null, "Esc 从排行榜页关闭设置并恢复游戏，不同时重新打开")
	settings.open_menu()
	settings.select_page(4)
	settings._controls_page.begin_capture(&"toggle_rain", 0)
	key(KEY_ESCAPE)
	await process_frame
	check(settings.menu_open and not settings._controls_page.is_capturing(), "改键中的 Esc 只取消捕获")
	key(KEY_ESCAPE)
	await process_frame
	check(not settings.menu_open, "再次 Esc 才关闭设置")
	var wave: WavePrototype = world.get_node("WavePrototype")
	wave._set_phase(WavePrototype.Phase.REST)
	key(KEY_ESCAPE)
	await process_frame
	check(settings.menu_open and wave.phase == WavePrototype.Phase.REST, "挑战中 Esc 打开设置，不触发撤退结算")
	key(KEY_ESCAPE)
	await process_frame
	check(not settings.menu_open and wave.phase == WavePrototype.Phase.REST, "关闭设置不会把同一次 Esc 传给挑战撤退")
	var score: RunScore = wave.get_node("RunScore")
	score.state.begin(100, score.rules)
	client.begin_run()
	score.state.record_kill(900001, 23, false)
	wave.retreat()
	check(client.model.pending.total == 23 and not settings.menu_open, "真实结算信号自动捕获成绩，不强制弹出设置或排行榜")
	key(KEY_ESCAPE)
	await process_frame
	check(settings.menu_open and wave.phase == WavePrototype.Phase.RESULT, "结算中 Esc 打开设置，不直接返回或重置本局")
	settings.select_page(5)
	check(settings._leaderboard_page.is_visible_in_tree() and wave.phase == WavePrototype.Phase.RESULT, "结算仍可在设置中查看排行榜")
	key(wave.retry_key)
	await process_frame
	check(settings.menu_open and wave.phase == WavePrototype.Phase.RESULT, "查看排行榜时重试按键不穿透到本局")
	var blocker := Node.new()
	root.add_child(blocker)
	blocker.add_to_group(&"gameplay_input_blockers")
	settings.close_menu()
	key(KEY_ESCAPE)
	await process_frame
	check(not settings.menu_open and wave.phase == WavePrototype.Phase.RESULT, "结算已有其它弹窗时 Esc 不抢占输入或重置结算")
	blocker.free()
	check(world.get_node("WavePrototype/RunScore").online_demo_enabled, "World 明确启用联网结算快照")
	var hud: WaveHUD = wave.get_node("WaveHUD")
	check(hud._root.find_children("*", "Button", true, false).is_empty(), "结算 HUD 不再出现手动提交或查看排行的弹出入口")
	world.queue_free()
	page.queue_free()
	for index in 4: await process_frame
	print("Leaderboard UI: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
