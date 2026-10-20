class_name ItemQuickbar
extends Control

signal slot_selected(item_id: String)

const SLOT_SHADER := preload("res://shaders/ui/skill_hud.gdshader")
@export var slot_texture: Texture2D = preload("res://assets/meowa/ui/inventory/controls/quick-slot.png")
@export var selected_slot_texture: Texture2D = preload("res://assets/meowa/ui/inventory/controls/quick-slot-active.png")
@export_range(40,96,1) var slot_size := 68.0
@export_range(0,20,1) var slot_spacing := 6
@export_range(8,80,1) var bottom_margin := 24.0
@export_range(0.0,1.0,0.05) var background_opacity := 0.65
@export_group("悬浮名称提示")
## 仅显示物品名称；完整说明在背包页查看，空槽不弹提示。
@export var show_item_name := true:
	set(value): show_item_name = value; _update_name_hint()
@export_range(12,20,1) var name_font_size := 16:
	set(value): name_font_size = value; _update_name_hint()
## 名称最大宽度，逻辑像素；过长名称省略，保持一行。
@export_range(80,240,8) var name_max_width := 160.0:
	set(value): name_max_width = value; _update_name_hint()
## 0 为全透明背景；增加少量暗底以方便在明亮地面上阅读。
@export_range(0.0,0.5,0.05) var name_background_opacity := 0.0:
	set(value): name_background_opacity = value; _update_name_hint()
var state: LoadoutState
var player_access_enabled := true
var audio: UIAudio
var reserved_hud: Control
var _slots := HBoxContainer.new()
var _queued := false
var _name_panel: PanelContainer
var _name_label: Label
var _hovered_slot := -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slots)
	_name_panel = PanelContainer.new()
	_name_panel.name = "ItemNameHint"
	_name_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_panel)
	_name_label = _label("",name_font_size)
	_name_panel.add_child(_name_label)
	_update_name_hint()
	get_viewport().size_changed.connect(update_layout)

func _update_name_hint() -> void:
	if not _name_panel: return
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.05,0.07,0.06,name_background_opacity)
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		panel.set_content_margin(side,4.0 if side in [SIDE_LEFT,SIDE_RIGHT] else 2.0)
	_name_panel.add_theme_stylebox_override("panel",panel)
	_name_label.add_theme_font_size_override("font_size",name_font_size)
	if not state or _hovered_slot < 0 or _hovered_slot >= _slots.get_child_count():
		_name_panel.hide()
		return
	_name_label.text = _name_hint(state.catalog.get_inventory_entry(state.get_quick_slots()[_hovered_slot]))
	if _name_label.text.is_empty():
		_name_panel.hide()
		return
	_name_panel.reset_size()
	var tile: Control = _slots.get_child(_hovered_slot)
	var local := _slots.position + tile.position + Vector2((tile.size.x-_name_panel.size.x)*0.5,-_name_panel.size.y-8)
	var point := get_global_transform() * local
	var viewport := get_viewport().get_visible_rect().size
	point.x = clampf(point.x,12,viewport.x-_name_panel.size.x*get_global_transform().get_scale().x-12)
	_name_panel.position = (get_global_transform().affine_inverse() * point).round()
	_name_panel.show()

func _show_name(index: int) -> void:
	_hovered_slot = index
	_update_name_hint()

func _hide_name(index: int) -> void:
	if _hovered_slot != index: return
	_hovered_slot = -1
	_name_panel.hide()

func _name_hint(entry: Resource) -> String:
	if not entry or not show_item_name: return ""
	var words: String = entry.display_name.replace("\n"," ")
	var font := get_theme_font("font")
	if font.get_string_size(words,HORIZONTAL_ALIGNMENT_LEFT,-1,name_font_size).x <= name_max_width: return words
	while words.length() > 1 and font.get_string_size(words+"…",HORIZONTAL_ALIGNMENT_LEFT,-1,name_font_size).x > name_max_width:
		words = words.substr(0,words.length()-1)
	return words+"…"

func bind_state(value: LoadoutState, skill_hud: Control) -> void:
	state = value
	reserved_hud = skill_hud
	state.changed.connect(_queue_refresh)
	refresh()

func _queue_refresh() -> void:
	if _queued: return
	_queued = true
	refresh.call_deferred()

