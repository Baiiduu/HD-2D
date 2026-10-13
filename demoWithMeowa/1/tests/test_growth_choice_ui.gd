extends SceneTree

class WorldProbe extends Node:
	var frames := 0
	var physics_frames := 0
	var unhandled := 0
	func _process(_delta: float) -> void: frames += 1
	func _physics_process(_delta: float) -> void: physics_frames += 1
	func _unhandled_key_input(_event: InputEvent) -> void: unhandled += 1

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func option(id: StringName, enabled := true) -> GrowthChoiceOption:
	var value := GrowthChoiceOption.new()
	value.id = id
	value.enabled = enabled
	return value

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func click(control: Control) -> void:
	var point := control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)

func run() -> void:
	var world := WorldProbe.new()
	root.add_child(world)
	var loadout: LoadoutUI = load("res://scenes/ui/loadout_ui.tscn").instantiate()
	loadout.save_enabled = false
	loadout.motion_enabled = false
	world.add_child(loadout)
	var ui: GrowthChoiceUI = load("res://scenes/ui/growth_choice_ui.tscn").instantiate()
	ui.open_duration = 0.0
	ui.hover_duration = 0.0
	world.add_child(ui)
	var confirmed: Array[StringName] = []
	var cancellation: Array[bool] = []
	ui.choice_confirmed.connect(func(id: StringName): confirmed.append(id))
	ui.cancelled.connect(func(): cancellation.append(true))
	await process_frame
	check(not ui.is_open and not ui.get_node("Root").visible, "Production component starts closed")
	check(not ui.present_choices([]), "Empty candidate list is rejected")
	check(not ui.present_choices([option(&"")]), "Empty identifiers are rejected")
	check(not ui.present_choices([option(&"same"), option(&"same")]), "Duplicate identifiers are rejected")
	check(not ui.present_choices([option(&"disabled", false)]), "An entirely unavailable list does not open")
	var a := option(&"a")
	var b := option(&"b", false)
	var c := option(&"c")
	check(ui.present_choices([a, b, c]), "Data-driven three-option screen opens")
	check(ui.get_selected_option() == a, "First available candidate is selected")
	check(ui._cards.size() == 3, "Card count follows supplied data")
	ui.title = "等级 123 · 成长选择"
	var header: Label = ui.get_node("Root/Content/Header/Title")
	check(header.get_theme_font("font").get_string_size(header.text, HORIZONTAL_ALIGNMENT_LEFT, -1, ui.title_font_size).x < header.size.x, "Level titles fit without ellipsis or overlapping ornaments")
	check(not paused and get_first_node_in_group(&"gameplay_input_blockers") == ui, "UI owns player input without pausing")
	for card in ui._cards:
		check(not card.get_node("Title").visible and not card.get_node("Description").visible and not card.get_node("IconSlot/Icon").visible, "Empty candidate data introduces no ability content")
	check(not ui.select_option(&"b") and not ui.select_option(&"missing"), "Unavailable and unknown candidates cannot be selected")
	key(KEY_RIGHT)
	check(ui.get_selected_option() == c, "Keyboard skips unavailable candidates")
	key(KEY_RIGHT)
	check(ui.get_selected_option() == a, "Keyboard wraps to the first candidate")
	click(ui._cards[2])
	check(ui.get_selected_option() == c, "Actual mouse input selects a separate card")
	key(KEY_TAB)
	check(not loadout.menu_open, "Tab does not open the backpack behind the choice UI")
	loadout.open_menu()
	check(not loadout.menu_open, "Programmatic backpack opening also respects UI ownership")
	var old_unhandled := world.unhandled
	key(KEY_D)
	var old_frames := world.frames
	var old_physics := world.physics_frames
	await create_timer(0.15).timeout
	check(world.unhandled == old_unhandled, "Gameplay keys are consumed")
	check(world.frames > old_frames and world.physics_frames > old_physics, "World process and physics continue")
	check(not ui.present_choices([option(&"invalid"), option(&"invalid")]) and ui.get_selected_option() == c, "Rejected replacement leaves the pending selection intact")
	ui.card_width = 320.0
	check(ui._cards[0].size.x == 320.0, "Layout parameters update live")
	ui.background_opacity = 0.35
	check(is_equal_approx(float(ui._cards[0].get_node("Frame").material.get_shader_parameter("background_opacity")), 0.35), "Interior transparency updates independently")
	root.size = Vector2i(640, 400)
	await process_frame
	var rect := ui._content.get_global_rect()
	check(root.get_visible_rect().encloses(rect), "Small window fits the complete interface")
	check(is_equal_approx(ui._content.scale.x, ui._content.scale.y), "Window fit preserves artwork proportions")
	click(ui._confirm)
	check(confirmed == [&"c"] and not ui.is_open, "Mouse confirmation emits the selected stable identifier")
	ui.confirm_selection()
	key(KEY_ENTER)
	check(confirmed.size() == 1, "Repeated confirmation cannot apply the same choice twice")
	check(get_first_node_in_group(&"gameplay_input_blockers") == null and not paused, "Confirmation releases only UI input ownership")
	check(ui.present_choices([a, c]), "UI can reopen for another round")
	ui.allow_cancel = false
	key(KEY_ESCAPE)
	check(ui.is_open and cancellation.is_empty(), "Caller can disable cancellation")
	ui.allow_cancel = true
	key(KEY_ESCAPE)
	check(not ui.is_open and cancellation.size() == 1 and confirmed.size() == 1, "Cancellation emits no growth result")
	loadout.open_menu()
	check(not ui.present_choices([a]), "Another open panel prevents overlapping choice UI")
	loadout.close_menu()
	await create_timer(0.1).timeout
	paused = true
	check(ui.present_choices([a]), "UI can operate during an externally requested pause")
	key(KEY_ENTER)
	check(paused and confirmed == [&"c", &"a"], "Keyboard confirmation preserves an external pause")
	paused = false
	ui.present_choices([a])
	world.remove_child(ui)
	check(get_first_node_in_group(&"gameplay_input_blockers") == null, "Removing an open component leaves no stale input lock")
	ui.free()
	world.free()
	# 给音频混音线程一次清理窗口，避免立即退出留下尚未释放的播放资源。
	await create_timer(0.1).timeout
	print("Growth choice UI: %d checks, %d failures" % [checks, failures.size()])
	quit.call_deferred(0 if failures.is_empty() else 1)
