class_name JournalEffects
extends Node

const BUTTON_SHADER := preload("res://shaders/journal_button.gdshader")

var ui
var amount := 0.0
var closing := false
var numbers: Dictionary = {}
var _equipped: Array[String] = []
var _attributes: Dictionary = {}
var _open_tween: Tween
var _page_tween: Tween
var _number_tween: Tween
var _flights: Dictionary = {}
var _pulses: Array[int] = []

func configure(owner_ui) -> void:
	ui = owner_ui
	_equipped = _equipment_ids()
	_attributes = ui.state.get_character_attributes()
	numbers = _attributes.duplicate()

func _kill(tween: Tween) -> void:
	if tween and tween.is_valid():
		tween.kill()

func apply_open(value: float) -> void:
	amount = value
	ui._book.scale = Vector2.ONE * lerpf(ui.open_start_scale, 1.0, value)
	ui._book.position = Vector2(0, ui.open_lift * (1.0 - value))
	ui._book.modulate.a = value
	ui._shade.color.a = ui.world_dim_amount * value

func open() -> void:
	_kill(_open_tween)
	closing = false
	ui._input_guard.show()
	if not ui.motion_enabled or ui.open_duration <= 0:
		apply_open(1.0)
		ui._input_guard.hide()
		return
	_open_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_open_tween.tween_method(apply_open, amount, 1.0, ui.open_duration * (1.0 - amount))
	_open_tween.tween_callback(func(): ui._input_guard.hide())

func close() -> void:
	if closing:
		return
	closing = true
	_kill(_open_tween)
	reset_page()
	clear_equipment_effects()
	_kill(_number_tween)
	numbers = ui.state.get_character_attributes()
	ui._input_guard.show()
	if not ui.motion_enabled or ui.close_duration <= 0:
		apply_open(0.0)
		ui._finish_close()
		return
	_open_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_open_tween.tween_method(apply_open, amount, 0.0, ui.close_duration * amount)
	_open_tween.tween_callback(ui._finish_close)

func disable_motion() -> void:
	_kill(_open_tween)
	_kill(_number_tween)
	reset_page()
	clear_equipment_effects()
	numbers = ui.state.get_character_attributes()
	apply_open(1.0 if ui.menu_open and not closing else 0.0)
	ui._input_guard.hide()
	if closing:
		ui._finish_close()
	ui._queue_refresh()

func reset_page() -> void:
	_kill(_page_tween)
	ui._content.position = Vector2.ZERO
	ui._content.modulate.a = 1.0

func turn_page(direction: int) -> void:
	if not ui.motion_enabled or ui.page_duration <= 0 or amount < 0.99 or closing:
		return
	ui._content.position.x = direction * ui.page_slide_distance
	ui._content.modulate.a = 0.0
	_page_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_page_tween.tween_property(ui._content, "position", Vector2.ZERO, ui.page_duration)
	_page_tween.tween_property(ui._content, "modulate:a", 1.0, ui.page_duration)

func attach_button(button: Button) -> void:
	if button.has_meta("journal_attached"):
		return
	button.set_meta("journal_attached", true)
	var material := ShaderMaterial.new()
	material.shader = BUTTON_SHADER
	material.set_shader_parameter("press_offset", 0.0)
	material.set_shader_parameter("brightness", 0.0)
	button.material = material
	button.mouse_entered.connect(update_button.bind(button))
	button.mouse_exited.connect(update_button.bind(button))
	button.focus_entered.connect(update_button.bind(button))
	button.focus_exited.connect(update_button.bind(button))
	button.button_down.connect(_press.bind(button, true))
	button.button_up.connect(_press.bind(button, false))

func _press(button: Button, down: bool) -> void:
	button.set_meta("journal_pressed", down)
	update_button(button)

func _icon(button: Button) -> TextureRect:
	for child in button.get_children():
		if child is TextureRect:
			return child
	return null

func update_button(button: Button) -> void:
	if not is_instance_valid(button) or not button.is_inside_tree():
		return
	var previous: Tween = button.get_meta("journal_tween") if button.has_meta("journal_tween") else null
	_kill(previous)
	var active: bool = ui.motion_enabled and ui.menu_open and not closing
	var highlighted: bool = active and (button.is_hovered() or button.has_focus()) and not button.disabled
	var pressed: bool = active and button.get_meta("journal_pressed", false)
	var offset: float = ui.button_press_distance if pressed else 0.0
	if active and button.toggle_mode and button.button_pressed:
		offset -= 4.0
	var brightness: float = ui.hover_brightness if highlighted else 0.0
	var material := button.material as ShaderMaterial
	var icon := _icon(button)
	var zoom: float = ui.hover_scale if highlighted else 1.0
	if pressed:
		zoom *= 0.98
	if icon:
		icon.pivot_offset = icon.size * 0.5
	if not active or ui.hover_duration <= 0:
		material.set_shader_parameter("press_offset", offset)
		material.set_shader_parameter("brightness", brightness)
		if icon: icon.scale = Vector2.ONE
		return
	var tween := button.create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	button.set_meta("journal_tween", tween)
	tween.tween_method(func(value: float): material.set_shader_parameter("press_offset", value), material.get_shader_parameter("press_offset"), offset, ui.hover_duration)
	tween.tween_method(func(value: float): material.set_shader_parameter("brightness", value), material.get_shader_parameter("brightness"), brightness, ui.hover_duration)
	if icon:
		tween.tween_property(icon, "scale", Vector2.ONE * zoom, ui.hover_duration)

