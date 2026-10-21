@tool
extends Control
## 共用正式卡片组件，人工对比场景插画与透明机制插画的融合边缘。
const CARD := preload("res://scenes/ui/growth_choice_card.tscn")
const FONT := preload("res://assets/fonts/maoken_assorted_sans/MaokenAssortedSans.ttf")
const SKILL := preload("res://data/combat/scenes/world/skills/ricochet_storm.tres")
const GROWTH := [
	preload("res://data/combat/scenes/world/growth/epic/multistrike.tres"),
	preload("res://data/combat/scenes/world/growth/epic/heavy_strike.tres")]
var _cards: Array[GrowthChoiceCard] = []
var _headings: Array[Label] = []
var _title: Label
var _hint: Label

func _ready() -> void:
	var ui_theme := Theme.new()
	ui_theme.default_font = FONT
	theme = ui_theme
	_title = _label("成长插画 · 透明底与卡纸融合")
	_hint = _label("使用正式资源 · 鼠标悬停、点击查看高亮")
	for index in 3:
		_headings.append(_label(["奔雷涌潮 · 默认", "千手 · 悬停示例", "一拳超人 · 选中示例"][index]))
		var card := CARD.instantiate() as GrowthChoiceCard
		add_child(card)
		_cards.append(card)
		var option := GrowthChoiceOption.new() if index == 0 else GROWTH[index - 1].duplicate() as GrowthChoiceOption
		option.id = StringName("preview_%d" % index)
		if index == 0:
			option.title = "%s\nLv.1" % SKILL.display_name
			option.description = SKILL.level_data(1).description
			option.icon = SKILL.icon
			option.illustration = SKILL.illustration
		else:
			option.title += "\nLv.1"
		card.configure(option, 0.96, 1.0, 0.12, 26, Color("fff0d4"), true)
		card.set_selection_key(index + 1)
		card.pressed.connect(_select.bind(index))
	_cards[1]._hovered = true
	_cards[1]._update_highlight(false)
	_cards[2].set_selected(true)
	resized.connect(_layout)
	_layout()

func _label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color("fff0d4"))
	add_child(label)
	return label

func _select(index: int) -> void:
	for candidate in _cards.size(): _cards[candidate].set_selected(candidate == index)

func _layout() -> void:
	if _cards.is_empty() or size.x <= 0.0 or size.y <= 0.0: return
	var scale_factor := minf(size.x / 1584.0, size.y / 940.0)
	var offset := (size - Vector2(1584, 940) * scale_factor) * 0.5
	_place(_title, Rect2(72, 12, 1440, 60), offset, scale_factor)
	_title.add_theme_font_size_override("font_size", roundi(36 * scale_factor))
	_place(_hint, Rect2(72, 868, 1440, 46), offset, scale_factor)
	_hint.add_theme_font_size_override("font_size", roundi(23 * scale_factor))
	for index in _cards.size():
		_place(_headings[index], Rect2(72 + index * 496, 74, 448, 34), offset, scale_factor)
		_headings[index].add_theme_font_size_override("font_size", roundi(24 * scale_factor))
		var card := _cards[index]
		_place(card, Rect2(72 + index * 496, 120, 448, 736), offset, scale_factor)
		card.configure(card.option, 0.96, 1.0, 0.12, maxi(14, roundi(26 * scale_factor)), Color("fff0d4"), true)

func _place(control: Control, rect: Rect2, offset: Vector2, factor: float) -> void:
	control.position = offset + rect.position * factor
	control.size = rect.size * factor
