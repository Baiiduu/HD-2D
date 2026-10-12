@tool
extends EditorPlugin

var _dock: EditorDock
var _target_label: Label
var _paint_button: Button
var _brush: OptionButton
var _palette_picker: EditorResourcePicker
var _texture_picker: EditorResourcePicker
var _mode: OptionButton
var _add_button: Button
var _config_button: Button
var _palette: TerrainPaintPalette
var _dirty_palettes: Dictionary[TerrainPaintPalette,String] = {}
var _size: SpinBox
var _save_button: Button
var _status: Label
var _terrain: Terrain
var _camera: Camera3D
var _pick_source: Mesh
var _pick_mesh: TriangleMesh
var _hover_cell := Vector2i.ZERO
var _has_hover := false
var _stroking := false
var _stroke_erase := false
var _stroke_brush: TerrainPaintBrush
var _stroke_target := TerrainPaintBrush.Target.PATH
var _last_cell := Vector2i.ZERO
var _has_last_cell := false
var _before: Dictionary[int, Vector3i] = {}
var _tracked: Dictionary[TerrainData, String] = {}
var _dirty: Dictionary[TerrainData, String] = {}

func _enter_tree() -> void:
	_dock = EditorDock.new()
	_dock.title = "地表画笔"
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	_dock.available_layouts = EditorDock.DOCK_LAYOUT_VERTICAL | EditorDock.DOCK_LAYOUT_FLOATING
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	_dock.add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)
	_target_label = Label.new()
	_target_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_target_label)
	var palette_label := Label.new()
	palette_label.text = "画笔列表配置"
	column.add_child(palette_label)
	_palette_picker = EditorResourcePicker.new()
	_palette_picker.base_type = "TerrainPaintPalette"
	_palette_picker.resource_changed.connect(_change_palette)
	_palette_picker.resource_selected.connect(func(resource: Resource,_inspect: bool): EditorInterface.edit_resource(resource))
	column.add_child(_palette_picker)
	_paint_button = Button.new()
	_paint_button.text = "启用地表画笔"
	_paint_button.toggle_mode = true
	_paint_button.toggled.connect(_toggle_paint)
	column.add_child(_paint_button)
	_brush = OptionButton.new()
	_brush.item_selected.connect(func(_index: int): _finish_stroke(); _update_brush_config())
	column.add_child(_brush)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	_add_button = Button.new()
	_add_button.text = "新增画笔"
	_add_button.pressed.connect(_add_brush)
	actions.add_child(_add_button)
	_config_button = Button.new()
	_config_button.text = "编辑画笔 / 图集"
	_config_button.pressed.connect(func():
		var brush := _selected_brush()
		if brush: EditorInterface.edit_resource(brush))
	actions.add_child(_config_button)
	_texture_picker = EditorResourcePicker.new()
	_texture_picker.base_type = "Texture2D"
	_texture_picker.resource_changed.connect(_change_texture)
	_texture_picker.resource_selected.connect(func(resource: Resource,_inspect: bool): EditorInterface.edit_resource(resource))
	column.add_child(_texture_picker)
	_mode = OptionButton.new()
	for text in ["整张纹理","图集中的单块","四角过渡图集"]: _mode.add_item(text)
	_mode.item_selected.connect(_change_mode)
	column.add_child(_mode)
	var size_label := Label.new()
	size_label.text = "画笔尺寸（格）"
	column.add_child(size_label)
	_size = SpinBox.new()
	_size.min_value = 1
	_size.max_value = 9
	_size.step = 2
	_size.value = 1
	_size.tooltip_text = "1 格为精细绘制；3、5、7、9 格为更宽的方形画笔。当前每格 1.6 米。"
	_size.value_changed.connect(_change_size)
	column.add_child(_size)
	var help := Label.new()
	help.text = "选中 Homestead，选择画笔后启用。\n新增画笔后选择纹理；图集格子在「编辑画笔 / 图集」设置。\n左键拖动绘制；Shift + 左键擦除选中地表。\nCtrl+Z 撤销；Ctrl+Shift+Z 重做。"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(help)
	_save_button = Button.new()
	_save_button.text = "保存地表"
	_save_button.pressed.connect(_save_current)
	column.add_child(_save_button)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	add_dock(_dock)
	scene_saved.connect(_on_scene_saved)
	_update_panel()

