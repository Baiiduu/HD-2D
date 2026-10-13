@tool
class_name WaveHUD
extends CanvasLayer

@export_group("波次连接")
@export var session: WavePrototype
## 独立于 Show UI；只显示透明背景的波次文字。
@export var enabled := true:
	set(value): enabled = value; _refresh()

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
	get_viewport().size_changed.connect(_update_presentation)
	_update_presentation()
	_refresh()

func _process(_delta: float) -> void:
	# READY 接近入口、管理界面及升级冻结不一定触发阶段通知。
	_refresh()

func _refresh() -> void:
	if not is_node_ready(): return
	_root.visible = enabled
	if Engine.is_editor_hint():
		_set_text("第 1 波 · 无尽 · 已完成", "休整 · 按 F 开始第 2 波")
		return
	if not is_instance_valid(session):
		_root.hide()
		return
	_root.visible = enabled and not session.combat_frozen and not (session.loadout and session.loadout.menu_open)
	var key := OS.get_keycode_string(session.interact_key)
	match session.phase:
		WavePrototype.Phase.READY:
			_root.visible = _root.visible and session.can_start_run()
			_set_text("准备" + session.wave_label(1), "按 %s 开始挑战" % key)
		WavePrototype.Phase.BATTLE:
			_set_text(session.wave_label(session.wave), "")
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
