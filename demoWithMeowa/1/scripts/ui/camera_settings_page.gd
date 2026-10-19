extends VBoxContainer
## 主菜单与游戏内共用；只保存数值偏好，快捷键切换的跟随状态不写入存档。
var camera: FollowCamera
var save_enabled := true
var config_path := "user://camera_settings.cfg"
var follow_toggle: CheckBox
var speed_input: SpinBox
var follow_speed_input: SpinBox
var follow_lag_input: SpinBox
var _follow := true
var _speed := 12.0
var _follow_speed := 10.0
var _follow_lag := 3.0
var _hint: Label

func configure(world: Node, settings_theme: Theme) -> void:
	theme = settings_theme
	add_theme_constant_override("separation", 16)
	var player := world.get_node_or_null("Player") as Player
	camera = player.movement_camera as FollowCamera if player else null
	if camera:
		_follow = camera.follow_enabled
		_speed = camera.edge_pan_speed
		_follow_speed = camera.follow_max_speed
		_follow_lag = camera.follow_max_lag
	var title := Label.new()
	title.text = "镜头控制"
	title.add_theme_font_size_override("font_size", 24)
	add_child(title)
	follow_toggle = CheckBox.new()
	follow_toggle.text = "镜头跟随人物"
	add_child(follow_toggle)
	speed_input = _number_row("边缘移动速度", 2.0, 40.0, 1.0, "米/秒")
	follow_speed_input = _number_row("跟随速度上限", 0.0, 80.0, 1.0, "米/秒")
	follow_lag_input = _number_row("最大跟随落后", 0.5, 8.0, 0.1, "米")
	_hint = Label.new()
	_hint.text = "跟随状态仅在本次运行生效，快捷键在「按键」页调整。关闭后用鼠标靠近屏幕边缘移动，仍可旋转镜头。\n跟随上限为 0 时不限速；落后增大时允许加速追赶，安全距离会按当前视野收紧。远处重新跟随时平滑归位。\n打开管理界面、鼠标移出窗口或窗口失焦时停止边缘移动。"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_color_override("font_color", Color("a6b2bd"))
	add_child(_hint)
	load_settings()
	sync_controls()
	follow_toggle.toggled.connect(func(value: bool):
		_follow = value
		if is_instance_valid(camera): camera.follow_enabled = value
		sync_controls())
	speed_input.value_changed.connect(func(value: float):
		_speed = value
		if is_instance_valid(camera): camera.edge_pan_speed = value
		save_settings())
	follow_speed_input.value_changed.connect(func(value: float):
		_follow_speed = value
		if is_instance_valid(camera): camera.follow_max_speed = value
		save_settings())
	follow_lag_input.value_changed.connect(func(value: float):
		_follow_lag = value
		if is_instance_valid(camera): camera.follow_max_lag = value
		save_settings())

func _number_row(title: String, minimum: float, maximum: float, step_size: float, suffix: String) -> SpinBox:
	var row := HBoxContainer.new()
	add_child(row)
	var label := Label.new()
	label.text = title
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = step_size
	input.suffix = suffix
	input.custom_minimum_size.x = 150
	row.add_child(input)
	return input

func sync_controls() -> void:
	if is_instance_valid(camera):
		_follow = camera.follow_enabled
		_speed = camera.edge_pan_speed
		_follow_speed = camera.follow_max_speed
		_follow_lag = camera.follow_max_lag
	if follow_toggle:
		var controls := get_node_or_null("/root/GameControls")
		var key: int = camera.follow_toggle_key if is_instance_valid(camera) else controls.model.bindings.camera_follow[0] if controls else KEY_Y
		follow_toggle.text = "镜头跟随人物 · %s 切换" % OS.get_keycode_string(key)
		follow_toggle.set_pressed_no_signal(_follow)
	if speed_input:
		speed_input.set_value_no_signal(_speed)
		speed_input.editable = not _follow
	if follow_speed_input: follow_speed_input.set_value_no_signal(_follow_speed)
	if follow_lag_input: follow_lag_input.set_value_no_signal(_follow_lag)

func load_settings() -> void:
	if not save_enabled: return
	var config := ConfigFile.new()
	if config.load(config_path) != OK: return
	_speed = _number(config, "edge_pan_speed", _speed, 2.0, 40.0)
	_follow_speed = _number(config, "follow_max_speed", _follow_speed, 0.0, 80.0)
	_follow_lag = _number(config, "follow_max_lag", _follow_lag, 0.5, 8.0)
	if is_instance_valid(camera):
		camera.edge_pan_speed = _speed
		camera.follow_max_speed = _follow_speed
		camera.follow_max_lag = _follow_lag
	sync_controls()

func _number(config: ConfigFile, key: String, fallback: float, minimum: float, maximum: float) -> float:
	var value: Variant = config.get_value("camera", key, fallback)
	return clampf(float(value), minimum, maximum) if (value is float or value is int) and is_finite(float(value)) else fallback

func save_settings() -> Error:
	if not save_enabled: return OK
	var config := ConfigFile.new()
	config.set_value("camera", "edge_pan_speed", _speed)
	config.set_value("camera", "follow_max_speed", _follow_speed)
	config.set_value("camera", "follow_max_lag", _follow_lag)
	var result := config.save(config_path)
	if result != OK and _hint: _hint.text = "本次修改已生效，但未能保存镜头设置。"
	return result
