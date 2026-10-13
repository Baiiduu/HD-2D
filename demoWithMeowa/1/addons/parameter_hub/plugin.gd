@tool
extends EditorPlugin

const Catalog = preload("catalog.gd")
var _catalog := Catalog.new()
var _dock: EditorDock
var _search: LineEdit
var _common: CheckBox
var _tree: Tree
var _status: Label
var _hint: Label

func _enter_tree() -> void:
	_dock = EditorDock.new()
	_dock.title = "参数总览"
	# 与检查器分处上下区域，选中参数后总览仍可继续使用。
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_BL
	_dock.available_layouts = EditorDock.DOCK_LAYOUT_VERTICAL | EditorDock.DOCK_LAYOUT_FLOATING
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_dock.add_child(column)
	_search = LineEdit.new()
	_search.placeholder_text = "搜索：伤害、景深、雨声…"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text: String): _filter())
	column.add_child(_search)
	var toolbar := HBoxContainer.new()
	column.add_child(toolbar)
	_common = CheckBox.new()
	_common.text = "只看常用"
	_common.button_pressed = true
	_common.toggled.connect(func(_value: bool): _filter())
	toolbar.add_child(_common)
	var refresh := Button.new()
	refresh.text = "刷新"
	refresh.pressed.connect(_refresh)
	toolbar.add_child(refresh)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.custom_minimum_size = Vector2(240, 280)
	_tree.item_selected.connect(_select)
	column.add_child(_tree)
	_hint = Label.new()
	_hint.text = "选择参数，在检查器修改原值。\nStyle 只切视觉和天气；镜头独立调节。"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_hint)
	add_dock(_dock)
	scene_changed.connect(_scene_changed)
	scene_closed.connect(_scene_closed)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_refresh)
	_refresh.call_deferred()

func _exit_tree() -> void:
	EditorInterface.get_resource_filesystem().filesystem_changed.disconnect(_refresh)
	scene_changed.disconnect(_scene_changed)
	scene_closed.disconnect(_scene_closed)
	remove_dock(_dock)
	_dock.queue_free()
	_catalog.entries.clear()

func _scene_changed(_scene: Node) -> void:
	_refresh.call_deferred()

func _scene_closed(_path: String) -> void:
	_refresh.call_deferred()

func _refresh() -> void:
	if not is_instance_valid(_tree): return
	_catalog.collect(EditorInterface.get_edited_scene_root())
	_filter()

func _filter() -> void:
	_tree.clear()
	var root := _tree.create_item()
	var branches := {}
	var components := {}
	var count := 0
	var query := _search.text.strip_edges().to_lower()
	for section in Catalog.CATEGORIES:
		for entry in _catalog.entries:
			if entry.category != section or not is_instance_valid(entry.object): continue
			# 搜索始终覆盖全部参数，不受“只看常用”限制。
			if not query.is_empty() and not query in entry.search: continue
			if query.is_empty() and _common.button_pressed and not entry.common: continue
			if not branches.has(section):
				var branch := _tree.create_item(root)
				branch.set_text(0, section)
				branch.set_selectable(0, false)
				branches[section] = branch
			var parent: TreeItem = branches[section]
			if not _common.button_pressed or not query.is_empty():
				var key: String = section + ":" + entry.path + ":" + entry.group
				if not components.has(key):
					var component := _tree.create_item(parent)
					component.set_text(0, entry.path + " · " + entry.group)
					component.set_selectable(0, false)
					component.collapsed = query.is_empty()
					components[key] = component
				parent = components[key]
			var item := _tree.create_item(parent)
			item.set_text(0, entry.label + (" · " + entry.path if _common.button_pressed and query.is_empty() else ""))
			item.set_tooltip_text(0, entry.group + "\n" + entry.path + "\n" + entry.property + "\n" + entry.description)
			item.set_metadata(0, entry)
			count += 1
	_status.text = "当前场景 · %d / %d 个参数" % [count, _catalog.entries.size()]
	if _catalog.entries.is_empty(): _status.text = "请打开要调节的地图或组件场景。"

func _select() -> void:
	var item := _tree.get_selected()
	if item == null: return
	var entry: Variant = item.get_metadata(0)
	if not entry is Dictionary or not is_instance_valid(entry.object): return
	# 检查器拥有撤销、保存和资源编辑；总览不维护第二套数值。
	EditorInterface.inspect_object(entry.object, entry.property)
	_hint.text = entry.group + "\n" + entry.path + "\n" + entry.property + "\n" + entry.description
	if entry.object is Resource:
		_hint.text += "\n编辑资源会影响引用它的对象；需要独立配置时先设为唯一。"