func refresh() -> void:
	_queued = false
	if not state: return
	for child in _slots.get_children():
		_slots.remove_child(child)
		child.queue_free()
	_slots.add_theme_constant_override("separation", slot_spacing)
	var ids := state.get_quick_slots()
	for index in ids.size():
		var id := ids[index]
		var entry := state.catalog.get_inventory_entry(id)
		var tile := LoadoutTile.new()
		tile.audio = audio
		tile.name = "ItemSlot%d" % index
		tile.loadout = state
		tile.quick_slot = index
		tile.custom_minimum_size = Vector2.ONE * slot_size
		# 默认纸面 Tooltip 不用于地图上的快捷栏。
		tile.tooltip_text = ""
		tile.mouse_entered.connect(_show_name.bind(index))
		tile.mouse_exited.connect(_hide_name.bind(index))
		for style in ["normal","hover","pressed","focus"]:
			tile.add_theme_stylebox_override(style, StyleBoxEmpty.new())
		tile.pressed.connect(_select.bind(index))
		tile.dropped.connect(func(data):
			var success := state.assign_item(data.id,index)
			if audio: audio.play(&"item_drop" if success else &"error"))
		tile.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
				var success := state.clear_quick_slot(index)
				if audio: audio.play(&"cancel" if success else &"error")
				tile.accept_event())
		_slots.add_child(tile)
		var frame := _image(selected_slot_texture if state.active_quick_slot == index else slot_texture)
		frame.name = "Frame"
		frame.stretch_mode = TextureRect.STRETCH_SCALE
		frame.material = ShaderMaterial.new()
		(frame.material as ShaderMaterial).shader = SLOT_SHADER
		(frame.material as ShaderMaterial).set_shader_parameter("glow_strength",1.0)
		(frame.material as ShaderMaterial).set_shader_parameter("background_opacity",background_opacity)
		tile.add_child(frame)
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if entry:
			tile.drag_icon = entry.icon
			tile.payload = {"kind":"equipment" if entry is EquipmentDefinition else "item","id":id}
			var icon := _image(entry.icon)
			icon.position = Vector2.ONE * 10
			icon.size = Vector2.ONE * (slot_size-20)
			tile.add_child(icon)
		var number := _label(str(index+1),15)
		number.position = Vector2(6,2)
		tile.add_child(number)
		if entry is ItemDefinition and entry.stackable:
			var amount := _label(str(state.get_quantity(id)),15)
			amount.name = "Quantity"
			amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			amount.position = Vector2(5,slot_size-24)
			amount.size = Vector2(slot_size-12,20)
			tile.add_child(amount)
	update_layout.call_deferred()

func _image(texture: Texture2D) -> TextureRect:
	var image := TextureRect.new()
	image.texture = texture
	image.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",Color("f4e7cb"))
	label.add_theme_color_override("font_outline_color",Color("17180f"))
	label.add_theme_constant_override("outline_size",3)
	return label

func _select(index: int) -> void:
	if not player_access_enabled: return
	state.select_quick_slot(index)
	if audio: audio.play(&"select")
	slot_selected.emit(state.get_quick_slots()[index])

func _unhandled_key_input(event: InputEvent) -> void:
	if not player_access_enabled or not state or get_tree().get_first_node_in_group(&"gameplay_input_blockers"):
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var index := int(event.physical_keycode) - int(KEY_1)
		if index >= 0 and index < LoadoutState.QUICK_SLOT_COUNT:
			_select(index)
			get_viewport().set_input_as_handled()

func update_layout() -> void:
	if not is_inside_tree(): return
	var viewport := get_viewport().get_visible_rect().size
	var width := slot_size * LoadoutState.QUICK_SLOT_COUNT + slot_spacing * (LoadoutState.QUICK_SLOT_COUNT-1)
	var factor := minf(1.0,(viewport.x-32.0)/width)
	size = Vector2(width,slot_size)
	_slots.size = size
	scale = Vector2.ONE * factor
	position = Vector2((viewport.x-width*factor)*0.5,viewport.y-bottom_margin-slot_size*factor)
	# 窄窗口只上移物品栏，保持原技能栏的样式与位置。
	if is_instance_valid(reserved_hud) and reserved_hud.visible and get_global_rect().intersects(reserved_hud.get_global_rect().grow(8)):
		position.y = reserved_hud.get_global_rect().position.y-slot_size*factor-12
	_update_name_hint()
