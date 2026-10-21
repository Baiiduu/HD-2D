@tool
class_name GrowthChoiceCard
extends Button

const BACK_ICON := preload("res://assets/meowa/ui/journal/symbols/star.png")
const LEGACY_FRAME := preload("res://assets/meowa/ui/upgrade/card.png")
const LEGACY_SELECTED := preload("res://assets/meowa/ui/upgrade/card-selected.png")
const LEGACY_SOCKET := preload("res://assets/meowa/ui/upgrade/icon-slot.png")
const INK_SIZE := Vector2(448, 736)
const INK_FRAMES := [
	preload("res://assets/meowa/ui/growth_cards/full/common.png"),
	preload("res://assets/meowa/ui/growth_cards/full/epic.png"),
	preload("res://assets/meowa/ui/growth_cards/full/legendary.png"),
	preload("res://assets/meowa/ui/growth_cards/full/mythic.png")]
const INK_SELECTED := [
	preload("res://assets/meowa/ui/growth_cards/full/common-selected.png"),
	preload("res://assets/meowa/ui/growth_cards/full/epic-selected.png"),
	preload("res://assets/meowa/ui/growth_cards/full/legendary-selected.png"),
	preload("res://assets/meowa/ui/growth_cards/full/mythic-selected.png")]

var option: GrowthChoiceOption
var selected := false
var hover_duration := 0.12
var selection_strength := 1.0
var _hovered := false
var _highlight: Tween
var _revealed := true
var _ink_style := false
var _content_font_size := 20
var _body_font_size := 20

@onready var _frame: TextureRect = $Frame
@onready var _socket: TextureRect = $IconSlot
@onready var _icon: TextureRect = $IconSlot/Icon
@onready var _title: Label = $Title
@onready var _description: Label = $Description
@onready var _category: Label = $Category
@onready var _shortcut: Label = $Shortcut
@onready var _level: Label = $Level
@onready var _gain: Label = $Gain

func _ready() -> void:
	resized.connect(_layout)
	mouse_entered.connect(func(): _hovered = true; _update_highlight())
	mouse_exited.connect(func(): _hovered = false; _update_highlight())
	_layout()
	_update_highlight(false)

func configure(value: GrowthChoiceOption, opacity: float, strength: float, duration: float, font_size: int, text_color := Color(0.98, 0.91, 0.73), ink_style := false) -> void:
	option = value
	_ink_style = ink_style
	_content_font_size = font_size
	_body_font_size = font_size
	tooltip_text = value.description.strip_edges()
	disabled = not value.enabled or not _revealed
	selection_strength = strength
	hover_duration = duration
	_title.text = value.title
	_level.text = ""
	if _ink_style:
		# Existing choices already separate their display name and rank with a newline.
		var title_lines := value.title.split("\n", true, 1)
		_title.text = title_lines[0]
		if title_lines.size() > 1: _level.text = title_lines[1]
	_description.text = value.description.replace("\n\n", "\n").strip_edges()
	_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_gain.text = ""
	if _ink_style: _prepare_ink_description(value.description)
	_title.visible = not value.title.is_empty()
	_description.visible = not value.description.is_empty()
	_icon.texture = value.icon
	_icon.visible = value.icon != null
	# An open editor can retain null for a newly added export until reloaded.
	var category: Variant = value.get("category")
	if category == null: category = GrowthChoiceOption.Category.GENERAL
	_category.text = ["", "学习技能", "技能升级", "全局增益"][category]
	if value.get("ricochet_growth") == true: _category.text = "弹射成长"
	if value.hide_category: _category.text = "史诗" if value.epic else ""
	var skin := _frame.material as ShaderMaterial
	if _ink_style:
		var rarity := clampi(value.get_card_rarity(), 0, 3)
		_frame.texture = INK_FRAMES[rarity]
		skin.set_shader_parameter("selected_texture", INK_SELECTED[rarity])
		_socket.texture = null
		_category.text = ["普通", "史诗", "传说", "神话"][rarity]
	else:
		_frame.texture = LEGACY_FRAME
		skin.set_shader_parameter("selected_texture", LEGACY_SELECTED)
		_socket.texture = LEGACY_SOCKET
		_description.max_lines_visible = 7
	skin.set_shader_parameter("edge_only_selection", _ink_style)
	skin.set_shader_parameter("inner_rect", Vector4(0.105, 0.09, 0.79, 0.81) if _ink_style else Vector4(0.118, 0.080, 0.764, 0.843))
	skin.set_shader_parameter("page_color", Color("080f1b") if _ink_style else Color(0.035, 0.045, 0.024))
	_category.visible = not _category.text.is_empty()
	_title.add_theme_font_size_override("font_size", font_size + 4)
	_description.add_theme_font_size_override("font_size", font_size)
	_category.add_theme_font_size_override("font_size", font_size - 2)
	_shortcut.add_theme_font_size_override("font_size", font_size - 3)
	for label in [_title, _description, _category, _shortcut, _level]:
		label.add_theme_color_override("font_color", text_color)
		label.add_theme_color_override("font_shadow_color", Color(0.05, 0.08, 0.03, 0.9))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
	if _ink_style:
		_title.add_theme_font_size_override("font_size", font_size + 7)
		_level.add_theme_font_size_override("font_size", font_size - 2)
		_level.add_theme_color_override("font_color", Color("91d9f2"))
		_gain.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_gain.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_gain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	(_frame.material as ShaderMaterial).set_shader_parameter("background_opacity", opacity)
	self_modulate = Color(1, 1, 1, 0.45 if not value.enabled else 1.0)
	_update_highlight(false)
	set_revealed(_revealed)
	_layout()

