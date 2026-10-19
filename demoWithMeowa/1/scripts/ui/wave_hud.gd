@tool
class_name WaveHUD
extends CanvasLayer

@export_group("波次连接")
@export var session: WavePrototype
## 独立于 Show UI；只显示透明背景的波次文字。
@export var enabled := true:
	set(value): enabled = value; _refresh()
@export_group("开战按键提示")
## World 独立启用；开战和休整复用同一像素键帽与屏幕位置。
@export var start_hint_enabled := false:
	set(value): start_hint_enabled = value; _refresh()

## 临时标题只占用内容显示，不改 CanvasLayer 的菜单／入场可见状态。
var presentation_active := false:
	set(value): presentation_active = value; _refresh()

## 只由当前地图的波次演出绑定；共享场景与其它地图沿用原 HUD。
var wave_style: WavePresentationSettings:
	set(value):
		wave_style = value
		_update_presentation()
		_refresh()
var _rest_hint: HBoxContainer
var _rest_caption: Label
var _rest_key: Label
var _rest_next: Label
var _start_hint: HBoxContainer
var _start_key: Label
var _start_caption: Label

@export_group("布局与文字")
## 到画面上缘的距离，逻辑像素；始终水平居中。
@export_range(0.0, 120.0, 1.0) var top_margin := 24.0:
	set(value): top_margin = maxf(value, 0.0); _update_presentation()
@export_range(12, 32, 1) var font_size := 18:
	set(value): font_size = value; _update_presentation()
@export_range(10, 24, 1) var hint_font_size := 14:
	set(value): hint_font_size = value; _update_presentation()
@export var text_color := Color(1.0, 0.95, 0.83, 0.94):
	set(value): text_color = value; _update_presentation()
## 只淡化下方操作提示，不影响主波次文字。
@export_range(0.0, 1.0, 0.05) var hint_opacity := 0.72:
	set(value): hint_opacity = value; _update_presentation()
## 细暗描边保证草地和辉光上的可读性，没有底板。
@export_range(0, 4, 1) var outline_size := 2:
	set(value): outline_size = value; _update_presentation()

@onready var _root: VBoxContainer = $Root
@onready var _title: Label = $Root/Title
@onready var _hint: Label = $Root/Hint

func _ready() -> void:
	_build_rest_hint()
	_build_start_hint()
	get_viewport().size_changed.connect(_update_presentation)
	_update_presentation()
	_refresh()

func _process(_delta: float) -> void:
	# READY 开战资格、管理界面及升级冻结不一定触发阶段通知。
	_refresh()

func _refresh() -> void:
	if not is_node_ready(): return
	if Engine.is_editor_hint():
		_root.visible = enabled and not presentation_active
		_rest_hint.hide()
		_start_hint.hide()
		_set_text("第 1 波 · 无尽 · 已完成", "休整 · 按 F 开始第 2 波")
		return
	if not is_instance_valid(session):
		_rest_hint.hide()
		_start_hint.hide()
		_root.hide()
		return
	var available := enabled and not session.combat_frozen and not (session.loadout and session.loadout.menu_open)
	var key := OS.get_keycode_string(session.interact_key)
	if start_hint_enabled and session.phase == WavePrototype.Phase.READY:
		_root.hide()
		_rest_hint.hide()
		_start_hint.visible = available and not presentation_active and not get_tree().paused and session.can_start_run()
		if _start_hint.visible:
			var caption := "开始模拟" if session.is_horde_simulation() else "开始挑战"
			if _start_key.text != key or _start_caption.text != caption:
				_start_key.text = key
				_start_caption.text = caption
				_fit_start_hint()
		return
	_start_hint.hide()
	if wave_style and wave_style.compact_clear_enabled and session.phase == WavePrototype.Phase.REST and session.is_endless() and not session.is_horde_simulation():
		_root.hide()
		_set_text("", "")
		var next_text := "开始第 %02d 波" % (session.wave + 1)
		if _rest_key.text != key or _rest_next.text != next_text:
			_rest_key.text = key
			_rest_next.text = next_text
			_fit_rest_hint()
		_rest_hint.visible = available and get_tree().get_first_node_in_group(&"gameplay_input_blockers") == null
		return
	_root.visible = available and not presentation_active
	_rest_hint.hide()
	match session.phase:
		WavePrototype.Phase.READY:
			_root.visible = _root.visible and session.can_start_run()
			_set_text("准备" + session.wave_label(1), "按 %s 开始模拟" % key if session.is_horde_simulation() else "按 %s 选择初始技能" % key)
		WavePrototype.Phase.BATTLE:
			_set_text(session.wave_label(session.wave), "真实伤害飘字 · 怪物不扣血 · 人物免伤 · ESC 结束模拟" if session.is_horde_simulation() else "")
		WavePrototype.Phase.REST:
			_set_text(session.wave_label(session.completed_waves) + " · 已完成", "休整 · 按 %s 开始第 %d 波" % [key, session.wave + 1])
		WavePrototype.Phase.RESULT:
			var title := "挑战完成 · %d / %d 波" % [session.completed_waves, session.wave_count()] if session.outcome == WavePrototype.Outcome.VICTORY else session.result_reason
			_set_text(title, "%s 重试 · ESC 返回" % OS.get_keycode_string(session.retry_key))

