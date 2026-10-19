@tool
extends EditorPlugin

const MAPS: Array[Dictionary] = [
	{
		"name": "回弹 · 动态主菜单",
		"path": "res://scenes/ui/main_menu.tscn",
		"description": "分层夜景、人物弹射、火带与近景怪物击飞。\n开始按钮进入正式地图；F5 默认仍保留正式地图。",
	},
	{
		"name": "City 城市战斗场景",
		"path": "res://scenes/city/city.tscn",
		"description": "城市布局与夜景，独立战斗配置。\n共用正式战斗代码；在参数总览选择 City 调参。",
	},
	{
		"name": "正式连续地图",
		"path": "res://scenes/world/world.tscn",
		"description": "正式主场景，当前只保留战斗区与外围绕行带。\n复用手绘地表、分隔带、小型弹射障碍、人物和无尽波次。",
	},
	{
		"name": "视觉预览",
		"path": "res://scenes/previews/four_realms.tscn",
		"description": "保留的独立视觉沙盒，用于光影和材质对照。\n玩法试玩统一使用正式连续地图。",
	},
	{
		"name": "树池建筑预览",
		"path": "res://scenes/previews/tree_planter_preview.tscn",
		"description": "当前正式世界中的独立树池样板。\n完整 2D 树与花草、3D 花坛和长椅；保留 Q/E 与 R。",
	},
	{
		"name": "广场路灯与环球雕塑预览",
		"path": "res://scenes/previews/plaza_landmarks_preview.tscn",
		"description": "参考图的双头金属路灯与黄铜环球雕塑。\n当前世界光照和镜头；两个独立道具可拖入正式地图。",
	},
	{
		"name": "六种弹射障碍物预览",
		"path": "res://scenes/previews/ricochet_props_preview.tscn",
		"description": "矮石墙、铁艺围栏、木箱堆、木桶组、方形石柱和 L 形挡墙。\n独立场景、实际碰撞，保留当前世界光影与 Q/E。",
	},
	{
		"name": "弹射建筑变种预览",
		"path": "res://scenes/previews/ricochet_variants_preview.tscn",
		"description": "十二种同风格变形，分四组陈列于当前广场。\n斜面、通行开口、圆面与多面转角；保留实际镜头与 Q/E。",
	},
	{
		"name": "伤害数字预览",
		"path": "res://scenes/previews/damage_numbers_preview.tscn",
		"description": "当前地图和实际镜头中的普通、重击、暴击与雷电数字样式。\n循环演示弹跳、错位与消散，保留 Q/E；重击／暴击仅为表现预留。",
	},
	{
		"name": "城镇细节物件预览",
		"path": "res://scenes/previews/town_details_preview.tscn",
		"description": "长椅、花车、告示牌、陶盆、水钵、垃圾桶、货运托盘和麻袋。\n独立可放置场景，保留实际形状碰撞与当前世界镜头。",
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
	# 隐藏页签的最小尺寸也参与编辑器布局；说明文字只能撑大滚动内容。
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	scroll.add_child(column)

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
	_sync_maps()
	if scene_root:
		for index in MAPS.size():
			if MAPS[index]["path"] == scene_root.scene_file_path:
				_selector.select(index)
				break
	_update_status()

func _selected_path() -> String:
	_sync_maps()
	return MAPS[_selector.selected]["path"]

func _default_path() -> String:
	var path: String = ProjectSettings.get_setting("application/run/main_scene", "")
	if path.begins_with("uid://"):
		var id := ResourceUID.text_to_id(path)
		if ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
	return path

func _sync_maps() -> void:
	if _selector.item_count == MAPS.size(): return
	var previous := _selector.get_item_tooltip(_selector.selected) if _selector.selected >= 0 else ""
	_selector.clear()
	for map in MAPS:
		_selector.add_item(map["name"])
		_selector.set_item_tooltip(_selector.item_count - 1, map["path"])
		if map["path"] == previous: _selector.select(_selector.item_count - 1)

func _update_status() -> void:
	_sync_maps()
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
