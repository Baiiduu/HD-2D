class_name ScoreHUD
extends CanvasLayer

@export var score: RunScore
@export_range(0.1, 0.8, 0.01) var merge_window := 0.3
@export_range(0.1, 0.6, 0.01) var count_duration := 0.22
@export_range(0.0, 6.0, 0.1) var digit_lift := 2.4
@export var number_color := Color("fff1cf")
@export var award_color := Color("ffd16e")
const NUMBER_FONT := preload("res://assets/fonts/press_start_2p/PressStart2P-Regular.ttf")
var _root: Control
var _title: Label
var _number: Control
var _gain: Label
var _hint: Label
var _digits: Array[Label] = []
var _pulse := PackedFloat32Array()
var _run_id := -1
var _display := 0
var _from := 0
var _target := 0
var _count_time := 1.0
var _pending := 0
var _merge_time := 0.0
var _feedback_time := 0.0
var _kind: StringName = &"kill"
var _details := {}
## World 统一提供波次视觉配置；数值、入账与加分反馈不受标题样式影响。
var wave_style: WavePresentationSettings

func _ready() -> void:
	layer = 12
	_build()
	score.state.changed.connect(_state_changed)
	score.state.awarded.connect(_awarded)
	get_viewport().size_changed.connect(_fit)
	_fit()
	_state_changed()

func _label(text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", number_color)
	label.add_theme_color_override("font_outline_color", Color(0.025, 0.035, 0.055, 0.9))
	label.add_theme_constant_override("outline_size", 2)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label

func _build() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.size = Vector2(310, 150)
	add_child(_root)
	_title = _label("本局得分", 16)
	_title.size = Vector2(310, 25)
	_root.add_child(_title)
	_number = Control.new()
	_number.position.y = 30
	_number.size = Vector2(310, 44)
	_number.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_number)
	var line := ColorRect.new()
	line.color = Color(0.85, 0.65, 0.33, 0.75)
	line.position = Vector2(126, 77)
	line.size = Vector2(184, 1)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(line)
	_gain = _label("", 20)
	_gain.add_theme_font_override("font", NUMBER_FONT)
	_gain.add_theme_color_override("font_color", award_color)
	_gain.position.y = 90
	_gain.size = Vector2(310, 30)
	_root.add_child(_gain)
	_hint = _label("", 14)
	_hint.position.y = 122
	_hint.size = Vector2(310, 24)
	_root.add_child(_hint)
	_render(0)

func _fit() -> void:
	_root.position = Vector2(get_viewport().get_visible_rect().size.x - 410, 24)

func _state_changed() -> void:
	var state := score.state
	if _run_id != state.run_id:
		_run_id = state.run_id
		_pending = 0
		_display = state.total
		_target = state.total
		_count_time = count_duration
		_feedback_time = 0.0
		_pulse.fill(0.0)
		_gain.text = ""
		_hint.text = ""
		_render(_display)
	_title.text = "模拟 · 不计分" if state.simulation else "本局得分"
	if not state.active and _pending > 0: _commit()

func _awarded(amount: int, kind: StringName, details: Dictionary) -> void:
	if _pending == 0:
		_merge_time = 0.0
		_kind = kind
		_details = details.duplicate()
	_pending += amount
	var priority := {&"kill": 0, &"performance": 1, &"wave": 2}
	if int(priority.get(kind, 0)) >= int(priority.get(_kind, 0)):
		_kind = kind
		_details = details.duplicate()

func _commit() -> void:
	if _pending <= 0: return
	_from = _display
	_target = score.state.total
	_count_time = 0.0
	_gain.text = "+%s" % _format(_pending)
	var separate_title := wave_style and wave_style.compact_clear_enabled and score.session.is_endless()
	var wave_hint := "第 %d 波完成" % int(_details.get("wave", 0)) if not separate_title else ""
	_hint.text = wave_hint if _kind == &"wave" else ("弹射连杀 %d" % int(_details.get("kills", 0)) if _kind == &"performance" else "")
	_feedback_time = 0.85 if _kind == &"wave" else 0.62
	_pending = 0
	# 在入账时确定变化位，逐帧计数不反复触发起跳。
	var before := _format(_display)
	var after := _format(_target)
	_render(_target)
	_render(_display)
	for index in _digits.size():
		var at := before.length() - _digits.size() + index
		var target_at := after.length() - _digits.size() + index
		if at < 0 or target_at < 0 or before[at] != after[target_at]: _pulse[index] = 0.26

func _process(delta: float) -> void:
	delta /= maxf(Engine.time_scale, 0.001)
	_root.visible = not score.session.combat_frozen
	for blocker in get_tree().get_nodes_in_group(&"gameplay_input_blockers"):
		if blocker != score.session: _root.hide(); break
	if _pending > 0:
		_merge_time += delta
		if _merge_time >= merge_window: _commit()
	if _count_time < count_duration:
		_count_time = minf(count_duration, _count_time + delta)
		var progress := 1.0 - pow(1.0 - _count_time / count_duration, 3.0)
		_display = roundi(lerpf(_from, _target, progress))
		_render(_display)
	for index in _digits.size():
		_pulse[index] = maxf(0.0, _pulse[index] - delta)
		var heat := _pulse[index] / 0.26
		_digits[index].position.y = -sin((1.0 - heat) * PI) * digit_lift if heat > 0.0 else 0.0
		_digits[index].modulate = Color.WHITE.lerp(award_color / number_color, heat * 0.75)
	_feedback_time = maxf(0.0, _feedback_time - delta)
	var opacity := minf(1.0, _feedback_time / 0.22)
	_gain.modulate.a = opacity
	_hint.modulate.a = opacity
	_gain.position.y = 90.0 - (1.0 - opacity) * 5.0

func _format(value: int) -> String:
	var source := str(maxi(value, 0))
	var result := ""
	for index in source.length():
		if index > 0 and (source.length() - index) % 3 == 0: result += ","
		result += source[index]
	return result

func _render(value: int) -> void:
	var text := _format(value)
	while _digits.size() < text.length():
		var label := _label("", 28)
		label.add_theme_font_override("font", NUMBER_FONT)
		label.size = Vector2(28, 44)
		_number.add_child(label)
		_digits.append(label)
		_pulse.append(0.0)
	var cursor := 310.0
	for offset in _digits.size():
		var index := _digits.size() - offset - 1
		var at := text.length() - offset - 1
		_digits[index].visible = at >= 0
		if at < 0: continue
		cursor -= 17.0 if text[at] == "," else 29.0
		_digits[index].position.x = cursor
		_digits[index].text = text[at]
