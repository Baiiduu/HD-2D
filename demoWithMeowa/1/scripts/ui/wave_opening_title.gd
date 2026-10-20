class_name WaveOpeningTitle
extends Control

## 开战与清波复用手绘中文字体、像素数字和金线，由同一个真实时间轴推进。
const FONT = preload("res://assets/fonts/maoken_assorted_sans/MaokenAssortedSans.ttf")
const NUMBER_FONT = preload("res://assets/fonts/press_start_2p/PressStart2P-Regular.ttf")
var _labels: Array[Label] = []
var _rest: Array[Vector2] = []
var _settings: WavePresentationSettings
var _age := 0.0
var _line_amount := 0.0
var _line_width := 300.0
var _closing := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in 3:
		var label := Label.new()
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", NUMBER_FONT if index == 1 else FONT)
		label.add_theme_color_override("font_outline_color", Color(0.025, 0.035, 0.055, 0.95))
		label.add_theme_constant_override("outline_size", 3)
		add_child(label)
		_labels.append(label)
	set_process(false)

func configure(number: int, settings: WavePresentationSettings, closing := false) -> void:
	_settings = settings
	_closing = closing
	_labels[0].text = "第"
	_labels[1].text = "%02d" % number
	_labels[2].text = "波完成" if closing else "波"
	var number_size := settings.clear_title_size if closing else settings.opening_title_size
	for index in 3:
		var font_size := number_size if index == 1 else roundi(number_size * 0.6 / 12.0) * 12
		_labels[index].add_theme_font_size_override("font_size", font_size)
		_labels[index].add_theme_color_override("font_color", settings.title_color)
	_age = 0.0
	fit_width(size.x)

func fit_width(width: float) -> void:
	size = Vector2(width, 184.0)
	if not _settings: return
	var widths: Array[float] = []
	var total := 28.0
	for label in _labels:
		var font := label.get_theme_font("font")
		var font_size := label.get_theme_font_size("font_size")
		var glyph_width := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + 8.0
		widths.append(glyph_width)
		total += glyph_width
	var x := (width - total) * 0.5
	_rest.clear()
	for index in 3:
		var label := _labels[index]
		label.size = Vector2(widths[index], 130.0)
		label.pivot_offset = label.size * 0.5
		_rest.append(Vector2(roundf(x), 0.0))
		x += widths[index] + 14.0
	_line_width = minf(width - 32.0, total * 0.62 if _closing else total + 70.0)

func render_at(age: float, duration: float) -> void:
	if not _settings: return
	_age = age
	if _closing:
		_render_clear(age, duration)
		return
	var enter_seconds := maxf(0.05, minf(_settings.opening_title_enter_seconds, duration * 0.36))
	var exit_seconds := maxf(0.05, minf(_settings.opening_title_exit_seconds, duration * 0.28))
	var leave := smoothstep(maxf(enter_seconds, duration - exit_seconds), duration, age)
	modulate.a = 1.0 - leave
	for index in 3:
		var label := _labels[index]
		var t := clampf((age - index * 0.018) / enter_seconds, 0.0, 1.0)
		var arrive := 1.0 - pow(1.0 - t, 3.0)
		var offset := Vector2((index - 1) * _settings.opening_title_travel_pixels, -8.0)
		if index == 1: offset = Vector2(0.0, -_settings.opening_title_travel_pixels * 0.42)
		label.position = (_rest[index] + offset * (1.0 - arrive) + Vector2(22.0, -12.0) * leave).round()
		# 一次落定回弹，末段精确归一；保持段没有抖动或循环缩放。
		var pop := sin(t * PI) * (1.0 - t) * (0.34 if index == 1 else 0.16)
		label.scale = Vector2.ONE * (1.0 + pop)
		label.modulate.a = smoothstep(0.0, 0.25, t)
	_line_amount = smoothstep(enter_seconds * 0.40, enter_seconds * 1.25, age)
	queue_redraw()

func _render_clear(age: float, duration: float) -> void:
	var enter_seconds := maxf(0.05, minf(_settings.clear_title_enter_seconds, duration * 0.35))
	var exit_seconds := maxf(0.05, minf(_settings.clear_title_exit_seconds, duration * 0.30))
	var arrive := smoothstep(0.0, enter_seconds, age)
	var leave := smoothstep(duration - exit_seconds, duration, age)
	modulate.a = arrive * (1.0 - leave)
	for index in 3:
		_labels[index].position = (_rest[index] + Vector2(0.0, (1.0 - arrive) * 10.0 - leave * 4.0)).round()
		_labels[index].scale = Vector2.ONE
		_labels[index].modulate.a = 1.0
	_line_amount = arrive
	queue_redraw()

func _draw() -> void:
	if not _settings or _line_amount <= 0.0: return
	var ink := _settings.battle_color
	var start := Vector2((size.x - _line_width) * 0.5, 108.0 if _closing else 135.0)
	var end := start + Vector2(_line_width * _line_amount, 0.0 if _closing else -8.0 * _line_amount)
	draw_line(start.round(), end.round(), Color(ink, 0.12 if _closing else 0.18), 4.0 if _closing else 8.0)
	draw_line(start.round(), end.round(), ink, 2.0 if _closing else 3.0)
	draw_line((end - Vector2(18.0, 0.0)).round(), end.round(), _settings.title_color, 2.0)
	if _closing: return
	# 落定时两侧仅六枚短碎光，随后完全消散；不铺满战斗中心。
	var burst := clampf((_age - _settings.opening_title_enter_seconds * 0.5) / 0.28, 0.0, 1.0)
	if burst <= 0.0 or burst >= 1.0: return
	for index in 6:
		var side := -1.0 if index < 3 else 1.0
		var angle := float(index % 3 - 1) * 0.62
		var direction := Vector2(side * cos(angle), sin(angle))
		var point := Vector2(size.x * 0.5 + side * _line_width * 0.43, 68.0) + direction * (12.0 + burst * 28.0)
		var length := lerpf(12.0, 3.0, burst)
		draw_line(point.round(), (point + direction * length).round(), Color(ink, (1.0 - burst) * 0.85), 2.0)