func _set_text(title: String, hint: String) -> void:
	if _title.text != title: _title.text = title
	if _hint.text != hint: _hint.text = hint
	_hint.visible = not hint.is_empty()

func _update_presentation() -> void:
	if not is_node_ready(): return
	_root.offset_top = top_margin
	_title.add_theme_font_size_override("font_size", font_size)
	_hint.add_theme_font_size_override("font_size", hint_font_size)
	_title.add_theme_color_override("font_color", text_color)
	_hint.add_theme_color_override("font_color", Color(text_color, text_color.a * hint_opacity))
	for label: Label in [_title, _hint]:
		label.add_theme_constant_override("outline_size", outline_size)
	if _rest_hint:
		var size := wave_style.rest_hint_font_size if wave_style else 18
		var color := wave_style.title_color if wave_style else text_color
		for label in [_rest_caption, _rest_next]:
			label.add_theme_font_size_override("font_size", size)
			label.add_theme_color_override("font_color", Color(color, 0.85))
		_fit_rest_hint()
	if _start_caption:
		_start_caption.add_theme_color_override("font_color", text_color)
		_fit_start_hint()

func _rest_label(text: String, key := false) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", preload("res://assets/fonts/press_start_2p/PressStart2P-Regular.ttf") if key else preload("res://assets/fonts/fusion_pixel/fusion-pixel-12px-monospaced-zh_hans.ttf"))
	label.add_theme_font_size_override("font_size", 16 if key else 18)
	label.add_theme_color_override("font_outline_color", Color(0.025, 0.035, 0.055, 0.9))
	label.add_theme_constant_override("outline_size", 2)
	return label

func _pixel_keycap() -> Control:
	var key := Control.new()
	key.custom_minimum_size = Vector2(28, 28)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var art := TextureRect.new()
	art.texture = preload("res://assets/meowa/ui/interaction/key.tres")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.add_child(art)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var letter := _rest_label("F", true)
	letter.name = "KeyLabel"
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.add_theme_font_size_override("font_size", 14)
	letter.add_theme_color_override("font_color", Color("243449"))
	letter.add_theme_constant_override("outline_size", 0)
	key.add_child(letter)
	letter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 对齐复用键帽的浅色顶面，避开底部阴影。
	letter.offset_top = -3.0
	letter.offset_bottom = -3.0
	return key

func _build_start_hint() -> void:
	_start_hint = HBoxContainer.new()
	_start_hint.name = "StartHint"
	_start_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_hint.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_start_hint.add_theme_constant_override("separation", 8)
	add_child(_start_hint)
	var key := _pixel_keycap()
	_start_hint.add_child(key)
	_start_key = key.get_node("KeyLabel") as Label
	_start_caption = _rest_label("开始挑战")
	_start_hint.add_child(_start_caption)
	_start_hint.minimum_size_changed.connect(_fit_start_hint)
	_start_hint.hide()

func _fit_start_hint() -> void:
	_fit_interaction_hint(_start_hint)

func _build_rest_hint() -> void:
	_rest_hint = HBoxContainer.new()
	_rest_hint.name = "RestHint"
	_rest_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rest_hint.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rest_hint.add_theme_constant_override("separation", 12)
	_rest_hint.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_rest_hint)
	_rest_caption = _rest_label("休整中")
	_rest_hint.add_child(_rest_caption)
	var key := _pixel_keycap()
	_rest_hint.add_child(key)
	_rest_key = key.get_node("KeyLabel") as Label
	_rest_next = _rest_label("开始第 02 波")
	_rest_hint.add_child(_rest_next)
	_rest_hint.minimum_size_changed.connect(_fit_rest_hint)
	_rest_hint.hide()

func _fit_rest_hint() -> void:
	_fit_interaction_hint(_rest_hint)

func _fit_interaction_hint(hint: Control) -> void:
	var viewport := get_viewport().get_visible_rect().size
	var minimum := hint.get_combined_minimum_size()
	var factor := minf(1.0, minf(viewport.y / 720.0, (viewport.x - 32.0) / maxf(minimum.x, 1.0)))
	hint.size = minimum
	hint.scale = Vector2.ONE * maxf(factor, 0.1)
	var margin := wave_style.rest_hint_bottom_margin if wave_style else 112.0
	hint.position = Vector2((viewport.x - minimum.x * factor) * 0.5, viewport.y - (margin + minimum.y * 0.5) * factor).round()
