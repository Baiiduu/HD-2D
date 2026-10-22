extends PanelContainer
## One reusable read-only row; arbitrary cell counts and a conditional subtitle.
const KINETIC = preload("res://scripts/ui/settings_kinetic_theme.gd")
const SYMBOL = preload("res://shaders/ui/attribute_symbol.gdshader")
const ICONS := {
	"sword": preload("res://assets/meowa/ui/journal/symbols/sword.png"),
	"shield": preload("res://assets/meowa/ui/journal/symbols/shield.png"),
	"heart": preload("res://assets/meowa/ui/journal/symbols/heart.png"),
	"star": preload("res://assets/meowa/ui/journal/symbols/star.png"),
	"boot": preload("res://assets/meowa/ui/journal/symbols/boot.png"),
}
static var _symbol_material: ShaderMaterial
var _numbers: Array[Label] = []
var _status: Label
var _normal: StyleBoxFlat
var _hover: StyleBoxFlat

func configure(row: Dictionary) -> void:
	name = String(row.id).to_pascal_case()
	custom_minimum_size.y = 58
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_normal = KINETIC.field(Color("151c28"), Color("48525d"))
	_normal.content_margin_left = 17
	_normal.content_margin_right = 12
	_normal.content_margin_top = 7
	_normal.content_margin_bottom = 7
	_hover = _normal.duplicate()
	_hover.border_color = KINETIC.CORAL
	_hover.bg_color = Color("24232d")
	add_theme_stylebox_override("panel", _normal)
	mouse_entered.connect(func(): add_theme_stylebox_override("panel", _hover))
	mouse_exited.connect(func(): add_theme_stylebox_override("panel", _normal))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)
	var icon := TextureRect.new()
	icon.texture = ICONS.get(row.get("icon", "star"), ICONS.star)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.custom_minimum_size = Vector2(32, 32)
	icon.modulate = KINETIC.IVORY
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not _symbol_material:
		_symbol_material = ShaderMaterial.new()
		_symbol_material.shader = SYMBOL
	icon.material = _symbol_material
	line.add_child(icon)
	var names := VBoxContainer.new()
	names.custom_minimum_size.x = 160
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	names.add_theme_constant_override("separation", -1)
	line.add_child(names)
	var label := _label(row.label, 23)
	names.add_child(label)
	_status = _label("", 14)
	_status.add_theme_color_override("font_color", Color("c4ac9b"))
	names.add_child(_status)
	var cells := HBoxContainer.new()
	cells.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cells.add_theme_constant_override("separation", 6)
	line.add_child(cells)
	for index in row["values"].size():
		var cell := PanelContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var single: bool = row["values"].size() == 1
		var skin := KINETIC.field(KINETIC.IVORY if single else Color("0f1722"), Color("8c8881"))
		skin.set_content_margin_all(4)
		cell.add_theme_stylebox_override("panel", skin)
		cells.add_child(cell)
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", -2)
		cell.add_child(stack)
		var headings: Array = row.get("headings", [])
		if index < headings.size():
			var heading := _label(headings[index], 13)
			heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			heading.add_theme_color_override("font_color", Color("c4b8a8"))
			stack.add_child(heading)
		var number := _label("", 22 if single else 20)
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.add_theme_color_override("font_color", Color("111925") if single else KINETIC.IVORY)
		stack.add_child(number)
		_numbers.append(number)
	set_readout(row)

func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func set_readout(row: Dictionary) -> void:
	for index in _numbers.size(): _numbers[index].text = row["values"][index]
	_status.text = row.status
	_status.visible = not row.status.is_empty()
	tooltip_text = row.label + "\n" + row.detail.strip_edges()

func _make_custom_tooltip(for_text: String) -> Object:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", KINETIC.field(Color("111822"), KINETIC.CORAL))
	var text := _label(for_text, 18)
	text.custom_minimum_size.x = 390
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)
	return box
