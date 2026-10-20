extends RefCounted
## Meowa foreground artwork; the World viewport remains the menu background.
const RED = preload("res://assets/meowa/ui/settings_kinetic/brush_red.png")
const DARK = preload("res://assets/meowa/ui/settings_kinetic/brush_dark.png")
const INK = preload("res://assets/meowa/ui/settings_kinetic/content_ink.png")
const SWEEP = preload("res://assets/meowa/ui/settings_kinetic/sword_sweep.png")
const FILL = preload("res://assets/meowa/ui/settings_kinetic/slider_fill.png")
const TRACK = preload("res://assets/meowa/ui/settings_kinetic/slider_track.png")
const DIAMOND = preload("res://assets/meowa/ui/settings_kinetic/slider_diamond.png")
const ICONS = [
	preload("res://assets/meowa/ui/settings_kinetic/icon_audio.png"),
	preload("res://assets/meowa/ui/settings_kinetic/icon_debug.png"),
	preload("res://assets/meowa/ui/settings_kinetic/icon_display.png"),
	preload("res://assets/meowa/ui/settings_kinetic/icon_camera.png"),
	preload("res://assets/meowa/ui/settings_kinetic/icon_controls.png"),
	preload("res://assets/meowa/ui/settings_kinetic/icon_leaderboard.png")]
const IVORY = Color("fff0d4")
const CORAL = Color("ff5650")

static func brush(texture: Texture2D, tint := Color.WHITE) -> StyleBoxTexture:
	var skin := StyleBoxTexture.new()
	skin.texture = texture
	skin.modulate_color = tint
	skin.content_margin_left = 22
	skin.content_margin_right = 22
	skin.content_margin_top = 9
	skin.content_margin_bottom = 9
	return skin

static func field(color: Color, border := Color("687680")) -> StyleBoxFlat:
	var skin := StyleBoxFlat.new()
	skin.bg_color = color
	skin.border_color = border
	skin.set_border_width_all(1)
	skin.set_content_margin_all(10)
	skin.skew = Vector2(-0.12, 0)
	return skin

static func make() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 20
	for type in ["Label", "Button", "CheckBox", "OptionButton", "LineEdit", "PopupMenu"]:
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			theme.set_color(state, type, IVORY)
		theme.set_color("font_disabled_color", type, Color("79818b"))
	for state in ["normal", "disabled"]:
		theme.set_stylebox(state, "Button", field(Color("151d29"), Color("48505d")))
	theme.set_stylebox("hover", "Button", field(Color("30303a"), CORAL))
	theme.set_stylebox("pressed", "Button", field(Color("733135"), CORAL))
	theme.set_stylebox("focus", "Button", field(Color.TRANSPARENT, IVORY))
	theme.set_type_variation("SettingsTab", "Button")
	for state in ["normal", "focus", "disabled"]:
		theme.set_stylebox(state, "SettingsTab", brush(DARK))
	theme.set_stylebox("hover", "SettingsTab", brush(DARK, Color(1.3, 1.3, 1.3)))
	for state in ["pressed", "hover_pressed"]:
		theme.set_stylebox(state, "SettingsTab", brush(RED))
		theme.set_color("font_" + state + "_color", "SettingsTab", Color("111721"))
	for state in ["normal", "focus", "disabled", "hover", "pressed", "hover_pressed"]:
		theme.get_stylebox(state, "SettingsTab").content_margin_left = 58
	theme.set_color("icon_pressed_color", "SettingsTab", Color("111721"))
	theme.set_color("icon_hover_pressed_color", "SettingsTab", Color("111721"))
	theme.set_font_size("font_size", "SettingsTab", 34)
	theme.set_constant("h_separation", "SettingsTab", 20)
	theme.set_constant("icon_max_width", "SettingsTab", 36)
	theme.set_type_variation("SettingsResume", "Button")
	for state in ["normal", "pressed", "hover", "focus"]:
		theme.set_stylebox(state, "SettingsResume", brush(RED, Color(1.15, 1.15, 1.15) if state == "hover" else Color.WHITE))
		theme.set_color("font_" + ("color" if state == "normal" else state + "_color"), "SettingsResume", Color("111721"))
	theme.set_font_size("font_size", "SettingsResume", 38)
	theme.set_type_variation("SettingsReturn", "Button")
	for state in ["normal", "disabled", "focus"]:
		theme.set_stylebox(state, "SettingsReturn", brush(DARK))
	theme.set_stylebox("hover", "SettingsReturn", brush(DARK, Color(1.3, 1.3, 1.3)))
	theme.set_stylebox("pressed", "SettingsReturn", brush(DARK, Color(1.15, 0.9, 0.9)))
	theme.set_font_size("font_size", "SettingsReturn", 24)
	for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		theme.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())
	for icon in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		theme.set_icon(icon, "CheckBox", ThemeDB.get_default_theme().get_icon(icon, "CheckBox"))
	theme.set_color("checkbox_checked_color", "CheckBox", CORAL)
	theme.set_color("checkbox_unchecked_color", "CheckBox", IVORY)
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		theme.set_stylebox(state, "OptionButton", field(Color("141c28"), CORAL if state == "hover" else Color("576370")))
	for state in ["normal", "read_only", "focus"]:
		theme.set_stylebox(state, "LineEdit", field(Color("111925"), Color("576370")))
	theme.set_stylebox("panel", "PopupMenu", field(Color("101722")))
	theme.set_stylebox("hover", "PopupMenu", field(Color("7a3035"), CORAL))
	theme.set_constant("v_separation", "PopupMenu", 12)
	var track := brush(TRACK)
	track.content_margin_top = 9
	track.content_margin_bottom = 9
	var fill := brush(FILL)
	fill.content_margin_top = 9
	fill.content_margin_bottom = 9
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill)
	# Reserve the real slider grab area. A TextureRect draws the native artwork
	# at UI size without baking or resampling another bitmap.
	var small_handle := ImageTexture.create_from_image(Image.create(18, 36, false, Image.FORMAT_RGBA8))
	for state in ["grabber", "grabber_highlight", "grabber_disabled"]:
		theme.set_icon(state, "HSlider", small_handle)
	var separator := StyleBoxLine.new()
	separator.color = Color(1, 0.9, 0.77, 0.12)
	separator.thickness = 1
	theme.set_stylebox("separator", "HSeparator", separator)
	var scrollbar := field(Color("111923"), Color.TRANSPARENT)
	scrollbar.skew = Vector2.ZERO
	scrollbar.set_content_margin_all(3)
	theme.set_stylebox("scroll", "VScrollBar", scrollbar)
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var grabber := field(CORAL, Color.TRANSPARENT)
		grabber.skew = Vector2.ZERO
		grabber.set_content_margin_all(3)
		theme.set_stylebox(state, "VScrollBar", grabber)
	return theme

static func decorate_slider(slider: HSlider) -> void:
	var knob := TextureRect.new()
	knob.texture = DIAMOND
	knob.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	knob.size = Vector2(18, 36)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slider.add_child(knob)
	var position_knob := func():
		knob.position = Vector2(slider.get_as_ratio() * maxf(0, slider.size.x - 18), (slider.size.y - 36) * 0.5)
	slider.resized.connect(position_knob)
	slider.value_changed.connect(func(_value: float): position_knob.call())
	# Audio values are also refreshed with set_value_no_signal.
	slider.draw.connect(position_knob)
	position_knob.call_deferred()
