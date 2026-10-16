class_name GameSettingsUI
extends CanvasLayer

signal menu_changed(open: bool)
@export var audio_page: AudioMixUI
@export var orbit_page: CanvasLayer
var menu_open := false
var _root: Control
var _panel: PanelContainer
var _launcher: Button
var _audio_host: VBoxContainer
var _orbit_host: VBoxContainer
var _tabs: Array[Button] = []
var _theme: Theme
var _selected := 0

func _ready() -> void:
	layer = 40
	_build()
	_embed.call_deferred()
	get_viewport().size_changed.connect(_fit)
	_fit()

func _skin(background: Color, border := Color("7b6a46")) -> StyleBoxFlat:
	var skin := StyleBoxFlat.new()
	skin.bg_color = background
	skin.border_color = border
	skin.set_border_width_all(1)
	skin.set_corner_radius_all(3)
	skin.set_content_margin_all(14)
	return skin

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 42)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	return button

func _build() -> void:
	_theme = Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	_theme.default_font = font
	_theme.default_font_size = 17
	for type in ["Label", "Button", "CheckBox", "OptionButton", "SpinBox"]:
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			_theme.set_color(state, type, Color("e7dfca"))
	for state in ["normal", "focus"]: _theme.set_stylebox(state, "Button", _skin(Color("162333")))
	_theme.set_stylebox("hover", "Button", _skin(Color("28364a"), Color("d0ad65")))
	_theme.set_stylebox("pressed", "Button", _skin(Color("354150"), Color("e3bd71")))
	for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		_theme.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())
	_launcher = _button("设置", open_menu)
	_launcher.theme = _theme
	add_child(_launcher)
	_root = Control.new()
	_root.theme = _theme
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.025, 0.045, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", _skin(Color(0.035, 0.055, 0.085, 0.98)))
	_root.add_child(_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 18)
	_panel.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := Label.new()
	title.text = "设置"
	title.add_theme_font_size_override("font_size", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("返回游戏 · ESC", close_menu))
	layout.add_child(HSeparator.new())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	layout.add_child(body)
	var navigation := VBoxContainer.new()
	navigation.custom_minimum_size.x = 160
	navigation.add_theme_constant_override("separation", 10)
	body.add_child(navigation)
	for index in 2:
		var button := _button(["声音", "环绕调试"][index], select_page.bind(index))
		button.toggle_mode = true
		navigation.add_child(button)
		_tabs.append(button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(pages)
	_audio_host = VBoxContainer.new()
	_audio_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.add_child(_audio_host)
	_orbit_host = VBoxContainer.new()
	pages.add_child(_orbit_host)
	var enabled := CheckBox.new()
	enabled.text = "开启环绕调试"
	enabled.toggled.connect(func(value: bool):
		orbit_page.set_debug_enabled(value)
		orbit_page.set_embedded_visible(menu_open and _selected == 1))
	_orbit_host.add_child(enabled)
	var hint := Label.new()
	hint.text = "关闭设置后可继续观察场景内的诊断线；关闭调试即可停止采集。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color("a6b2bd"))
	_orbit_host.add_child(hint)
	var footer := Label.new()
	footer.text = "修改即时生效 · 世界继续运行"
	footer.add_theme_color_override("font_color", Color("a6b2bd"))
	layout.add_child(footer)
	_root.hide()

func _embed() -> void:
	audio_page.embed_in(_audio_host, _theme)
	orbit_page.embed_in(_orbit_host, _theme)
	audio_page.settings_requested.connect(func(): open_menu(); select_page(0))
	select_page(0)

func _fit() -> void:
	var viewport := get_viewport().get_visible_rect().size
	_launcher.position = Vector2(viewport.x - 90, 22)
	_launcher.size = Vector2(68, 38)
	_panel.size = Vector2(minf(1020, viewport.x - 48), minf(800, viewport.y - 48))
	_panel.position = (viewport - _panel.size) * 0.5

func select_page(index: int) -> void:
	_selected = clampi(index, 0, 1)
	for item in _tabs.size(): _tabs[item].set_pressed_no_signal(item == _selected)
	_audio_host.visible = _selected == 0
	_orbit_host.visible = _selected == 1
	if audio_page._embedded: audio_page.set_embedded_visible(menu_open and _selected == 0)
	if orbit_page._embedded: orbit_page.set_embedded_visible(menu_open and _selected == 1)

func open_menu() -> void:
	var blocker := get_tree().get_first_node_in_group(&"gameplay_input_blockers")
	if menu_open or (blocker != null and not (blocker is WavePrototype and blocker.phase == WavePrototype.Phase.RESULT)): return
	menu_open = true
	add_to_group(&"gameplay_input_blockers")
	_root.show()
	_launcher.hide()
	select_page(_selected)
	menu_changed.emit(true)

func close_menu() -> void:
	if not menu_open: return
	menu_open = false
	audio_page.set_embedded_visible(false)
	orbit_page.set_embedded_visible(false)
	_root.hide()
	_launcher.show()
	remove_from_group(&"gameplay_input_blockers")
	menu_changed.emit(false)

func _input(event: InputEvent) -> void:
	if menu_open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_menu()
		get_viewport().set_input_as_handled()

func _unhandled_input(_event: InputEvent) -> void:
	if menu_open: get_viewport().set_input_as_handled()