func _exit_tree() -> void:
	_finish_stroke()
	if _palette: _palette.changed.disconnect(_on_palette_changed)
	for data in _tracked:
		data.changed.disconnect(_on_data_changed.bind(data))
	scene_saved.disconnect(_on_scene_saved)
	remove_dock(_dock)
	_dock.queue_free()

func _handles(object: Object) -> bool:
	return object is Terrain

func _edit(object: Object) -> void:
	_finish_stroke()
	_terrain = object as Terrain
	_pick_source = null
	_pick_mesh = null
	_has_hover = false
	_paint_button.set_pressed_no_signal(false)
	_paint_button.text = "启用地表画笔"
	if is_instance_valid(_terrain) and _terrain.data and not _tracked.has(_terrain.data):
		var scene := EditorInterface.get_edited_scene_root()
		_tracked[_terrain.data] = scene.scene_file_path if scene else ""
		_terrain.data.changed.connect(_on_data_changed.bind(_terrain.data))
	_bind_palette()
	_update_panel()
	update_overlays()

func _make_visible(visible: bool) -> void:
	if not visible:
		_toggle_paint(false)
		_paint_button.set_pressed_no_signal(false)

func _clear() -> void:
	_edit(null)

func _toggle_paint(enabled: bool) -> void:
	if not enabled:
		_finish_stroke()
		_has_hover = false
	_paint_button.text = "停止绘制" if enabled else "启用地表画笔"
	update_overlays()

func _change_size(value: float) -> void:
	# 手动输入时也保持 1、3、5、7、9 格，使尺寸与实际预览一致。
	_size.set_value_no_signal(clampi(int(value) | 1, 1, 9))
	update_overlays()

func _update_panel() -> void:
	var valid := is_instance_valid(_terrain) and _terrain.data != null
	_paint_button.disabled = not valid
	_brush.disabled = not valid
	_size.editable = valid
	_save_button.disabled = not valid
	_palette_picker.editable = valid
	_palette_picker.edited_resource = _palette
	_add_button.disabled = not valid
	_target_label.text = "选中场景中的 Terrain 地形节点。"
	_status.text = "仅绘制地表，不调整地形高度。"
	if valid:
		_target_label.text = "%s\n%s" % [_terrain.name, _terrain.data.resource_path]
		_status.text = "地表有未保存的修改。" if _dirty.has(_terrain.data) else "地表已保存。"
		if _palette and _dirty_palettes.has(_palette): _status.text = "画笔配置有未保存的修改。"
	_update_brush_config()

func _bind_palette() -> void:
	if _palette and _palette.changed.is_connected(_on_palette_changed): _palette.changed.disconnect(_on_palette_changed)
	_palette = _terrain.paint_palette if is_instance_valid(_terrain) else null
	if _palette: _palette.changed.connect(_on_palette_changed)
	_refresh_brushes()
	_update_panel()

func _refresh_brushes() -> void:
	var selected := _brush.selected
	_brush.clear()
	if _palette:
		for brush in _palette.brushes:
			_brush.add_item(brush.label if brush else "未配置画笔")
	else:
		_brush.add_item("草地")
		_brush.add_item("卵石道路")
	if _brush.item_count > 0: _brush.select(clampi(selected,0,_brush.item_count-1))

func _selected_brush() -> TerrainPaintBrush:
	if _palette and _brush.selected >= 0 and _brush.selected < _palette.brushes.size():
		return _palette.brushes[_brush.selected]
	return null

func _update_brush_config() -> void:
	var brush := _selected_brush()
	_texture_picker.edited_resource = brush.texture if brush else null
	_texture_picker.editable = brush != null
	_mode.disabled = brush == null
	_config_button.disabled = brush == null
	if brush: _mode.select(brush.mode)
	if _palette:
		var problem := _palette.id_error()
		if problem.is_empty(): problem = brush.validation_error() if brush else "请选择已配置的画笔。"
		if not problem.is_empty():
			_status.text = problem
			_paint_button.disabled = true
			_paint_button.set_pressed_no_signal(false)
		else:
			_paint_button.disabled = not is_instance_valid(_terrain) or not _terrain.data

func _on_palette_changed() -> void:
	_finish_stroke()
	var scene := EditorInterface.get_edited_scene_root()
	_dirty_palettes[_palette] = scene.scene_file_path if scene else ""
	_refresh_brushes()
	_update_panel()

