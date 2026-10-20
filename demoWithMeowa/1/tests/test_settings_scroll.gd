extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func frames(count := 4) -> void:
	for frame in count: await process_frame

func mouse_button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1440, 900)
	var world: Node = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WorldMainMenu").show_on_world_start = false
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("GameSettingsUI").save_graphics_settings = false
	world.get_node("MapEffects/BGM").music_enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	root.add_child(world)
	current_scene = world
	await frames(12)
	var settings = world.get_node("GameSettingsUI")
	var rail := settings.get("_page_scrollbar") as VScrollBar
	check(rail != null, "设置页提供跟随斜切轨道移动的滚动条")
	if rail:
		settings.open_menu()
		settings.select_page(2)
		await frames()
		var source := (settings._scroll as ScrollContainer).get_v_scroll_bar()
		check(rail.visible and rail.max_value > rail.page, "长画质页显示可用轨道")
		rail.value = (rail.max_value - rail.page) * 0.6
		await frames()
		check(absf(settings._scroll.scroll_vertical - rail.value) < 1, "外部轨道驱动真实内容滚动")
		settings._scroll.scroll_vertical = 0
		await frames()
		check(is_zero_approx(rail.value), "程序滚动可同步外部滑块")
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.position = settings._panel.get_global_transform_with_canvas() * Vector2(10, 10)
		wheel.pressed = true
		var hover := InputEventMouseMotion.new()
		hover.position = wheel.position
		Input.parse_input_event(hover)
		Input.flush_buffered_events()
		await frames()
		Input.parse_input_event(wheel)
		Input.flush_buffered_events()
		wheel = wheel.duplicate()
		wheel.pressed = false
		Input.parse_input_event(wheel)
		Input.flush_buffered_events()
		await create_timer(0.25).timeout
		check(source.value > 0 and is_equal_approx(source.value, rail.value), "内容区鼠标滚轮同步倾斜轨道")
		source.value = 0
		for viewport_size in [Vector2i(1440, 900), Vector2i(1024, 640)]:
			root.content_scale_size = Vector2i.ZERO
			root.size = viewport_size
			await frames()
			var transform := rail.get_global_transform_with_canvas()
			# Start on the thumb rather than the native decrement arrow.
			var arrow_height := float(rail.get_theme_icon("decrement").get_height())
			var track_height := rail.size.y - arrow_height * 2
			var thumb_height := track_height * rail.page / (rail.max_value - rail.min_value)
			var start := transform * Vector2(rail.size.x * 0.5, arrow_height + thumb_height * 0.5)
			var end := transform * Vector2(rail.size.x * 0.5, rail.size.y - arrow_height - thumb_height * 0.5)
			check(end.x < start.x - 10 and end.y > start.y, "轨道按斜切方向下行并随视口缩放")
			check(root.get_visible_rect().has_point(start) and root.get_visible_rect().has_point(end), "轨道端点保持在视口内")
			mouse_button(start, true)
			await frames()
			var motion := InputEventMouseMotion.new()
			motion.position = end
			motion.relative = end - start
			motion.button_mask = MOUSE_BUTTON_MASK_LEFT
			Input.parse_input_event(motion)
			Input.flush_buffered_events()
			await frames()
			mouse_button(end, false)
			await frames()
			check(source.value > (source.max_value - source.page) * 0.8, "沿倾斜轨道拖动可滚到实际内容底部")
			source.value = 0
		settings.select_page(0)
		await frames()
		check(not rail.visible, "无需滚动的声音页隐藏外部轨道")
		settings.select_page(2)
		await frames()
		check(rail.visible and is_zero_approx(rail.value), "返回长页后恢复轨道并从页首开始")
		settings.close_menu()
		check(not paused and not rail.is_visible_in_tree(), "关闭设置隐藏轨道并保留世界运行")
	world.free()
	await frames()
	print("Settings scroll: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
