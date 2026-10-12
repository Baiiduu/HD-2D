class_name ItemQuickbar
extends Control

signal slot_selected(item_id: String)

const SLOT_SHADER := preload("res://shaders/skill_hud.gdshader")
@export var slot_texture: Texture2D = preload("res://assets/meowa/ui/inventory/controls/quick-slot.png")
@export var selected_slot_texture: Texture2D = preload("res://assets/meowa/ui/inventory/controls/quick-slot-active.png")
@export_range(40,96,1) var slot_size := 68.0
@export_range(0,20,1) var slot_spacing := 6
@export_range(8,80,1) var bottom_margin := 24.0
@export_range(0.0,1.0,0.05) var background_opacity := 0.65
var state: LoadoutState
var audio: UIAudio
var reserved_hud: Control
var _slots := HBoxContainer.new()
var _queued := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slots)
	get_viewport().size_changed.connect(update_layout)

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
		tile.tooltip_text = "%d：%s\n拖入背包物品，右键移出快捷栏。" % [index + 1, entry.display_name if entry else "空物品槽"]
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
	state.select_quick_slot(index)
	if audio: audio.play(&"select")
	slot_selected.emit(state.get_quick_slots()[index])

func _unhandled_key_input(event: InputEvent) -> void:
	if not state or get_tree().get_first_node_in_group(&"gameplay_input_blockers"):
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
