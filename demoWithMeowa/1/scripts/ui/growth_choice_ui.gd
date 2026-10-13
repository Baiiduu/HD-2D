@tool
class_name GrowthChoiceUI
extends CanvasLayer

signal selection_changed(option_id: StringName)
signal choice_confirmed(option_id: StringName)
signal cancelled

const CARD := preload("res://scenes/ui/growth_choice_card.tscn")

@export_group("布局")
## 单张卡片的逻辑宽度；高度按美术比例计算，窄窗口整体缩小。
@export_range(180.0, 420.0, 1.0) var card_width := 280.0:
	set(value): card_width = maxf(value, 1.0); _update_presentation()
@export_range(0.0, 160.0, 1.0) var card_gap := 64.0:
	set(value): card_gap = maxf(value, 0.0); _update_presentation()
@export var screen_margin := Vector2(24, 24):
	set(value): screen_margin = value.max(Vector2.ZERO); _update_presentation()
@export var center_offset := Vector2.ZERO:
	set(value): center_offset = value; _update_presentation()
@export_range(180.0, 340.0, 1.0) var button_width := 244.0:
	set(value): button_width = maxf(value, 1.0); _update_presentation()

@export_group("视觉与文字")
## 只淡化卡片内页，青铜边框与光边保持清晰；0 透出世界，1 保留原底纹。
@export_range(0.0, 1.0, 0.05) var background_opacity := 0.72:
	set(value): background_opacity = value; _update_presentation()
## 选中态素材的混合强度；0 使用普通态，1 使用 Meowa 完整选中态。
@export_range(0.0, 1.0, 0.05) var selection_strength := 1.0:
	set(value): selection_strength = value; _update_presentation()
## 整屏暗化默认关闭，界面后面直接显示游戏世界。
@export_range(0.0, 0.5, 0.02) var world_dim_opacity := 0.0:
	set(value): world_dim_opacity = value; _update_presentation()
@export var title := "选择成长方向":
	set(value): title = value; _update_presentation()
@export var confirm_text := "确认":
	set(value): confirm_text = value; _update_presentation()
@export_range(24, 56, 1) var title_font_size := 40:
	set(value): title_font_size = value; _update_presentation()
@export_range(14, 28, 1) var content_font_size := 20:
	set(value): content_font_size = value; _update_presentation()
## 提高透明卡片中文字的可读性，保留原 Meowa 底纹与边框。
@export var card_text_color := Color(0.98, 0.91, 0.73):
	set(value): card_text_color = value; _update_presentation()
@export_range(20, 44, 1) var confirm_font_size := 32:
	set(value): confirm_font_size = value; _update_presentation()

@export_group("交互")
## 是否允许 Esc 取消；后续必须完成的成长选择可由调用方关闭。
@export var allow_cancel := true
@export_range(0.0, 0.5, 0.01, "suffix:s") var open_duration := 0.18
@export_range(0.0, 0.4, 0.01, "suffix:s") var hover_duration := 0.12:
	set(value): hover_duration = value; _update_presentation()

@export_group("编辑器预览")
## 只供编辑器展示，运行时须通过 present_choices 传入本轮选项。
@export var preview_options: Array[GrowthChoiceOption] = []:
	set(value):
		preview_options = value
		if is_node_ready() and Engine.is_editor_hint(): _build_cards(preview_options)

var is_open := false
var selected_index := -1
var _options: Array[GrowthChoiceOption] = []
var _cards: Array[GrowthChoiceCard] = []
var _opening: Tween

@onready var _root: Control = $Root
@onready var _content: Control = $Root/Content
@onready var _rows: Control = $Root/Content/Cards
@onready var _confirm: Button = $Root/Content/Confirm
@onready var _audio: UIAudio = $UIAudio

func _ready() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["KaiTi", "STKaiti", "SimSun", "Microsoft YaHei"])
	var ui_theme := Theme.new()
	ui_theme.default_font = font
	_root.theme = ui_theme
	get_viewport().size_changed.connect(_update_presentation)
	_confirm.pressed.connect(confirm_selection)
	if Engine.is_editor_hint():
		_build_cards(preview_options)
		_root.show()
	else:
		_root.hide()
	_update_presentation()

## 返回 false 表示没有可选项、标识无效，或已有其它界面占用输入。
## 不修改候选数据、人物属性、存档或世界暂停状态。
func present_choices(options: Array[GrowthChoiceOption]) -> bool:
	if not is_node_ready() or options.is_empty(): return false
	var blocker := get_tree().get_first_node_in_group(&"gameplay_input_blockers")
	if blocker and blocker != self: return false
	var ids: Array[StringName] = []
	var selectable := false
	for option in options:
		if not option or option.id.is_empty() or option.id in ids: return false
		ids.append(option.id)
		selectable = selectable or option.enabled
	if not selectable: return false
	_build_cards(options)
	is_open = true
	add_to_group(&"gameplay_input_blockers")
	_root.show()
	_content.modulate.a = 0.0 if open_duration > 0.0 else 1.0
	if _opening: _opening.kill()
	if open_duration > 0.0:
		_opening = create_tween()
		_opening.tween_property(_content, "modulate:a", 1.0, open_duration)
	_audio.play(&"journal_open")
	return true

