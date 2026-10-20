class_name GameSettingsUI
extends CanvasLayer

const KINETIC = preload("res://scripts/ui/settings_kinetic_theme.gd")
const DESIGN_SIZE := Vector2(1440, 900)
const PAGE_NAMES := ["声音", "环绕调试", "画质", "镜头", "按键", "排行榜", "人物"]
const CHARACTER_PAGE = preload("res://scripts/ui/character_stats_page.gd")
const LEADERBOARD_PAGE = preload("res://scripts/ui/leaderboard_page.gd")

const GRAPHICS_PAGE = preload("res://scripts/ui/graphics_settings_page.gd")
const CAMERA_PAGE = preload("res://scripts/ui/camera_settings_page.gd")
const CONTROLS_PAGE = preload("res://scripts/ui/controls_settings_page.gd")
const ENTRY_REQUEST = preload("res://scripts/world/world_entry_request.gd")
const MAIN_MENU_SCENE := "res://scenes/ui/main_menu.tscn"

signal menu_changed(open: bool)
@export var audio_page: AudioMixUI
@export var orbit_page: CanvasLayer
@export var save_graphics_settings := true
@export_group("界面音效")
@export var ui_sounds: UISoundBank = preload("res://data/audio/ui_sounds.tres")
var _ui_audio: UIAudio
var menu_open := false
var _root: Control
var _panel: PanelContainer
var _canvas: Control
var _page_heading: Label
var _scroll: ScrollContainer
var _page_scrollbar: VScrollBar
var _appearance: Tween
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
var _leaderboard_page: VBoxContainer
var _character_page: VBoxContainer
var _controls: Node
var _return_button: Button
var _returning_to_menu := false

func _ready() -> void:
	_controls = get_node("/root/GameControls")
	_controls.configure_world(get_parent())
	_ui_audio = preload("res://scenes/audio/ui_audio.tscn").instantiate()
	_ui_audio.sounds = ui_sounds
	add_child(_ui_audio)
	layer = 40
	_build()
	_embed.call_deferred()
	get_viewport().size_changed.connect(_fit)
	_fit()

func _button(text: String, callback: Callable, action: StringName = &"button") -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 42)
	button.focus_mode = Control.FOCUS_NONE
	button.set_meta(&"ui_audio_action", action)
	button.pressed.connect(callback)
	return button

func _art(texture: Texture2D, rect: Rect2, tint := Color.WHITE) -> TextureRect:
	var art := TextureRect.new()
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.position = rect.position
	art.size = rect.size
	art.modulate = tint
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(art)
	return art

func _caption(text: String, point: Vector2, font_size: int, color := KINETIC.IVORY) -> Label:
	var label := Label.new()
	label.text = text
	label.position = point
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(label)
	return label

func _build() -> void:
	_theme = KINETIC.make()
	_launcher = _button("设置", open_menu, &"")
	_launcher.theme = _theme
	add_child(_launcher)
	_root = Control.new()
	_root.theme = _theme
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	# The existing viewport is the background: no screenshot, blur pass or second world.
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.02, 0.035, 0.22)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	_canvas = Control.new()
	_canvas.size = DESIGN_SIZE
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_canvas)
	_art(KINETIC.DARK, Rect2(-190, 30, 760, 220), Color(0.7, 0.7, 0.7, 0.95))
	_art(KINETIC.SWEEP, Rect2(-110, -24, 1080, 195), Color(1, 1, 1, 0.92))
	_art(KINETIC.SWEEP, Rect2(-120, 756, 1190, 175), Color(1, 1, 1, 0.88)).rotation = -0.075
	var title := _caption("设置", Vector2(63, 65), 112)
	title.rotation = -0.055
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_outline_color", Color("10151d"))
	_art(KINETIC.INK, Rect2(514, 100, 926, 650))
	_page_heading = _caption("", Vector2(623, 161), 32)
	_fps_toggle = CheckBox.new()
	_fps_toggle.text = "显示帧率"
	_fps_toggle.position = Vector2(1178, 167)
	_fps_toggle.add_theme_font_size_override("font_size", 16)
	_fps_toggle.toggled.connect(_set_fps_visible)
	_canvas.add_child(_fps_toggle)
	_tabs.resize(PAGE_NAMES.size())
	var order := [6, 0, 2, 3, 4, 5, 1]
	for slot in order.size():
		var index: int = order[slot]
		var button := _button(["声音", "调试", "画质", "镜头", "按键", "排行榜", "人物"][index], select_page.bind(index, true), &"")
		button.theme_type_variation = "SettingsTab"
		button.toggle_mode = true
		if index < KINETIC.ICONS.size(): button.icon = KINETIC.ICONS[index]
		button.expand_icon = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.position = Vector2(48 + slot * 14, 263 + slot * 70)
		button.size = Vector2(318, 74)
		_canvas.add_child(button)
		_tabs[index] = button
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_panel.position = Vector2(623, 222)
	_panel.size = Vector2(716, 437)
	_canvas.add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(_scroll)
	# Rotate the complete native control, including its input coordinates. Skewing
	# only its StyleBox would leave the thumb moving down a vertical hit area.
	_page_scrollbar = VScrollBar.new()
	_page_scrollbar.name = "PageScrollBar"
	_page_scrollbar.rotation = atan(0.12)
	_page_scrollbar.position = Vector2(1395, 222)
	_page_scrollbar.size = Vector2(10, _panel.size.y / cos(_page_scrollbar.rotation))
	_canvas.add_child(_page_scrollbar)
	var source := _scroll.get_v_scroll_bar()
	source.share(_page_scrollbar)
	source.changed.connect(_sync_page_scrollbar)
	_sync_page_scrollbar()
	var pages := VBoxContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(pages)
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
	_leaderboard_page = LEADERBOARD_PAGE.new()
	pages.add_child(_leaderboard_page)
	_character_page = CHARACTER_PAGE.new()
	pages.add_child(_character_page)
	_character_page.configure(get_parent())
	var enabled := CheckBox.new()
	enabled.text = "开启环绕调试"
	enabled.toggled.connect(func(value: bool):
		orbit_page.set_debug_enabled(value)
		orbit_page.set_embedded_visible(menu_open and _selected == 1))
	_orbit_host.add_child(enabled)
	enabled.tooltip_text = "关闭设置后仍可查看诊断线，关闭调试停止采集。"
	var resume := _button("返回游戏  ›", close_menu, &"")
	resume.theme_type_variation = "SettingsResume"
	resume.position = Vector2(1005, 733)
	resume.size = Vector2(382, 104)
	_canvas.add_child(resume)
	_return_button = _button("返回主菜单", return_to_main_menu)
	_return_button.theme_type_variation = "SettingsReturn"
	_return_button.position = Vector2(1064, 840)
	_return_button.size = Vector2(300, 56)
	_return_button.tooltip_text = "结束本局并返回主菜单。"
	_canvas.add_child(_return_button)
	_caption("ESC", Vector2(942, 783), 20)
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

