@tool
extends VBoxContainer
## 只读写项目设置；不查找当前场景或修改任何场景节点。
const SYSTEMS := preload("res://scripts/core/game_system_settings.gd")
var _controls: Dictionary[StringName, CheckButton] = {}
var _status: Label

func _ready() -> void:
	SYSTEMS.ensure_defaults()
	add_theme_constant_override("separation", 10)
	var heading := Label.new()
	heading.text = "项目系统开关"
	add_child(heading)
	for system in SYSTEMS.SYSTEMS:
		var toggle := CheckButton.new()
		toggle.text = system.label
		toggle.tooltip_text = system.description
		toggle.toggled.connect(_toggled.bind(system.id))
		add_child(toggle)
		_controls[system.id] = toggle
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 220
	add_child(_status)
	var hint := Label.new()
	hint.text = "作用于所有场景，下次运行生效。\n各系统的本地 Enabled 开关也须开启。\n角色固有弹射、Dash 和基础普攻独立。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	ProjectSettings.settings_changed.connect(_refresh)
	_refresh()

func set_switch(system: StringName, enabled: bool, save := true) -> Error:
	if not SYSTEMS.SYSTEMS.any(func(entry: Dictionary): return entry.id == system): return ERR_INVALID_PARAMETER
	var property := SYSTEMS.key(system)
	var previous: Variant = ProjectSettings.get_setting(property, true)
	ProjectSettings.set_setting(property, enabled)
	var error := ProjectSettings.save() if save else OK
	if error != OK: ProjectSettings.set_setting(property, previous)
	if is_node_ready():
		_refresh()
		_status.text = "已保存到 project.godot，下次运行生效。" if error == OK else "保存失败，已恢复开关：" + error_string(error)
	return error

func _toggled(enabled: bool, system: StringName) -> void:
	set_switch(system, enabled)

func _refresh() -> void:
	for id in _controls: _controls[id].set_pressed_no_signal(SYSTEMS.is_enabled(id))
	_status.text = "当前为项目设置，不依赖打开的场景。"

func _exit_tree() -> void:
	if ProjectSettings.settings_changed.is_connected(_refresh): ProjectSettings.settings_changed.disconnect(_refresh)