func set_selection_key(number: int) -> void:
	_shortcut.text = "[%d] 选择" % number

func set_revealed(value: bool) -> void:
	_revealed = value
	if not is_node_ready() or not option: return
	disabled = not option.enabled or not value
	_title.visible = value and not option.title.is_empty()
	_description.visible = value and not _description.text.is_empty()
	_category.visible = value and not _category.text.is_empty()
	_shortcut.visible = value and not _ink_style
	_level.visible = value and _ink_style and not _level.text.is_empty()
	_gain.visible = value and _ink_style and not _gain.text.is_empty()
	var has_illustration := value and _ink_style and option.illustration != null
	_icon.texture = (option.illustration if has_illustration else option.icon) if value else BACK_ICON
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED if has_illustration else TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	(_icon.material as ShaderMaterial).set_shader_parameter("blend_edges", has_illustration)
	_icon.visible = _icon.texture != null
	_update_highlight(false)
	if _ink_style: _layout()

func set_selected(value: bool) -> void:
	selected = value
	_update_highlight()

func _exit_tree() -> void:
	if _highlight:
		_highlight.kill()
		_highlight = null

func _update_highlight(animate := true) -> void:
	if not is_node_ready(): return
	if _highlight: _highlight.kill()
	var skin := _frame.material as ShaderMaterial
	var amount := 0.0
	if not disabled and _revealed:
		amount = selection_strength if selected else selection_strength * (0.28 if _ink_style else 0.45) if _hovered else 0.0
	if animate and hover_duration > 0.0 and not Engine.is_editor_hint():
		_highlight = create_tween()
		_highlight.tween_method(func(value: float): skin.set_shader_parameter("selected_mix", value), float(skin.get_shader_parameter("selected_mix")), amount, hover_duration)
	else:
		skin.set_shader_parameter("selected_mix", amount)

func _layout() -> void:
	if not is_node_ready(): return
	_frame.size = size
	pivot_offset = size * 0.5
	if _ink_style:
		_layout_ink()
		return
	var diameter := size.x * 0.42
	_socket.size = Vector2.ONE * diameter
	_socket.position = Vector2((size.x - diameter) * 0.5, size.y * 0.13)
	_icon.position = Vector2.ONE * diameter * 0.12
	_icon.size = Vector2.ONE * diameter * 0.76
	_category.position = Vector2(size.x * 0.14, size.y * 0.055)
	_category.size = Vector2(size.x * 0.72, size.y * 0.065)
	_title.position = Vector2(size.x * 0.13, size.y * 0.375)
	_title.size = Vector2(size.x * 0.74, size.y * 0.14)
	_description.position = Vector2(size.x * 0.16, size.y * 0.52)
	_description.size = Vector2(size.x * 0.68, size.y * 0.34)
	_shortcut.position = Vector2(size.x * 0.14, size.y * 0.87)
	_shortcut.size = Vector2(size.x * 0.72, size.y * 0.055)