func _equipment_ids() -> Array[String]:
	var ids: Array[String] = []
	for slot in 3:
		ids.append(ui.state.get_equipped_id(slot))
	return ids

func _slot(slot: int) -> LoadoutTile:
	for child in ui._left.get_children():
		if child is LoadoutTile and child.equipment_slot == slot:
			return child
	return null

func _source(id: String) -> TextureRect:
	for child in ui._entries.get_children():
		if child is LoadoutTile and child.payload.get("id") == id:
			return _icon(child)
	if ui._inventory_book.visible:
		for child in ui._inventory_book._grid.get_children():
			if child is LoadoutTile and child.payload.get("id") == id:
				return _icon(child)
		if ui._inventory_book.selected_item == id:
			return ui._inventory_book._hero
	return ui._detail_icon if ui.selected_equipment == id else null

func _target(slot: int) -> TextureRect:
	var tile := _slot(slot)
	if tile:
		return _icon(tile)
	return ui._inventory_book._hero if ui._inventory_book.visible else null

func _rect(control: Control) -> Rect2:
	return ui._book.get_global_transform_with_canvas().affine_inverse() * control.get_global_rect()

func state_changed() -> void:
	var current := _equipment_ids()
	var visible_equipment: bool = ui.menu_open and not closing and ui.current_page == 0 and amount >= 0.99 and ui.motion_enabled
	for slot in 3:
		if current[slot] == _equipped[slot]:
			continue
		_cancel_flight(slot)
		if visible_equipment:
			var entry: EquipmentDefinition = ui.catalog.get_equipment(current[slot])
			var source := _source(current[slot]) if entry else null
			var target := _target(slot)
			if entry and source and target and ui.equip_duration > 0:
				fly(slot, entry, _rect(source), _rect(target))
			else:
				_pulses.append(slot)
	_equipped = current
	var attributes: Dictionary = ui.state.get_character_attributes()
	if attributes != _attributes:
		_kill(_number_tween)
		var before := numbers.duplicate()
		_attributes = attributes
		if visible_equipment and ui.attribute_duration > 0:
			_number_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_number_tween.tween_method(func(value: float):
				for key in attributes:
					numbers[key] = lerpf(before.get(key, 0.0), attributes[key], value)
				update_numbers(), 0.0, 1.0, ui.attribute_duration)
		else:
			numbers = attributes.duplicate()

func update_numbers() -> void:
	for key in ui._stat_labels:
		var label: Label = ui._stat_labels[key]
		label.text = ui._number(numbers.get(key, 0.0))

func after_refresh() -> void:
	for button in ui._tabs:
		update_button(button)
	if ui._inventory_book.visible:
		_attach_tree(ui._inventory_book)
	for slot in _flights.keys():
		var target := _target(slot)
		if ui._inventory_book.visible and ui._inventory_book.selected_item != _flights[slot].id:
			_cancel_flight(slot)
		elif target:
			target.modulate.a = 0.0
	for slot in _pulses:
		pulse_slot(slot)
	_pulses.clear()

func _attach_tree(parent: Node) -> void:
	for child in parent.get_children():
		if child is Button: attach_button(child)
		_attach_tree(child)

func fly(slot: int, entry: EquipmentDefinition, start: Rect2, end: Rect2) -> void:
	var ghost: TextureRect = ui._icon(entry.icon)
	ghost.name = "FlyingEquipment"
	ghost.position = start.position
	ghost.size = start.size
	ui._fx.add_child(ghost)
	var tween := ghost.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_flights[slot] = {"id": entry.id, "ghost": ghost, "tween": tween}
	tween.tween_method(func(value: float):
		ghost.size = start.size.lerp(end.size, value)
		ghost.position = start.get_center().lerp(end.get_center(), value) - ghost.size * 0.5 + Vector2(0, -24 * sin(value * PI))
		ghost.modulate.a = clampf((1.0 - value) * 5.0, 0.0, 1.0), 0.0, 1.0, ui.equip_duration)
	tween.tween_callback(func():
		_flights.erase(slot)
		var target := _target(slot)
		if target: target.modulate.a = 1.0
		pulse_slot(slot)
		ghost.queue_free())

func pulse_slot(slot: int) -> void:
	var tile := _slot(slot)
	var target: Control = tile if tile else _target(slot)
	if not target or not ui.menu_open or closing or not ui.motion_enabled:
		return
	var pulse := Panel.new()
	pulse.name = "EquipmentArrival"
	pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = ui._outline(ui.equip_glow_color)
	pulse.add_theme_stylebox_override("panel", style)
	var rect := _rect(target)
	pulse.position = rect.position
	pulse.size = rect.size
	pulse.modulate.a = 0.0
	ui._fx.add_child(pulse)
	var tween := pulse.create_tween()
	tween.tween_property(pulse, "modulate:a", 1.0, 0.08)
	tween.tween_property(pulse, "modulate:a", 0.0, 0.22)
	tween.tween_callback(pulse.queue_free)

func _cancel_flight(slot: int) -> void:
	if not _flights.has(slot):
		return
	var flight: Dictionary = _flights[slot]
	_kill(flight.tween)
	flight.ghost.queue_free()
	_flights.erase(slot)
	var target := _target(slot)
	if target: target.modulate.a = 1.0

func clear_equipment_effects() -> void:
	for slot in _flights.keys():
		_cancel_flight(slot)
	_pulses.clear()
	for child in ui._fx.get_children():
		child.queue_free()
