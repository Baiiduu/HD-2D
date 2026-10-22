extends SceneTree

var checks := 0
var failures: Array[String] = []
var cues: Array[StringName] = []

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func frames(count := 3) -> void:
	for frame in count: await process_frame

func expect(cue: StringName, label: String) -> void:
	check(cues == [cue], label)
	cues.clear()

func press(button: BaseButton) -> void:
	button.button_down.emit()
	button.button_up.emit()
	button.pressed.emit()

func binding_checks(audio: Node) -> void:
	var scope := Control.new()
	root.add_child(scope)
	var button := Button.new()
	scope.add_child(button)
	var toggle := CheckBox.new()
	scope.add_child(toggle)
	var choice := OptionButton.new()
	choice.add_item("A")
	choice.add_item("B")
	scope.add_child(choice)
	var slider := HSlider.new()
	scope.add_child(slider)
	var spin := SpinBox.new()
	scope.add_child(spin)
	audio.bind_controls(scope)
	audio.bind_controls(scope)
	await frames()
	check(cues.is_empty(), "Binding and initializing a control tree is silent")
	press(button)
	expect(&"confirm", "Buttons share one confirmation even when bound twice")
	toggle.button_pressed = true
	choice.select(1)
	slider.value = 20
	spin.value = 5
	await frames()
	check(cues.is_empty(), "Programmatic toggle, dropdown and numeric synchronization is silent")
	press(toggle)
	expect(&"select", "Toggle interaction uses its own semantic action")
	choice.item_selected.emit(0)
	expect(&"select", "An actual dropdown selection has feedback")
	button.set_meta(&"ui_audio_action", &"close")
	press(button)
	expect(&"cancel", "A single widget can override its action without changing the global bank")
	button.set_meta(&"ui_audio_action", &"")
	press(button)
	check(cues.is_empty(), "An empty action opts a manually handled control out of automatic sound")
	button.remove_meta(&"ui_audio_action")
	button.disabled = true
	press(button)
	check(cues.is_empty(), "Disabled widgets cannot produce success sounds")
	button.disabled = false
	scope.hide()
	press(button)
	check(cues.is_empty(), "Hidden controls cannot produce interaction sounds")
	scope.show()
	var late := Button.new()
	scope.add_child(late)
	await frames()
	press(late)
	expect(&"confirm", "Controls added after page construction join the same binding scope")
	late.button_down.emit()
	late.hide()
	late.disabled = true
	late.pressed.emit()
	expect(&"confirm", "An accepted click keeps its sound when the action immediately hides or disables the button")
	slider.drag_ended.emit(true)
	expect(&"select", "Finishing a changed slider drag gives one adjustment cue")
	slider.drag_ended.emit(false)
	check(cues.is_empty(), "An unchanged slider drag is silent")
	var key := InputEventKey.new()
	key.keycode = KEY_UP
	key.pressed = true
	spin.gui_input.emit(key)
	spin.value += 1
	await frames()
	expect(&"select", "User-driven numeric input is audible after the value actually changes")
	var shared: Resource = audio.sounds
	audio.sounds = shared.duplicate(true)
	audio.sounds.actions[&"button"] = &"select"
	press(button)
	expect(&"select", "Reassigning a semantic action updates already-bound widgets")
	audio.sounds = shared
	check(audio._voices.size() == 6 and not audio.is_processing(), "Binding reuses the bounded audio pool without a per-frame scan")
	scope.free()
	await frames()
	audio._last_actions.clear()
	audio.action_intervals[&"adjust"] = 0.12
	check(audio.play_action(&"adjust") and not audio.play_action(&"adjust"), "Rapid adjustment feedback is limited independently of value changes")
	cues.clear()
	audio.action_intervals.clear()