func _change_palette(resource: Resource) -> void:
	_finish_stroke()
	var history := get_undo_redo()
	history.create_action("配置地表画笔",UndoRedo.MERGE_DISABLE,_terrain)
	history.add_do_property(_terrain,"paint_palette",resource)
	history.add_undo_property(_terrain,"paint_palette",_terrain.paint_palette)
	history.add_do_method(self,"_bind_palette")
	history.add_undo_method(self,"_bind_palette")
	history.commit_action()
	_update_panel()

func _change_brush_property(property: String,value: Variant) -> void:
	_finish_stroke()
	var brush := _selected_brush()
	if not brush: return
	var history := get_undo_redo()
	history.create_action("配置地表纹理",UndoRedo.MERGE_DISABLE,_terrain)
	history.add_do_property(brush,property,value)
	history.add_undo_property(brush,property,brush.get(property))
	history.commit_action()

func _change_texture(resource: Resource) -> void:
	_change_brush_property("texture",resource)

func _change_mode(index: int) -> void:
	_change_brush_property("mode",index)

func _add_brush() -> void:
	_finish_stroke()
	if not _palette:
		var palette := TerrainPaintPalette.new()
		for target in [TerrainPaintBrush.Target.GRASS,TerrainPaintBrush.Target.PATH]:
			var brush := TerrainPaintBrush.new()
			brush.target = target
			brush.is_grass = target == TerrainPaintBrush.Target.GRASS
			var prefix := "wild" if target == TerrainPaintBrush.Target.GRASS else "path"
			brush.label = "草地" if prefix == "wild" else "道路"
			brush.mode = TerrainPaintBrush.Mode.TEXTURE if prefix == "wild" else TerrainPaintBrush.Mode.CORNER_ATLAS
			if prefix == "path" and _terrain.top_material.get_shader_parameter("path_configured"):
				brush.atlas_grid = Vector2i(_terrain.top_material.get_shader_parameter("path_grid"))
				brush.corner_tiles = _terrain.top_material.get_shader_parameter("path_tiles")
			brush.texture = _terrain.top_material.get_shader_parameter(prefix+("_texture" if prefix == "wild" else "_atlas"))
			var tint: Variant = _terrain.top_material.get_shader_parameter(prefix+"_tint")
			if tint == null: tint = RenderingServer.shader_get_parameter_default(_terrain.top_material.shader.get_rid(),prefix+"_tint")
			if tint is Color: brush.tint = tint
			var response: Variant = _terrain.top_material.get_shader_parameter(prefix+"_surface")
			if response == null: response = RenderingServer.shader_get_parameter_default(_terrain.top_material.shader.get_rid(),prefix+"_surface")
			var surface: Vector3 = response if response is Vector3 else brush.surface()
			brush.roughness = surface.x; brush.metallic = surface.y; brush.wet_response = surface.z
			palette.brushes.append(brush)
		_change_palette(palette)
	var next_id := 1
	while next_id <= 255 and _palette.brush_for_id(next_id): next_id += 1
	if next_id > 255:
		_status.text = "已使用全部 255 个自定义地表编号。"
		return
	var brush := TerrainPaintBrush.new()
	brush.label = "新地表 %d" % next_id
	brush.paint_id = next_id
	var before := _palette.brushes.duplicate()
	var after := before.duplicate()
	after.append(brush)
	var history := get_undo_redo()
	history.create_action("新增地表画笔",UndoRedo.MERGE_DISABLE,_terrain)
	history.add_do_property(_palette,"brushes",after)
	history.add_undo_property(_palette,"brushes",before)
	history.commit_action()
	_brush.select(after.size()-1)
	_update_panel()
	EditorInterface.edit_resource(brush)

func _process(_delta: float) -> void:
	# 鼠标在视口外松开时也结束本笔，防止下一次移动继续涂画。
	if _stroking and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_stroke()