func _sync_page_scrollbar() -> void:
	_page_scrollbar.visible = _page_scrollbar.max_value - _page_scrollbar.min_value > _page_scrollbar.page + 1

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
	_controls_page.audio = _ui_audio
	_controls_page.configure(_theme)
	audio_page.settings_requested.connect(func(): open_menu(); select_page(0))
	select_page(0)
	_ui_audio.bind_controls(self)

func _fit() -> void:
	var viewport := get_viewport().get_visible_rect().size
	_launcher.position = Vector2(viewport.x - 90, 22)
	_launcher.size = Vector2(68, 38)
	_fps_label.position = Vector2(viewport.x - 152, 68)
	_fps_label.size = Vector2(130, 28)
	var fit_scale := minf(viewport.x / DESIGN_SIZE.x, viewport.y / DESIGN_SIZE.y)
	_canvas.scale = Vector2.ONE * fit_scale
	_canvas.position = (viewport - DESIGN_SIZE * fit_scale) * 0.5

func select_page(index: int, audible := false) -> void:
	var changed := _selected != index
	_selected = clampi(index, 0, PAGE_NAMES.size() - 1)
	_page_heading.text = PAGE_NAMES[_selected]
	if changed: _scroll.scroll_vertical = 0
	if _selected != 4: _controls_page.cancel_capture()
	for item in _tabs.size(): _tabs[item].set_pressed_no_signal(item == _selected)
	_audio_host.visible = _selected == 0
	_orbit_host.visible = _selected == 1
	_graphics_page.visible = _selected == 2
	_camera_page.visible = _selected == 3
	_controls_page.visible = _selected == 4
	_leaderboard_page.visible = _selected == 5
	_character_page.visible = _selected == 6
	if _selected == 6: _character_page.refresh()
	if menu_open and _selected == 5: _leaderboard_page.activate()
	if _selected == 4: _controls_page.sync_controls()
	if _selected == 3: _camera_page.sync_controls()
	if audio_page._embedded: audio_page.set_embedded_visible(menu_open and _selected == 0)
	if orbit_page._embedded: orbit_page.set_embedded_visible(menu_open and _selected == 1)
	if changed and audible and menu_open: _ui_audio.play_action(&"tab")

func open_menu() -> void:
	if menu_open: return
	for blocker in get_tree().get_nodes_in_group(&"gameplay_input_blockers"):
		if not (blocker is WavePrototype and blocker.phase == WavePrototype.Phase.RESULT): return
	menu_open = true
	add_to_group(&"gameplay_input_blockers")
	_root.show()
	if _appearance: _appearance.kill()
	_canvas.modulate.a = 0.0
	_appearance = create_tween().set_ignore_time_scale(true)
	_appearance.tween_property(_canvas, "modulate:a", 1.0, 0.16)
	_launcher.hide()
	select_page(_selected)
	menu_changed.emit(true)
	_ui_audio.play_action(&"open")

func close_menu(audible := true) -> void:
	if not menu_open or _returning_to_menu: return
	menu_open = false
	_controls_page.cancel_capture()
	audio_page.set_embedded_visible(false)
	orbit_page.set_embedded_visible(false)
	if _appearance: _appearance.kill()
	_root.hide()
	_launcher.show()
	remove_from_group(&"gameplay_input_blockers")
	menu_changed.emit(false)
	if audible: _ui_audio.play_action(&"close")

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
			close_menu(false)
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
	_ui_audio.play_action(&"error")

func _input(event: InputEvent) -> void:
	if _controls_page and _controls_page.is_capturing(): return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		if menu_open:
			close_menu()
			get_viewport().set_input_as_handled()
		else:
			open_menu()
			if menu_open: get_viewport().set_input_as_handled()
		return
	var focus := get_viewport().gui_get_focus_owner()
	if _controls.pressed(event, &"settings") and not (focus is LineEdit or focus is TextEdit):
		if menu_open: close_menu()
		else: open_menu()
		if menu_open or get_tree().get_first_node_in_group(&"gameplay_input_blockers") == null: get_viewport().set_input_as_handled()
		return

func _unhandled_key_input(event: InputEvent) -> void:
	if menu_open:
		get_viewport().set_input_as_handled()
		return
	if not _controls.pressed(event, &"toggle_rain") or not _graphics_page or not _graphics_page.configured: return
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