func mouse(point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func native_input_checks(audio: Node) -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(800, 600)
	var scope := Control.new()
	scope.size = Vector2(600, 400)
	root.add_child(scope)
	var slider := HSlider.new()
	slider.position = Vector2(32, 32)
	slider.size = Vector2(300, 32)
	scope.add_child(slider)
	var spin := SpinBox.new()
	spin.position = Vector2(32, 100)
	spin.size = Vector2(180, 40)
	scope.add_child(spin)
	audio.bind_controls(scope)
	await frames()
	cues.clear()
	mouse(slider.global_position + Vector2(220, 16), true)
	mouse(slider.global_position + Vector2(220, 16), false)
	await frames()
	check(slider.value > 50, "Native viewport input changes the actual slider")
	expect(&"select", "Native slider click and release produce one adjustment")
	mouse(spin.global_position + Vector2(spin.size.x - 7, 7), true)
	mouse(spin.global_position + Vector2(spin.size.x - 7, 7), false)
	await frames()
	check(spin.value > 0, "Native input reaches the numeric stepper")
	expect(&"select", "Native numeric arrow buttons produce feedback")
	spin.get_line_edit().grab_focus()
	await frames()
	spin.get_line_edit().text = "7"
	key(KEY_ENTER)
	await frames()
	check(spin.value == 7, "Submitting native numeric text commits its value")
	expect(&"select", "Numeric text submission produces one feedback cue")
	var button := Button.new()
	button.position = Vector2(32, 180)
	button.size = Vector2(200, 40)
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	button.pressed.connect(func(): button.disabled = true; button.hide())
	scope.add_child(button)
	await frames()
	mouse(button.global_position + Vector2(20, 20), true)
	mouse(button.global_position + Vector2(20, 20), false)
	await frames()
	expect(&"confirm", "Native press-mode buttons keep one sound when their action immediately hides them")
	scope.free()
	await frames()

func world_checks() -> void:
	var world: Node = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WorldMainMenu").show_on_world_start = false
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("GameSettingsUI").save_graphics_settings = false
	world.get_node("MapEffects/BGM").music_enabled = false
	root.add_child(world)
	current_scene = world
	await frames(12)
	var loadout = world.get_node("LoadoutUI")
	check("player_access_enabled" in loadout and not loadout.get("player_access_enabled"), "World explicitly closes the player-facing character and backpack interface")
	loadout.open_menu()
	loadout._open_skill_from_hud("")
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = loadout.toggle_key
	loadout._input(event)
	check(not loadout.menu_open and not loadout.is_in_group(&"gameplay_input_blockers"), "Direct, HUD and saved hotkey entry cannot bypass backpack access")
	check(not loadout._bottom_toggle.visible and not loadout._item_bar.visible, "The hidden backpack has no quickbar expansion entry")
	var active_slot: int = loadout.state.active_quick_slot
	key(KEY_2 if active_slot != 1 else KEY_3)
	await frames()
	check(loadout.state.active_quick_slot == active_slot, "Hidden item shortcuts do not consume gameplay input or alter the backpack")
	check(world.get_node("Player").character_state == loadout.state and loadout.state != null, "Closing the interface retains character data and combat growth")
	var settings = world.get_node("GameSettingsUI")
	check(not settings._controls_page.buttons.has(&"inventory"), "In-game key settings omit the closed backpack action")
	var audio = settings.get("_ui_audio")
	check(audio != null, "Settings owns a common UI audio endpoint")
	if audio:
		audio.repeat_interval = 0.0
		audio.action_intervals.clear()
		audio.cue_played.connect(func(cue): cues.append(cue))
		settings._graphics_page.sync_controls()
		settings._camera_page.sync_controls()
		settings._controls_page.sync_controls()
		check(cues.is_empty(), "Refreshing settings remains silent")
		settings.open_menu()
		expect(&"journal_open", "Opening settings has one opening sound")
		settings.open_menu()
		check(cues.is_empty(), "Repeated open requests do not replay feedback")
		press(settings._tabs[3])
		expect(&"page_turn", "A changed settings tab has one page sound")
		press(settings._tabs[3])
		check(cues.is_empty(), "The active tab does not replay a page change")
		settings._camera_page.follow_toggle.set_pressed_no_signal(false)
		press(settings._camera_page.follow_toggle)
		expect(&"select", "Embedded settings controls share the root audio scope")
		settings.select_page(4)
		cues.clear()
		var page = settings._controls_page
		page.begin_capture(&"toggle_rain", 0)
		event.keycode = KEY_R
		event.physical_keycode = KEY_R
		page._input(event)
		expect(&"error", "An invalid key assignment uses failure feedback")
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		page._input(event)
		expect(&"cancel", "Esc cancels key capture with one cancellation sound")
		check(settings.menu_open, "Cancelling key capture keeps settings open")
		settings.close_menu()
		expect(&"cancel", "Closing settings has one return sound")
	world.free()
	await frames()
	var menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	menu.auto_prepare_world = false
	menu.save_preferences = false
	menu.audio_enabled = false
	root.add_child(menu)
	await frames(6)
	check(not menu._controls_page.buttons.has(&"inventory"), "Main-menu key settings also hide the unavailable backpack")
	check(menu._ui_audio.has_method("bind_controls"), "Main-menu settings reuse the same audio architecture")
	menu.free()
	await frames()

func run() -> void:
	var audio = load("res://scenes/audio/ui_audio.tscn").instantiate()
	root.add_child(audio)
	check(audio.has_method("bind_controls") and audio.has_method("play_action"), "UI audio needs shared semantic actions and reusable control binding")
	if failures.is_empty():
		audio.repeat_interval = 0.0
		audio.action_intervals.clear()
		audio.cue_played.connect(func(cue): cues.append(cue))
		await binding_checks(audio)
		await native_input_checks(audio)
		audio.free()
		await world_checks()
	else: audio.free()
	await frames()
	print(JSON.stringify({"suite":"ui_feedback", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
