@tool
extends EditorPlugin

const Catalog = preload("catalog.gd")
var _catalog := Catalog.new()
var _dock: EditorDock
var _search: LineEdit
var _common: CheckBox
var _locate_button: Button
var _tree: Tree
var _status: Label
var _hint: Label
var _navigation_request := 0

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
	_hint.text = "选择参数，在检查器修改原值；双击或点击“定位来源”跳转。\nStyle 只切视觉和天气；镜头独立调节。"
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
	_ensure_navigation()
	_navigation_request += 1
	_tree.clear()
	_locate_button.disabled = true
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
	_ensure_navigation()
	_navigation_request += 1
	var entry := _selected_entry()
	_locate_button.disabled = entry.is_empty()
	if entry.is_empty(): return
	# 检查器拥有撤销、保存和资源编辑；总览不维护第二套数值。
	EditorInterface.inspect_object(entry.object, entry.property)
	_hint.text = entry.group + "\n" + entry.path + "\n" + entry.property + "\n" + entry.description
	var scene := EditorInterface.get_edited_scene_root()
	if scene and is_instance_valid(entry.node):
		_hint.text += "\n来源节点：" + String(scene.get_path_to(entry.node))
		_hint.text += "\n当前场景：" + scene.scene_file_path
	if entry.object is Resource:
		var resource: Resource = entry.object
		_hint.text += "\n资源：" + (resource.resource_path if not resource.resource_path.is_empty() else "场景内置资源（尚未独立保存）")
		_hint.text += "\n编辑资源会影响引用它的对象；需要独立配置时先设为唯一。"

func _ensure_navigation() -> void:
	# @tool 脚本热重载不会重建已有停靠栏，刷新时为旧面板补上入口。
	if not is_instance_valid(_locate_button):
		_locate_button = Button.new()
		_locate_button.text = "定位来源"
		_locate_button.tooltip_text = "选中来源节点并展开、高亮检查器参数；资源还会定位文件。也可双击参数。"
		_locate_button.disabled = true
		_locate_button.pressed.connect(_locate)
		_common.get_parent().add_child(_locate_button)
	if not _tree.item_activated.is_connected(_locate): _tree.item_activated.connect(_locate)

func _selected_entry() -> Dictionary:
	var item := _tree.get_selected()
	if item == null: return {}
	var entry: Variant = item.get_metadata(0)
	if not entry is Dictionary or not is_instance_valid(entry.object): return {}
	return entry

func _locate() -> void:
	var entry := _selected_entry()
	if entry.is_empty(): return
	var scene := EditorInterface.get_edited_scene_root()
	var node: Node = entry.node
	if not is_instance_valid(node) or not scene or (node != scene and not scene.is_ancestor_of(node)):
		_locate_button.disabled = true
		_hint.text = "来源节点已变化，请刷新参数总览后重新选择。"
		return
	_navigation_request += 1
	var request := _navigation_request
	EditorInterface.get_selection().clear()
	EditorInterface.edit_node(node)
	if entry.object is Resource:
		# 内置子资源使用 :: 后缀；文件系统只能定位到其所属场景或资源文件。
		var resource: Resource = entry.object
		var file := resource.resource_path.get_slice("::", 0)
		if not file.is_empty() and FileAccess.file_exists(file): EditorInterface.select_file(file)
	# 场景树选择也会延迟切换检查器，等其完成后再显示真正的资源参数。
	await get_tree().process_frame
	if request != _navigation_request or not is_instance_valid(entry.object): return
	EditorInterface.inspect_object(entry.object, entry.property)
	await get_tree().process_frame
	if request != _navigation_request or not is_instance_valid(entry.object): return
	var inspector := EditorInterface.get_inspector()
	if inspector.get_edited_object() != entry.object: return
	for editor in inspector.find_children("*", "EditorProperty", true, false):
		if editor.get_edited_object() != entry.object or editor.get_edited_property() != entry.property: continue
		# 只展开目标项的祖先分组，避免展开所有资源与大型数组。
		var parent := editor.get_parent()
		while parent != inspector and parent != null:
			if parent.is_class("EditorInspectorSection"): parent.call("unfold")
			parent = parent.get_parent()
		editor.select()
		inspector.ensure_control_visible.call_deferred(editor)
		break