func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if not is_instance_valid(_terrain) or not _terrain.data or not _paint_button.button_pressed:
		return AFTER_GUI_INPUT_PASS
	if event is InputEventKey and event.pressed and event.ctrl_pressed:
		_finish_stroke()
		return AFTER_GUI_INPUT_PASS
	if not event is InputEventMouse:
		return AFTER_GUI_INPUT_PASS
	if event.alt_pressed or (event is InputEventMouseMotion and event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE)):
		_finish_stroke()
		_has_hover = false
		update_overlays()
		return AFTER_GUI_INPUT_PASS
	_camera = camera
	var hit := _pick(camera, event.position)
	_has_hover = not hit.is_empty()
	if _has_hover:
		_hover_cell = _terrain.data.world_to_cell(hit.position)
	update_overlays()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _has_hover:
			_stroking = true
			_stroke_erase = event.shift_pressed
			_stroke_brush = _selected_brush()
			_stroke_target = _stroke_brush.target if _stroke_brush else (TerrainPaintBrush.Target.GRASS if _brush.selected == 0 else TerrainPaintBrush.Target.PATH)
			if not _stroke_brush:
				_stroke_brush = TerrainPaintBrush.new()
				_stroke_brush.target = _stroke_target
			_before.clear()
			_has_last_cell = false
			_paint_to(_hover_cell)
		elif not event.pressed:
			_finish_stroke()
		return AFTER_GUI_INPUT_STOP
	if event is InputEventMouseMotion:
		if _stroking and _has_hover:
			_paint_to(_hover_cell)
		elif not _has_hover:
			_has_last_cell = false
		return AFTER_GUI_INPUT_STOP if _stroking else AFTER_GUI_INPUT_PASS
	return AFTER_GUI_INPUT_PASS

func _pick(camera: Camera3D, position: Vector2) -> Dictionary:
	var top := _terrain.get_node_or_null("Generated/Top") as MeshInstance3D
	if not top or not top.mesh:
		return {}
	if top.mesh != _pick_source:
		_pick_source = top.mesh
		_pick_mesh = top.mesh.generate_triangle_mesh()
	var inverse := top.global_transform.affine_inverse()
	var start := camera.project_ray_origin(position)
	var end := start + camera.project_ray_normal(position) * camera.far
	var hit := _pick_mesh.intersect_segment(inverse * start, inverse * end)
	if not hit.is_empty():
		# 地形数据的格子坐标以 Terrain 本地坐标为准。
		hit.position = _terrain.to_local(top.to_global(hit.position))
	return hit

