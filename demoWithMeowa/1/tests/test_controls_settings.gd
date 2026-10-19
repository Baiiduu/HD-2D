extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func frames(count := 3) -> void:
	for index in count: await process_frame

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

func run() -> void:
	var controls := root.get_node_or_null("GameControls")
	if not controls:
		check(false, "需要持久化的全局按键控制器和游戏内按键页")
		quit(1)
		return
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
	await frames(12)
	var settings := world.get_node("GameSettingsUI")
	var weather := world.get_node("MapEffects/Weather")
	var sample: SpawnVisualSample = world.get_node("VisualSample")
	var original: bool = weather.raining
	var style := sample.style
	key(KEY_G)
	await frames()
	check(weather.raining != original and settings._graphics_page.overrides.rain == weather.raining and sample.style == style, "G 单次切换雨天，复用保存入口并保留光影")
	key(KEY_G, true)
	await frames()
	check(weather.raining != original, "按住 G 的重复事件不会反复切换")
	key(KEY_P)
	await frames()
	check(settings.menu_open, "P 可打开设置")
	settings.select_page(4)
	var page = settings._controls_page
	check(page.visible and page.buttons.size() >= 16, "设置统一提供各类实际操作的按键入口")
	page.begin_capture(&"toggle_rain", 0)
	key(KEY_H)
	await frames()
	check(not page.is_capturing() and controls.model.bindings.toggle_rain == [KEY_H] and settings.menu_open, "改键即时完成，不关闭设置")
	check(weather.raining != original, "捕获新键不触发天气或游戏操作")
	page.begin_capture(&"toggle_rain", 0)
	key(KEY_R)
	await frames()
	check(page.is_capturing() and controls.model.bindings.toggle_rain == [KEY_H] and not page.status.text.is_empty(), "冲突按键不覆盖已有操作并明确提示")
	key(KEY_ESCAPE)
	await frames()
	check(not page.is_capturing() and settings.menu_open, "Esc 先取消改键，不关闭设置")
	key(KEY_ESCAPE, true)
	await frames()
	check(settings.menu_open, "按住 Esc 的重复事件不继续关闭设置")
	check(controls.rebind(&"cycle_style", 0, KEY_N).is_empty() and sample.style_key == KEY_N, "改键接入现有光影操作")
	check(controls.rebind(&"interact", 0, KEY_J).is_empty() and world.get_node("WavePrototype").interact_key == KEY_J, "交互改键同步当前地图的实际波次入口")
	check(controls.rebind(&"inventory", 0, KEY_I).is_empty() and world.get_node("LoadoutUI").toggle_key == KEY_I, "背包使用实际新按键")
	var camera: FollowCamera = world.get_node("Player").movement_camera
	var followed := camera.follow_enabled
	check(controls.rebind(&"camera_follow", 0, KEY_U).is_empty() and camera.follow_toggle_key == KEY_U and "U" in settings._camera_page.follow_toggle.text, "镜头跟随改键同步实际镜头及设置提示")
	key(KEY_ESCAPE)
	await frames()
	check(not settings.menu_open, "未捕获时 Esc 关闭设置")
	key(KEY_U)
	await frames()
	check(camera.follow_enabled != followed, "新的镜头跟随快捷键生效")
	key(KEY_G)
	await frames()
	check(weather.raining != original, "改键后旧雨天按键失效")
	key(KEY_H)
	await frames()
	check(weather.raining == original, "新雨天按键生效")
	key(KEY_N)
	await frames()
	check(sample.style == (style + 1) % 4 and weather.raining == original, "新光影按键循环且不改变天气")
	var blocker := Node.new()
	root.add_child(blocker)
	blocker.add_to_group(&"gameplay_input_blockers")
	key(KEY_H)
	await frames()
	check(weather.raining == original, "升级和管理输入占用时不响应天气快捷键")
	blocker.free()
	var edit := LineEdit.new()
	root.add_child(edit)
	edit.grab_focus()
	key(KEY_H)
	await frames()
	check(weather.raining == original, "文字输入不触发天气快捷键")
	edit.free()
	controls.reset_defaults()
	check(sample.style_key == KEY_R and world.get_node("LoadoutUI").toggle_key == KEY_TAB and controls.model.bindings.toggle_rain == [KEY_G], "恢复默认同步实际控制与全部设置显示")
	world.free()
	await frames()
	print("Controls settings: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
