extends RefCounted

## 正数为物理键码，负数为鼠标键；同一动作的各槽位是并列备选键。
const SPECS := [
	{"id": &"move_up", "label": "向上移动", "group": "移动与镜头", "keys": [KEY_W, KEY_UP]},
	{"id": &"move_left", "label": "向左移动", "group": "移动与镜头", "keys": [KEY_A, KEY_LEFT]},
	{"id": &"move_down", "label": "向下移动", "group": "移动与镜头", "keys": [KEY_S, KEY_DOWN]},
	{"id": &"move_right", "label": "向右移动", "group": "移动与镜头", "keys": [KEY_D, KEY_RIGHT]},
	{"id": &"camera_follow", "label": "镜头跟随开关", "group": "移动与镜头", "keys": [KEY_Y]},
	{"id": &"camera_left", "label": "镜头向左旋转", "group": "移动与镜头", "keys": [KEY_Q]},
	{"id": &"camera_right", "label": "镜头向右旋转", "group": "移动与镜头", "keys": [KEY_E]},
	{"id": &"normal_attack", "label": "普通攻击（可按住）", "group": "战斗", "keys": [-MOUSE_BUTTON_LEFT], "mouse": true},
	{"id": &"body_charge", "label": "蓄力弹射／切线脱离", "group": "战斗", "keys": [-MOUSE_BUTTON_RIGHT], "mouse": true},
	{"id": &"blink", "label": "闪身", "group": "战斗", "keys": [KEY_SHIFT], "mouse": true},
	{"id": &"jump", "label": "跳跃", "group": "战斗", "keys": [KEY_SPACE], "mouse": true},
	{"id": &"interact", "label": "交互／开始与继续波次", "group": "界面与环境", "keys": [KEY_F]},
	{"id": &"inventory", "label": "人物与背包", "group": "界面与环境", "keys": [KEY_TAB]},
	{"id": &"cycle_style", "label": "切换光影风格", "group": "界面与环境", "keys": [KEY_R]},
	{"id": &"toggle_rain", "label": "下雨开关", "group": "界面与环境", "keys": [KEY_G]},
	{"id": &"retry", "label": "结算后重试", "group": "界面与环境", "keys": [KEY_T]},
	{"id": &"settings", "label": "打开／关闭设置", "group": "界面与环境", "keys": [KEY_P]},
]
const MOVE_ACTIONS := [&"move_up", &"move_left", &"move_down", &"move_right"]
const MOUSE_BUTTONS := [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]
var defaults := {}
var bindings := {}

func _init() -> void:
	for spec in SPECS: defaults[spec.id] = spec.keys.duplicate()
	reset_defaults()

func reset_defaults() -> void:
	bindings = defaults.duplicate(true)

func _overrides() -> Dictionary:
	var result := {}
	for action in bindings:
		if bindings[action] != defaults[action]: result[action] = bindings[action].duplicate()
	return result

func use_defaults(values: Dictionary) -> String:
	var candidate := values.duplicate(true)
	candidate.merge(_overrides(), true)
	var error := _validate(candidate)
	if not error.is_empty(): return error
	defaults = values.duplicate(true)
	bindings = candidate
	return ""

func _code_error(spec: Dictionary, code: Variant) -> String:
	if typeof(code) != TYPE_INT or code == 0: return "请选择有效的按键。"
	if code < 0:
		if not spec.get("mouse", false): return "这个操作请使用键盘按键。"
		return "" if -code in MOUSE_BUTTONS else "鼠标滚轮不能用于持续操作。"
	if code in [KEY_ESCAPE, KEY_CTRL, KEY_ALT, KEY_META] or (code >= KEY_F1 and code <= KEY_F12) or (code >= KEY_1 and code <= KEY_9):
		return "这个按键保留给返回、界面选择或编辑器操作。"
	return "" if not OS.get_keycode_string(code).is_empty() else "无法识别这个键位。"

func _validate(candidate: Dictionary) -> String:
	var occupied := {}
	for spec in SPECS:
		var keys: Variant = candidate.get(spec.id)
		if not keys is Array or keys.size() != spec.keys.size(): return "按键槽位无效。"
		for code in keys:
			var error := _code_error(spec, code)
			if not error.is_empty(): return error
			if occupied.has(code): return "与「%s」使用的按键冲突，请选择其他按键。" % occupied[code]
			occupied[code] = spec.label
	return ""

func set_binding(action: StringName, slot: int, code: int) -> String:
	if not bindings.has(action) or slot < 0 or slot >= bindings[action].size(): return "操作或按键槽位无效。"
	var candidate := bindings.duplicate(true)
	candidate[action][slot] = code
	var error := _validate(candidate)
	if error.is_empty(): bindings = candidate
	return error

func event_code(event: InputEvent) -> int:
	if not event.is_pressed() or event.is_echo(): return 0
	if event is InputEventWithModifiers and (event.alt_pressed or event.ctrl_pressed or event.meta_pressed): return 0
	if event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode else event.keycode
		if event.shift_pressed and code != KEY_SHIFT: return 0
		return code
	if event is InputEventMouseButton:
		if event.shift_pressed: return 0
		return -event.button_index
	return 0

func label_for(code: int) -> String:
	if code < 0:
		return {MOUSE_BUTTON_LEFT:"鼠标左键", MOUSE_BUTTON_RIGHT:"鼠标右键", MOUSE_BUTTON_MIDDLE:"鼠标中键", MOUSE_BUTTON_XBUTTON1:"鼠标侧键 1", MOUSE_BUTTON_XBUTTON2:"鼠标侧键 2"}.get(-code, "未知鼠标键")
	return OS.get_keycode_string(code)

func apply_input_map() -> void:
	for action in bindings:
		if InputMap.has_action(action):
			Input.action_release(action)
			InputMap.action_erase_events(action)
		else: InputMap.add_action(action)
		for code: int in bindings[action]:
			var event: InputEvent
			if code > 0:
				event = InputEventKey.new()
				event.physical_keycode = code
			else:
				event = InputEventMouseButton.new()
				event.button_index = -code
			event.device = -1
			InputMap.action_add_event(action, event)

func movement_keys() -> Array[int]:
	var result: Array[int] = []
	for slot in 2:
		for action in MOVE_ACTIONS: result.append(bindings[action][slot])
	return result

func save_to_path(path: String) -> Error:
	var config := ConfigFile.new()
	for action in _overrides(): config.set_value("bindings", String(action), bindings[action])
	return config.save(path)

func load_from_path(path: String) -> Error:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK: return error
	var candidate := defaults.duplicate(true)
	for spec in SPECS:
		if config.has_section_key("bindings", String(spec.id)): candidate[spec.id] = config.get_value("bindings", String(spec.id))
	if not _validate(candidate).is_empty(): return ERR_INVALID_DATA
	bindings = candidate
	return OK
