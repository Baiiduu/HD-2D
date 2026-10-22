extends SceneTree

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func settle() -> void:
	for frame in 5:
		await process_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)

func run() -> void:
	root.size = Vector2i(1280, 800)
	var ui: LoadoutUI = load("res://scenes/ui/loadout_ui.tscn").instantiate()
	ui.save_enabled = false
	# 技能栏交互独立于书本过渡；动效另由 test_journal_effects 验证。
	ui.motion_enabled = false
	root.add_child(ui)
	await settle()
	var hud := ui._hud
	assert(hud.get_child_count() == 4 and not hud.show_skill_icons)
	assert(hud.position.x == 24.0 and root.get_visible_rect().size.y - hud.position.y - hud.size.y == 24.0)
	assert(hud.size == Vector2(274, 64), "Only the four compact slots belong in the HUD")
	for button: Button in hud.get_children():
		assert(button.text.is_empty() and not button.has_node("Icon"))
		assert(button.get_node("Frame").texture == hud.slot_texture)
	var image := hud.slot_texture.get_image()
	assert(image.get_pixel(0, 0).a < 0.02)
	var center := image.get_pixel(image.get_width() / 2, image.get_height() / 2)
	assert(center.a > 0.0 and center.a < 1.0, "Extracted well must retain real translucency")
	var saved_state := ui.state.export_state()
	hud.glow_strength = 0.0
	hud.background_opacity = 0.0
	for button: Button in hud.get_children():
		var material: ShaderMaterial = button.get_node("Frame").material
		assert(material.get_shader_parameter("glow_strength") == 0.0)
		assert(material.get_shader_parameter("background_opacity") == 0.0)
	hud.slot_size = 56.0
	hud.slot_spacing = 4
	hud.screen_margin = Vector2(32, 20)
	await settle()
	assert(hud.size == Vector2(236, 56) and hud.position.x == 32.0)
	assert(root.get_visible_rect().size.y - hud.position.y - hud.size.y == 20.0)
	hud.show_skill_icons = true
	await settle()
	assert(hud.get_child(0).has_node("Icon") and hud.get_child(1).has_node("Icon"))
	hud.show_skill_icons = false
	await settle()
	assert(not hud.get_child(0).has_node("Icon") and ui.state.export_state() == saved_state)
	key(KEY_TAB)
	await settle()
	assert(ui.menu_open and not paused and not hud.visible)
	assert(ui.is_in_group(&"gameplay_input_blockers"))
	key(KEY_TAB)
	await settle()
	assert(not ui.menu_open and not paused and hud.visible)
	assert(not ui.is_in_group(&"gameplay_input_blockers"))
	hud.get_child(0).pressed.emit()
	await settle()
	assert(ui.menu_open and ui.current_page == 1 and ui.selected_skill == "fire")
	key(KEY_ESCAPE)
	await settle()
	assert(not ui.menu_open and not paused and hud.visible)
	ui.skill_slot_count = 8
	hud.slot_size = 96.0
	hud.slot_spacing = 24
	root.size = Vector2i(640, 400)
	root.content_scale_size = Vector2i(640, 400)
	await settle()
	assert(hud.get_child_count() == 8 and hud.scale.x < 1.0)
	assert(hud.position.x >= 0.0 and hud.position.y >= 0.0)
	assert(hud.position.x + hud.size.x * hud.scale.x <= 640.1)
	assert(hud.position.y + hud.size.y * hud.scale.y <= 400.1)
	ui.free()
	await settle()
	# Dummy 驱动仍异步释放 WAV 播放实例，退出前等待声音线程完成回收。
	await create_timer(0.1).timeout
	print("PASS: empty Meowa slots, no menu button/icons, lower-left layout, live size/margin/glow parameters, unchanged assignments, Tab/ESC, click details and narrow-window 8-slot fit")
	quit()
