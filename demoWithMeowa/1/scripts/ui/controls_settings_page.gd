extends VBoxContainer

var buttons := {}
var status: Label
var _action: StringName = &""
var _slot := 0
var _controls: Node
var audio: UIAudio

func configure(settings_theme: Theme) -> void:
	_controls = get_node("/root/GameControls")
	theme = settings_theme
	add_theme_constant_override("separation", 12)
	var hint := Label.new()
	hint.text = "点击按键修改 · Esc 取消"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	var group := ""
	for spec in _controls.model.SPECS:
		if not _controls.action_available(spec.id): continue
		if spec.group != group:
			group = spec.group
			var heading := Label.new()
			heading.text = group
			heading.add_theme_font_size_override("font_size", 21)
			add_child(heading)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		add_child(row)
		var label := Label.new()
		label.text = spec.label
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		buttons[spec.id] = []
		for slot in spec.keys.size():
			var button := Button.new()
			button.custom_minimum_size = Vector2(118, 36)
			button.focus_mode = Control.FOCUS_NONE
			button.set_meta(&"ui_audio_action", &"choice")
			button.pressed.connect(begin_capture.bind(spec.id, slot))
			row.add_child(button)
			buttons[spec.id].append(button)
	var fixed := Label.new()
	fixed.text = "Esc 打开／关闭设置（改键时取消） · Enter 确认 · 1–9 选择"
	fixed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(fixed)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	var reset := Button.new()
	reset.text = "恢复默认"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(func(): cancel_capture(); _controls.reset_defaults(); status.text = "已恢复默认按键。")
	add_child(reset)
	_controls.changed.connect(sync_controls)
	visibility_changed.connect(func():
		if not is_visible_in_tree(): cancel_capture())
	status.text = _controls.last_error
	sync_controls()

func sync_controls() -> void:
	for action in buttons:
		for slot in buttons[action].size():
			buttons[action][slot].text = "按下新按键…" if action == _action and slot == _slot else _controls.model.label_for(_controls.model.bindings[action][slot])

func is_capturing() -> bool:
	return _action != &""

func begin_capture(action: StringName, slot: int) -> void:
	if not buttons.has(action): return
	_action = action
	_slot = slot
	status.text = "请按下新按键；Esc 取消。"
	sync_controls()

func cancel_capture(audible := false) -> void:
	var waiting := is_capturing()
	_action = &""
	sync_controls()
	if waiting and is_instance_valid(status): status.text = "已取消改键。"
	if waiting and audible and audio: audio.play_action(&"close")

func _input(event: InputEvent) -> void:
	if not is_capturing() or not is_visible_in_tree(): return
	if event is InputEventKey and event.pressed and (event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE):
		cancel_capture(true)
		status.text = "已取消改键。"
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey and not event is InputEventMouseButton: return
	if not event.is_pressed(): return
	get_viewport().set_input_as_handled()
	var code: int = _controls.model.event_code(event)
	if code == 0: return
	var error: String = _controls.rebind(_action, _slot, code)
	if not error.is_empty():
		status.text = error
		if audio: audio.play_action(&"error")
		return
	cancel_capture()
	status.text = _controls.last_error if not _controls.last_error.is_empty() else "已生效：%s。" % _controls.model.label_for(code)
	if audio: audio.play_action(&"confirm")
