@tool
extends EditorPlugin

const MAPS: Array[Dictionary] = [
	{
		"name": "视觉预览",
		"path": "res://scenes/four_realms.tscn",
		"description": "现有视觉效果测试地图。",
	},
	{
		"name": "正式连续地图",
		"path": "res://scenes/world/world.tscn",
		"description": "独立连续地图入口。\n默认接入预览光影、相机、天气和音乐；地图内容独立搭建。",
	},
]

var _dock: EditorDock
var _selector: OptionButton
var _description: Label
var _default_status: Label
var _default_button: Button

func _enter_tree() -> void:
	_dock = EditorDock.new()
	_dock.title = "地图切换"
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	_dock.available_layouts = EditorDock.DOCK_LAYOUT_VERTICAL | EditorDock.DOCK_LAYOUT_FLOATING
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	_dock.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	_selector = OptionButton.new()
	_selector.name = "MapSelector"
	for map in MAPS:
		_selector.add_item(map["name"])
		_selector.set_item_tooltip(_selector.item_count - 1, map["path"])
	_selector.item_selected.connect(_on_map_selected)
	column.add_child(_selector)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_description)

	var open_button := Button.new()
	open_button.text = "打开地图"
	open_button.pressed.connect(_open_map)
	column.add_child(open_button)
	var play_button := Button.new()
	play_button.text = "运行此地图"
	play_button.pressed.connect(_play_map)
	column.add_child(play_button)
	column.add_child(HSeparator.new())
	_default_status = Label.new()
	_default_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_default_status)
	_default_button = Button.new()
	_default_button.text = "设为默认启动地图"
	_default_button.pressed.connect(_set_default_map)
	column.add_child(_default_button)

	add_dock(_dock)
	scene_changed.connect(_on_scene_changed)
	ProjectSettings.settings_changed.connect(_update_status)
	_on_scene_changed(EditorInterface.get_edited_scene_root())
	_update_status()

func _exit_tree() -> void:
	ProjectSettings.settings_changed.disconnect(_update_status)
	scene_changed.disconnect(_on_scene_changed)
	remove_dock(_dock)
	_dock.queue_free()

func _on_map_selected(_index: int) -> void:
	_update_status()

func _on_scene_changed(scene_root: Node) -> void:
	if scene_root:
		for index in MAPS.size():
			if MAPS[index]["path"] == scene_root.scene_file_path:
				_selector.select(index)
				break
	_update_status()

func _selected_path() -> String:
	return MAPS[_selector.selected]["path"]

func _default_path() -> String:
	var path: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if path.begins_with("uid://"):
		var id := ResourceUID.text_to_id(path)
		if ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
	return path

func _update_status() -> void:
	_description.text = MAPS[_selector.selected]["description"]
	var default_path := _default_path()
	var default_name := default_path.get_file()
	for map in MAPS:
		if map["path"] == default_path:
			default_name = map["name"]
	_default_status.text = "F5 默认：" + default_name
	_default_button.disabled = _selected_path() == default_path

func _open_map() -> void:
	EditorInterface.open_scene_from_path(_selected_path())

func _play_map() -> void:
	if EditorInterface.is_playing_scene():
		EditorInterface.stop_playing_scene()
	EditorInterface.play_custom_scene.call_deferred(_selected_path())

func _set_default_map() -> void:
	var previous: String = ProjectSettings.get_setting("application/run/main_scene", "")
	ProjectSettings.set_setting("application/run/main_scene", _selected_path())
	var error := ProjectSettings.save()
	if error != OK:
		ProjectSettings.set_setting("application/run/main_scene", previous)
		push_error("无法保存默认启动地图：%s" % error_string(error))
	_update_status()