func _layout_ink() -> void:
	var has_illustration := option and option.illustration != null and _revealed
	_ink_rect(_category, Rect2(306, 40, 96, 36))
	_ink_rect(_socket, Rect2(48, 82, 352, 310) if has_illustration else Rect2(66, 104, 316, 260))
	_ink_rect(_title, Rect2(60, 400, 328, 50))
	_ink_rect(_level, Rect2(64, 454, 320, 28))
	_fit_heading(_title, _content_font_size + 7)
	_fit_heading(_level, _content_font_size - 2)
	_layout_ink_text()
	_description.max_lines_visible = -1
	_description.tooltip_text = option.description if option else ""
	_icon.size = _socket.size if has_illustration else Vector2.ONE * minf(size.x * 0.34, _socket.size.y)
	_icon.position = (_socket.size - _icon.size) * 0.5
	(_icon.material as ShaderMaterial).set_shader_parameter("display_size", _icon.size)

func _fit_heading(label: Label, preferred: int) -> void:
	var font := label.get_theme_font("font")
	var font_size := preferred
	while font_size > 16 and font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > label.size.x:
		font_size -= 1
	label.add_theme_font_size_override("font_size", font_size)

func _layout_ink_text() -> void:
	_ink_rect(_description, Rect2(64, 490, 320, 164))
	var body := Rect2(_description.position, _description.size)
	var gap := 6.0 if not _description.text.is_empty() and not _gain.text.is_empty() else 0.0
	# 每次从配置字号重新排版；改小窗口后再放大，不会永久停留在小字。
	var font_size := _body_font_size
	var minimum := mini(font_size, 14)
	while font_size > minimum and _text_height(_description, body.size.x, font_size) + _text_height(_gain, body.size.x, font_size) + gap > body.size.y:
		font_size -= 1
	for label in [_description, _gain]: label.add_theme_font_size_override("font_size", font_size)
	var summary_height := _text_height(_description, body.size.x, font_size)
	_description.size.y = summary_height
	_gain.position = body.position + Vector2(0, summary_height + gap)
	_gain.size = Vector2(body.size.x, maxf(0.0, body.size.y - summary_height - gap))

func get_body_font_size() -> int:
	return _description.get_theme_font_size("font_size")

## 同一轮卡牌共用正文与数值字号，不影响标题、品级与等级的层级。
func set_body_font_size(font_size: int) -> void:
	_body_font_size = font_size
	_layout_ink_text()

func _text_height(label: Label, width: float, font_size: int) -> float:
	if label.text.is_empty(): return 0.0
	var paragraph := TextParagraph.new()
	paragraph.width = width
	paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	paragraph.add_string(label.text, label.get_theme_font("font"), font_size)
	return paragraph.get_size().y + maxf(0.0, paragraph.get_line_count() - 1) * label.get_theme_constant("line_spacing") + 2.0

func _ink_rect(control: Control, rect: Rect2) -> void:
	var factor := size / INK_SIZE
	control.position = rect.position * factor
	control.size = rect.size * factor

func _prepare_ink_description(description: String) -> void:
	if description.contains("\n\n"):
		var sections := description.split("\n\n", true, 1)
		_description.text = sections[0]
		_gain.text = sections[1]
		return
	# 兼容预览及外部技能尚未分区的旧说明。
	var lines := description.split("\n")
	var values: PackedStringArray = []
	for line in lines:
		if line.contains(" → "): values.append(line)
	if values.size() == 1:
		_gain.text = values[0]
		lines.remove_at(lines.find(values[0]))
		_description.text = "\n".join(lines).strip_edges()
	else:
		# Keep every benefit and cap; put labels and values on the same line.
		var compact := PackedStringArray()
		for line in lines:
			if line.contains(" → ") and not compact.is_empty(): compact[-1] += " " + line
			else: compact.append(line)
		_description.text = "\n".join(compact)
