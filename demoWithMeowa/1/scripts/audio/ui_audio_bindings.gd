extends Node
## 页面级事件绑定。元数据 ui_audio_action 覆盖默认操作，空值表示由业务自己发声。
var audio: Node
var _presses: Dictionary = {}
var _edit_values: Dictionary = {}

func bind_tree(node: Node) -> void:
	if not is_instance_valid(node) or node == audio: return
	var previous: WeakRef = node.get_meta(&"_ui_audio_binding") if node.has_meta(&"_ui_audio_binding") else null
	if previous and is_instance_valid(previous.get_ref()): return
	node.set_meta(&"_ui_audio_binding", weakref(self))
	node.child_entered_tree.connect(bind_tree, CONNECT_DEFERRED)
	if node is OptionButton:
		node.item_selected.connect(func(_index: int): _play_for(node, &"choice"))
	elif node is BaseButton:
		node.button_down.connect(_capture_press.bind(node))
		node.tree_exiting.connect(func(): _clear_press(node.get_instance_id()))
		node.button_up.connect(func(): _clear_press.call_deferred(node.get_instance_id()))
		node.pressed.connect(_pressed.bind(node))
	elif node is TabBar:
		node.tab_clicked.connect(func(_index: int): _play_for(node, &"tab"))
	elif node is Slider:
		node.drag_ended.connect(func(changed: bool):
			if changed: _play_for(node, &"adjust"))
		node.gui_input.connect(_range_input.bind(node))
	elif node is SpinBox:
		node.gui_input.connect(_range_input.bind(node))
		var edit: LineEdit = node.get_line_edit()
		edit.gui_input.connect(_range_input.bind(node))
		edit.focus_entered.connect(func(): _edit_values[node.get_instance_id()] = node.value)
		edit.text_submitted.connect(func(_text: String): _commit_edit(node))
		edit.focus_exited.connect(_commit_edit.bind(node))
		node.tree_exiting.connect(func(): _edit_values.erase(node.get_instance_id()))
	for child in node.get_children(): bind_tree(child)

func _audible(control: Control) -> bool:
	if not control.is_visible_in_tree(): return false
	if control is BaseButton and control.disabled: return false
	if (control is SpinBox or control is Slider) and not control.editable: return false
	return true

func _action(control: Control, fallback: StringName) -> StringName:
	return StringName(control.get_meta(&"ui_audio_action", fallback))

func _play_for(control: Control, fallback: StringName) -> void:
	if _audible(control): audio.play_action(_action(control, fallback))

func _capture_press(button: BaseButton) -> void:
	_presses[button.get_instance_id()] = {
		"allowed": _audible(button),
		"action": _action(button, &"toggle" if button.toggle_mode else &"button"),
	}

func _clear_press(id: int) -> void:
	_presses.erase(id)

func _pressed(button: BaseButton) -> void:
	var id := button.get_instance_id()
	# 业务回调可能先隐藏或禁用按钮；沿用按下时的资格，仍只在实际激活后发声。
	var press: Dictionary = _presses.get(id, {"allowed": _audible(button), "action": _action(button, &"toggle" if button.toggle_mode else &"button")})
	_presses.erase(id)
	if press.allowed: audio.play_action(press.action)

func _range_input(event: InputEvent, control: Range) -> void:
	if not event.is_pressed() or not _audible(control): return
	if event is InputEventKey:
		if event.keycode not in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN]: return
	elif event is InputEventMouseButton:
		if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]: return
		if control is Slider and event.button_index == MOUSE_BUTTON_LEFT: return
	else: return
	_after_range_input.call_deferred(weakref(control), control.value)

func _commit_edit(control: SpinBox) -> void:
	_after_range_input.call_deferred(weakref(control), float(_edit_values.get(control.get_instance_id(), control.value)))

func _after_range_input(reference: WeakRef, before: float) -> void:
	var control := reference.get_ref() as Range
	if not control: return
	if control is SpinBox: _edit_values[control.get_instance_id()] = control.value
	if not is_equal_approx(before, control.value): _play_for(control, &"adjust")