func close() -> void:
	if _opening:
		_opening.kill()
		_opening = null
	is_open = false
	remove_from_group(&"gameplay_input_blockers")
	if is_instance_valid(_root): _root.hide()

func select_option(option_id: StringName) -> bool:
	if not is_open: return false
	for index in _options.size():
		if _options[index].id == option_id and _options[index].enabled:
			if selected_index == index: return true
			selected_index = index
			_refresh_selection()
			_audio.play(&"select")
			selection_changed.emit(option_id)
			return true
	return false

func get_selected_option() -> GrowthChoiceOption:
	return _options[selected_index] if is_open and selected_index >= 0 else null

func confirm_selection() -> void:
	var option := get_selected_option()
	if not option or not option.enabled: return
	var id := option.id
	close()
	_audio.play(&"confirm")
	choice_confirmed.emit(id)

func cancel() -> void:
	if not is_open or not allow_cancel: return
	close()
	_audio.play(&"cancel")
	cancelled.emit()

func _exit_tree() -> void:
	close()

func _input(event: InputEvent) -> void:
	if not is_open or Engine.is_editor_hint() or not event is InputEventKey: return
	# 在 GUI 与游戏的未处理按键之前接管按键，避免 Tab 打开背包。
	get_viewport().set_input_as_handled()
	if not event.pressed or event.echo: return
	var code: Key = event.physical_keycode if event.physical_keycode else event.keycode
	if code in [KEY_LEFT, KEY_UP]: _move_selection(-1)
	elif code in [KEY_RIGHT, KEY_DOWN]: _move_selection(1)
	elif code in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]: confirm_selection()
	elif code == KEY_ESCAPE: cancel()

func _move_selection(direction: int) -> void:
	for step in range(1, _options.size() + 1):
		var index := posmod(selected_index + direction * step, _options.size())
		if _options[index].enabled:
			select_option(_options[index].id)
			return

func _build_cards(options: Array[GrowthChoiceOption]) -> void:
	for card in _cards:
		_rows.remove_child(card)
		card.queue_free()
	_cards.clear()
	_options.clear()
	for option in options:
		if option: _options.append(option)
	selected_index = -1
	for index in _options.size():
		var option := _options[index]
		var card := CARD.instantiate() as GrowthChoiceCard
		card.name = "Choice%d" % index
		_rows.add_child(card)
		_cards.append(card)
		card.pressed.connect(select_option.bind(option.id))
		if selected_index < 0 and option.enabled: selected_index = index
	_update_presentation()
	_refresh_selection()

func _refresh_selection() -> void:
	for index in _cards.size(): _cards[index].set_selected(index == selected_index)
	_confirm.disabled = selected_index < 0

func _update_presentation() -> void:
	if not is_node_ready(): return
	var row_width := _cards.size() * card_width + maxi(_cards.size() - 1, 0) * card_gap
	var title_label: Label = _content.get_node("Header/Title")
	title_label.add_theme_font_size_override("font_size", title_font_size)
	var title_width := maxf(336.0, title_label.get_theme_font("font").get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_font_size).x + 24.0)
	var width := maxf(maxf(640.0, title_width + 296.0), row_width)
	var card_height := card_width * 1180.0 / 720.0
	_rows.position = Vector2((width - row_width) * 0.5, 116)
	_rows.size = Vector2(row_width, card_height)
	for index in _cards.size():
		var card := _cards[index]
		card.position = Vector2(index * (card_width + card_gap), 0)
		card.size = Vector2(card_width, card_height)
		card.configure(_options[index], background_opacity, selection_strength, hover_duration, content_font_size, card_text_color)
	var header: Control = _content.get_node("Header")
	header.size = Vector2(width, 100)
	title_label.text = title
	title_label.position = Vector2((width - title_width) * 0.5, 0)
	title_label.size = Vector2(title_width, 64)
	for side in ["Left", "Right"]:
		var ornament: TextureRect = header.get_node(side)
		ornament.size = Vector2(128, 54)
		ornament.position = Vector2(title_label.position.x - 148 if side == "Left" else title_label.position.x + title_width + 20, 8)
	var divider: TextureRect = header.get_node("Divider")
	divider.position = Vector2((width - 276) * 0.5, 64)
	divider.size = Vector2(276, 39)
	_confirm.text = confirm_text
	_confirm.add_theme_font_size_override("font_size", confirm_font_size)
	_confirm.size = Vector2(button_width, button_width * 186.0 / 588.0)
	_confirm.position = Vector2((width - button_width) * 0.5, _rows.position.y + card_height + 20)
	_content.size = Vector2(width, _confirm.position.y + _confirm.size.y)
	($Root/Shade as ColorRect).color = Color(0, 0, 0, world_dim_opacity)
	var viewport := get_viewport().get_visible_rect().size
	var available := (viewport - screen_margin * 2).max(Vector2.ONE)
	var factor := minf(1.0, minf(available.x / _content.size.x, available.y / _content.size.y))
	_content.scale = Vector2.ONE * factor
	var actual_size := _content.size * factor
	_content.position = ((viewport - actual_size) * 0.5 + center_offset).clamp(screen_margin, (viewport - screen_margin - actual_size).max(screen_margin))