func _brush_cells(center: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var radius := int(_size.value) / 2
	for z in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var cell := center + Vector2i(x, z)
			if _terrain.data.has_cell(cell): cells.append(cell)
	return cells

func _paint_to(cell: Vector2i) -> void:
	var start := _last_cell if _has_last_cell else cell
	var offset := cell - start
	var steps := maxi(absi(offset.x), absi(offset.y))
	for step in range(steps + 1):
		var t := float(step) / float(maxi(1, steps))
		var center := Vector2i(Vector2(start).lerp(Vector2(cell), t).round())
		for target in _brush_cells(center):
			_stamp(target)
	_last_cell = cell
	_has_last_cell = true
	_terrain.refresh_surface()

func _stamp(cell: Vector2i) -> void:
	var data := _terrain.data
	var local := cell - data.origin
	var index := local.y * data.size.x + local.x
	var before := _stroke_brush.stamp(data,index,_stroke_erase)
	if before == Vector3i(data.biomes[index],data.overlays[index],data.paint_at_index(index)):
		return
	if not _before.has(index):
		_before[index] = before

func _finish_stroke() -> void:
	if not _stroking:
		return
	_stroking = false
	_has_last_cell = false
	if _before.is_empty() or not is_instance_valid(_terrain) or not _terrain.data:
		_before.clear()
		return
	var data := _terrain.data
	var indices := PackedInt32Array()
	var old_biomes := PackedByteArray()
	var old_overlays := PackedByteArray()
	var new_biomes := PackedByteArray()
	var new_overlays := PackedByteArray()
	var old_paints := PackedByteArray()
	var new_paints := PackedByteArray()
	for index in _before:
		indices.append(index)
		old_biomes.append(_before[index].x)
		old_overlays.append(_before[index].y)
		new_biomes.append(data.biomes[index])
		new_overlays.append(data.overlays[index])
		old_paints.append(_before[index].z)
		new_paints.append(data.paint_at_index(index))
	var history := get_undo_redo()
	history.create_action("绘制地表", UndoRedo.MERGE_DISABLE, _terrain)
	history.add_do_method(data,"apply_surface_patch",indices,new_biomes,new_overlays,new_paints)
	history.add_undo_method(data,"apply_surface_patch",indices,old_biomes,old_overlays,old_paints)
	history.commit_action(false)
	_before.clear()
	data.emit_changed()

func _on_data_changed(data: TerrainData) -> void:
	_dirty[data] = _tracked[data]
	_update_panel()
	update_overlays()

func _forward_3d_draw_over_viewport(overlay: Control) -> void:
	if not _has_hover or not is_instance_valid(_terrain) or not is_instance_valid(_camera) or not _paint_button.button_pressed:
		return
	var selected := _selected_brush()
	var grass := selected.is_grass if selected else _brush.selected == 0
	var color := Color(0.45,1.0,0.55,0.9) if grass else Color(1.0,0.8,0.3,0.9)
	for cell in _brush_cells(_hover_cell):
		var points := _terrain._corner_points(cell)
		var heights := _terrain._corner_heights(cell)
		var polygon := PackedVector2Array()
		for index in 4:
			var world := _terrain.to_global(Vector3(points[index].x, heights[index] + 0.025, points[index].y))
			if _camera.is_position_behind(world):
				polygon.clear()
				break
			polygon.append(_camera.unproject_position(world))
		if polygon.size() != 4: continue
		overlay.draw_colored_polygon(polygon, Color(color, 0.12))
		polygon.append(polygon[0])
		overlay.draw_polyline(polygon, color, 2.0, true)

func _save_current() -> void:
	_finish_stroke()
	if is_instance_valid(_terrain) and _terrain.data:
		if _palette and not _save_palette(_palette): return
		if not _terrain.data.resource_path.is_empty() and not "::" in _terrain.data.resource_path:
			_save_data(_terrain.data)
		var error := EditorInterface.save_scene()
		if error != OK: _status.text = "场景保存失败：" + error_string(error)

func _save_data(data: TerrainData) -> void:
	if data.resource_path.is_empty() or "::" in data.resource_path:
		_status.text = "此地形数据内嵌在场景中，请使用 Ctrl+S 保存场景。"
		return
	var error := ResourceSaver.save(data, data.resource_path)
	if error == OK:
		_dirty.erase(data)
		_update_panel()
	else:
		_status.text = "地表保存失败：" + error_string(error)
		push_error(_status.text)

func _save_external_data() -> void:
	_finish_stroke()
	for data in _dirty.keys():
		_save_data(data)
	for palette in _dirty_palettes.keys(): _save_palette(palette)

func _save_palette(palette: TerrainPaintPalette) -> bool:
	if palette.resource_path.is_empty() or "::" in palette.resource_path:
		return true # The scene owns embedded configurations; avoid recursive scene saves.
	for brush in palette.brushes:
		if brush and not brush.resource_path.is_empty() and not "::" in brush.resource_path:
			var error := ResourceSaver.save(brush,brush.resource_path)
			if error != OK:
				_status.text = "画笔保存失败：" + error_string(error)
				return false
	var error := ResourceSaver.save(palette,palette.resource_path)
	if error == OK:
		_dirty_palettes.erase(palette)
		_update_panel()
		return true
	else:
		_status.text = "画笔配置保存失败：" + error_string(error)
		return false

func _apply_changes() -> void:
	_finish_stroke()

func _on_scene_saved(path: String) -> void:
	for data in _dirty.keys():
		if _dirty[data] == path and (data.resource_path.is_empty() or "::" in data.resource_path):
			_dirty.erase(data)
	for palette in _dirty_palettes.keys():
		if _dirty_palettes[palette] == path:
			if palette.resource_path.is_empty() or "::" in palette.resource_path:
				_dirty_palettes.erase(palette)
			else:
				_save_palette(palette)
	_update_panel()

func _get_unsaved_status(for_scene: String) -> String:
	if _stroking and not _before.is_empty():
		return "地表画笔有未保存的修改。"
	for data in _dirty:
		if for_scene.is_empty() or _dirty[data] == for_scene:
			return "地表画笔有未保存的修改。"
	for palette in _dirty_palettes:
		if for_scene.is_empty() or _dirty_palettes[palette] == for_scene:
			return "地表画笔配置有未保存的修改。"
	return ""
