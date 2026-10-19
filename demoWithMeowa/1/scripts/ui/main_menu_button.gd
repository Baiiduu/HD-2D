extends Button
## Native keyboard/focus/click behavior with a restrained animated gold highlight.
var emphasis := 0.0
var _press := 0.0
var _clock := 0.0

func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
	add_theme_color_override("font_color", Color("c2b9ab"))
	add_theme_color_override("font_hover_color", Color("fff0cf"))
	add_theme_color_override("font_focus_color", Color("fff0cf"))
	add_theme_color_override("font_pressed_color", Color("ffcc75"))
	add_theme_color_override("font_disabled_color", Color("827c76"))
	add_theme_font_size_override("font_size", 36)

func _process(delta: float) -> void:
	_clock += delta
	var target := 1.0 if (has_focus() or is_hovered()) and not disabled else 0.0
	emphasis = lerpf(emphasis, target, 1.0 - exp(-delta * 14.0))
	_press = lerpf(_press, 1.0 if button_pressed else 0.0, 1.0 - exp(-delta * 28.0))
	queue_redraw()

func _draw() -> void:
	var inset := 3.0 + _press * 4.0
	var rect := Rect2(Vector2(inset, 7), size - Vector2(inset * 2.0, 14))
	draw_rect(rect, Color(0.67, 0.38, 0.10, emphasis * 0.08))
	var y := size.y - 8.0
	var length := (size.x - 62.0) * (0.45 + emphasis * 0.55)
	draw_line(Vector2((size.x - length) * 0.5, y), Vector2((size.x + length) * 0.5, y), Color(0.88, 0.63, 0.28, 0.18 + emphasis * 0.63), 1.0)
	if emphasis < 0.01: return
	var p := Vector2(24.0 + _press * 3.0, size.y * 0.5)
	var radius := 4.0 + emphasis * 2.0
	draw_colored_polygon(PackedVector2Array([p + Vector2(-radius, 0), p + Vector2(0, -radius), p + Vector2(radius, 0), p + Vector2(0, radius)]), Color(1.0, 0.30, 0.14, emphasis))
	var glint := fposmod(_clock * 0.28, 1.0)
	var x := lerpf((size.x - length) * 0.5, (size.x + length) * 0.5, glint)
	draw_line(Vector2(x - 8.0, y), Vector2(x + 8.0, y), Color(1.0, 0.92, 0.67, sin(glint * PI) * emphasis * 0.75), 2.0)
