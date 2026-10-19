class_name GameSettingsUI
extends CanvasLayer

const GRAPHICS_PAGE = preload("res://scripts/ui/graphics_settings_page.gd")
const CAMERA_PAGE = preload("res://scripts/ui/camera_settings_page.gd")
const CONTROLS_PAGE = preload("res://scripts/ui/controls_settings_page.gd")
const ENTRY_REQUEST = preload("res://scripts/world/world_entry_request.gd")
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"

signal menu_changed(open: bool)
@export var audio_page: AudioMixUI
@export var orbit_page: CanvasLayer
@export var save_graphics_settings := true
var menu_open := false
var _root: Control
var _panel: PanelContainer
var _launcher: Button
var _audio_host: VBoxContainer
var _orbit_host: VBoxContainer
var _tabs: Array[Button] = []
var _theme: Theme
var _selected := 0
var _fps_label: Label
var _fps_toggle: CheckBox
var _fps_timer: Timer
var _graphics_page
var _camera_page
var _controls_page
var _controls: Node
var _return_button: Button
var _returning_to_menu := false

func _ready() -> void:
	_controls = get_node("/root/GameControls")
	_controls.configure_world(get_parent())
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
	_fps_toggle = CheckBox.new()
	_fps_toggle.text = "显示实时帧率"
	_fps_toggle.toggled.connect(_set_fps_visible)
	layout.add_child(_fps_toggle)
	layout.add_child(HSeparator.new())
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	layout.add_child(body)
	var navigation := VBoxContainer.new()
	navigation.custom_minimum_size.x = 160
	navigation.add_theme_constant_override("separation", 10)
	var navigation_scroll := ScrollContainer.new()
	navigation_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	navigation_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(navigation_scroll)
	navigation_scroll.add_child(navigation)
	for index in 5:
		var button := _button(["声音", "环绕调试", "画质与显示", "镜头", "按键"][index], select_page.bind(index))
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
	_graphics_page = GRAPHICS_PAGE.new()
	pages.add_child(_graphics_page)
	_camera_page = CAMERA_PAGE.new()
	pages.add_child(_camera_page)
	_controls_page = CONTROLS_PAGE.new()
	pages.add_child(_controls_page)
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
	var footer := HBoxContainer.new()
	layout.add_child(footer)
	var footer_hint := Label.new()
	footer_hint.text = "修改即时生效 · 世界继续运行"
	footer_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer_hint.add_theme_color_override("font_color", Color("a6b2bd"))
	footer.add_child(footer_hint)
	_return_button = _button("返回主菜单", return_to_main_menu)
	_return_button.tooltip_text = "结束当前一局并返回主菜单，可再次查看入场镜头。"
	footer.add_child(_return_button)
	_root.hide()
	_fps_label = Label.new()
	_fps_label.name = "LiveFPS"
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.add_theme_color_override("font_color", Color.BLACK)
	_fps_label.add_theme_font_size_override("font_size", 20)
	_fps_label.hide()
	add_child(_fps_label)
	_fps_timer = Timer.new()
	_fps_timer.wait_time = 0.5
	_fps_timer.ignore_time_scale = true
	_fps_timer.timeout.connect(_refresh_fps)
	add_child(_fps_timer)

func _set_fps_visible(enabled: bool) -> void:
	_fps_label.visible = enabled
	if enabled:
		_refresh_fps()
		_fps_timer.start()
	else:
		_fps_timer.stop()

func _refresh_fps() -> void:
	_fps_label.text = "FPS: %d" % Engine.get_frames_per_second()

func _embed() -> void:
	audio_page.embed_in(_audio_host, _theme)
	orbit_page.embed_in(_orbit_host, _theme)
	# Headless test suites must not load or write the player's display preferences.
	_graphics_page.save_enabled = save_graphics_settings and DisplayServer.get_name() != "headless"
	_graphics_page.configure(get_parent(), _theme)
	_camera_page.save_enabled = DisplayServer.get_name() != "headless"
	_camera_page.configure(get_parent(), _theme)
	_controls.changed.connect(_camera_page.sync_controls)
	_controls_page.configure(_theme)
	audio_page.settings_requested.connect(func(): open_menu(); select_page(0))
	select_page(0)

func _fit() -> void:
	var viewport := get_viewport().get_visible_rect().size
	_launcher.position = Vector2(viewport.x - 90, 22)
	_launcher.size = Vector2(68, 38)
	_fps_label.position = Vector2(viewport.x - 152, 68)
	_fps_label.size = Vector2(130, 28)
	_panel.size = Vector2(minf(1020, viewport.x - 48), minf(800, viewport.y - 48))
	_panel.position = (viewport - _panel.size) * 0.5

func select_page(index: int) -> void:
	_selected = clampi(index, 0, 4)
	if _selected != 4: _controls_page.cancel_capture()
	for item in _tabs.size(): _tabs[item].set_pressed_no_signal(item == _selected)
	_audio_host.visible = _selected == 0
	_orbit_host.visible = _selected == 1
	_graphics_page.visible = _selected == 2
	_camera_page.visible = _selected == 3
	_controls_page.visible = _selected == 4
	if _selected == 4: _controls_page.sync_controls()
	if _selected == 3: _camera_page.sync_controls()
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
	if not menu_open or _returning_to_menu: return
	menu_open = false
	_controls_page.cancel_capture()
	audio_page.set_embedded_visible(false)
	orbit_page.set_embedded_visible(false)
	_root.hide()
	_launcher.show()
	remove_from_group(&"gameplay_input_blockers")
	menu_changed.emit(false)

func return_to_main_menu() -> void:
	if not menu_open or _returning_to_menu: return
	_returning_to_menu = true
	_return_button.disabled = true
	_return_button.text = "正在返回…"
	_change_to_main_menu.call_deferred()

func _change_to_main_menu() -> void:
	ENTRY_REQUEST.clear()
	var startup := get_parent().get_node_or_null("WorldMainMenu")
	var result := ERR_BUSY
	if startup:
		if startup.return_to_menu():
			_returning_to_menu = false
			close_menu()
			_return_button.disabled = false
			_return_button.text = "返回主菜单"
			return
	else:
		# Other maps without an embedded menu still use the standalone entry.
		result = get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	if result == OK: return
	_returning_to_menu = false
	_return_button.disabled = false
	_return_button.text = "返回主菜单"
	_return_button.tooltip_text = "返回失败：%s。点击重试。" % error_string(result)

func _input(event: InputEvent) -> void:
	if _controls_page and _controls_page.is_capturing(): return
	var focus := get_viewport().gui_get_focus_owner()
	if _controls.pressed(event, &"settings") and not (focus is LineEdit or focus is TextEdit):
		if menu_open: close_menu()
		else: open_menu()
		if menu_open or get_tree().get_first_node_in_group(&"gameplay_input_blockers") == null: get_viewport().set_input_as_handled()
		return
	if menu_open and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close_menu()
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if menu_open or not _controls.pressed(event, &"toggle_rain") or not _graphics_page or not _graphics_page.configured: return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	for blocker in get_tree().get_nodes_in_group(&"gameplay_input_blockers"):
		if not (blocker is WavePrototype and blocker.phase == WavePrototype.Phase.RESULT): return
	var weather := get_parent().get_node_or_null("MapEffects/Weather")
	if weather and _graphics_page.set_option("rain", not weather.raining): get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if is_instance_valid(_controls): _controls.release_world(get_parent())

func _unhandled_input(_event: InputEvent) -> void:
	if menu_open: get_viewport().set_input_as_handled()
