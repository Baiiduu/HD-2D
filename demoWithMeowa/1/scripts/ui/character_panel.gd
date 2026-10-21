extends CanvasLayer
## World-only character sheet. The existing viewport remains its background.
const KINETIC = preload("res://scripts/ui/settings_kinetic_theme.gd")
const CATALOG = preload("res://scripts/ui/character_attribute_catalog.gd")
const ROW = preload("res://scripts/ui/character_attribute_row.gd")
const PORTRAIT = preload("res://assets/meowa/ui/main_menu/hero_battle.png")
const DESIGN_SIZE := Vector2(1440, 900)
const ART_WIDTH_RATIO := 0.9
@export var ui_sounds: UISoundBank = preload("res://data/audio/ui_sounds.tres")
signal panel_changed(open: bool)
var panel_open := false
var catalog := CATALOG.new()
var _category: StringName = &"overview"
var _controls: Node
var _audio: UIAudio
var _root: Control
var _canvas: Control
var _launcher: Button
var _tabs: Array[Button] = []
var _heading: Label
var _context: Label
var _level: Label
var _health: Label
var _health_bar: ProgressBar
var _list: VBoxContainer
var _scroll: ScrollContainer
var _scrollbar: VScrollBar
var _hint: Label
var _rows := {}
var _scroll_positions := {}
var _refresh_remaining := 0.0
var _pause_tree: SceneTree
var _previous_pause := false
var _appearance: Tween
var _hud_visibility: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_controls = get_node("/root/GameControls")
	_controls.configure_world(get_parent())
	catalog.configure(get_parent())
	_audio = preload("res://scenes/audio/ui_audio.tscn").instantiate()
	_audio.sounds = ui_sounds
	add_child(_audio)
	_build()
	var settings := get_parent().get_node_or_null("GameSettingsUI") as GameSettingsUI
	if settings: settings.menu_changed.connect(func(open: bool): _launcher.visible = not open and not panel_open)
	_audio.bind_controls(self)
	_controls.changed.connect(_sync_binding)
	_sync_binding()
	get_viewport().size_changed.connect(_fit)
	_fit()
	set_process(false)

func _art(texture: Texture2D, rect: Rect2, tint := Color.WHITE) -> TextureRect:
	var art := TextureRect.new()
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.position = Vector2(rect.position.x * ART_WIDTH_RATIO, rect.position.y)
	art.size = Vector2(rect.size.x * ART_WIDTH_RATIO, rect.size.y)
	art.modulate = tint
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(art)
	return art

func _label(text: String, point: Vector2, font_size: int, color := KINETIC.IVORY) -> Label:
	var label := Label.new()
	label.text = text
	label.position = Vector2(point.x * ART_WIDTH_RATIO, point.y)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(label)
	return label

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.set_meta(&"ui_audio_action", &"")
	button.pressed.connect(callback)
	return button

func _build() -> void:
	_launcher = _button("人物  C", open_panel)
	_launcher.theme = KINETIC.make()
	add_child(_launcher)
	_root = Control.new()
	_root.theme = _launcher.theme
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.02, 0.035, 0.28)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	_canvas = Control.new()
	_canvas.size = DESIGN_SIZE
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_canvas)
	_art(KINETIC.DARK, Rect2(-110, 16, 740, 235))
	_art(KINETIC.RED, Rect2(-110, 62, 610, 130)).rotation = -0.08
	_art(KINETIC.SWEEP, Rect2(-60, 25, 1010, 185))
	var title := _label("人物", Vector2(65, 58), 116)
	title.rotation = -0.055
	title.add_theme_constant_override("outline_size", 7)
	title.add_theme_color_override("font_outline_color", Color("11151e"))
	_art(KINETIC.SWEEP, Rect2(-200, 590, 1160, 175), Color(1, 0.8, 0.73, 0.72)).rotation = -0.17
	var portrait := _art(PORTRAIT, Rect2(-12, 178, 760, 600))
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_art(KINETIC.INK, Rect2(675, 65, 930, 768))
	# Level and its brush share one container, including font-driven minimum size.
	var level_frame := PanelContainer.new()
	level_frame.position = Vector2(247, 620)
	level_frame.size = Vector2(300, 94)
	level_frame.rotation = -0.06
	level_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var level_skin := KINETIC.brush(KINETIC.RED)
	level_skin.content_margin_left = 45
	level_skin.content_margin_right = 45
	level_skin.content_margin_top = 10
	level_skin.content_margin_bottom = 10
	level_frame.add_theme_stylebox_override("panel", level_skin)
	_canvas.add_child(level_frame)
	_level = Label.new()
	_level.text = "Lv. 1"
	_level.add_theme_font_size_override("font_size", 34)
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level.mouse_filter = Control.MOUSE_FILTER_IGNORE
	level_frame.add_child(_level)
	_label("基础状态", Vector2(135, 717), 27)
	_art(KINETIC.DARK, Rect2(110, 751, 570, 65))
	_label("生命", Vector2(145, 761), 24)
	_health_bar = ProgressBar.new()
	_health_bar.position = Vector2(195, 770)
	_health_bar.size = Vector2(198, 22)
	_health_bar.show_percentage = false
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_bar.add_theme_stylebox_override("background", KINETIC.field(Color("0e1720"), KINETIC.IVORY))
	_health_bar.add_theme_stylebox_override("fill", KINETIC.field(KINETIC.CORAL, Color.TRANSPARENT))
	_canvas.add_child(_health_bar)
	_health = _label("", Vector2(457, 762), 24)
	_art(KINETIC.SWEEP, Rect2(-120, 820, 1040, 90), Color(1, 1, 1, 0.65)).rotation = 0.03
	for index in CATALOG.CATEGORIES.size():
		var category: Dictionary = CATALOG.CATEGORIES[index]
		var tab := _button(category.title, select_category.bind(category.id, true))
		tab.toggle_mode = true
		tab.position = Vector2(752 + index * 121, 118)
		tab.size = Vector2(115, 52)
		tab.add_theme_font_size_override("font_size", 30)
		for state in ["pressed", "hover_pressed"]:
			tab.add_theme_stylebox_override(state, KINETIC.brush(KINETIC.RED))
			tab.add_theme_color_override("font_" + state + "_color", Color("111925"))
		_canvas.add_child(tab)
		_tabs.append(tab)
	_heading = _label("", Vector2(786, 191), 36)
	_context = _label("", Vector2(1230, 210), 16, Color("c3ad9c"))
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(717, 258)
	_scroll.size = Vector2(629, 478)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_canvas.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 9)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_scrollbar = VScrollBar.new()
	_scrollbar.position = Vector2(1385, 258)
	_scrollbar.rotation = atan(0.1)
	_scrollbar.size = Vector2(9, 478 / cos(_scrollbar.rotation))
	_canvas.add_child(_scrollbar)
	var source := _scroll.get_v_scroll_bar()
	source.share(_scrollbar)
	source.changed.connect(_sync_scrollbar)
	source.value_changed.connect(func(_value: float): _sync_scrollbar())
	_label("悬停查看来源与生效条件", Vector2(807, 772), 18, Color("ccbfae"))
	_hint = _label("", Vector2(1327, 749), 16, Color("b7aa9b"))
	var resume := _button("返回游戏  ›", close_panel)
	resume.theme_type_variation = "SettingsResume"
	resume.position = Vector2(1111, 815)
	resume.size = Vector2(315, 78)
	_canvas.add_child(resume)
	_label("ESC", Vector2(1162, 849), 19)
	_root.hide()

func _sync_binding() -> void:
	var key_name: String = _controls.model.label_for(_controls.model.bindings[&"character"][0])
	_launcher.text = "人物  " + key_name
	_launcher.tooltip_text = "人物属性（%s）" % key_name
	_fit()

func _fit() -> void:
	var viewport := get_viewport().get_visible_rect().size
	# The score occupies the upper-right strip; reserve a separate lower-right entry.
	_launcher.size = Vector2(maxf(118.0, _launcher.get_combined_minimum_size().x), 42)
	_launcher.position = viewport - _launcher.size - Vector2(24, 24)
	var fit_scale := minf(viewport.x / DESIGN_SIZE.x, viewport.y / DESIGN_SIZE.y)
	_canvas.scale = Vector2.ONE * fit_scale
	_canvas.position = (viewport - DESIGN_SIZE * fit_scale) * 0.5

func _sync_scrollbar() -> void:
	_scrollbar.visible = _scrollbar.max_value > _scrollbar.page + 1
	if _hint: _hint.text = "滚动查看更多 ↓" if _scrollbar.visible and _scrollbar.value + _scrollbar.page < _scrollbar.max_value - 2 else ""

func select_category(category: StringName, audible := false) -> void:
	if not CATALOG.CATEGORIES.any(func(item): return item.id == category): return
	_scroll_positions[_category] = _scroll.scroll_vertical
	var changed := category != _category
	_category = category
	for index in _tabs.size():
		var active: bool = CATALOG.CATEGORIES[index].id == category
		_tabs[index].set_pressed_no_signal(active)
		if active: _heading.text = CATALOG.CATEGORIES[index].heading
	_rows.clear()
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	var group := ""
	var data := catalog.capture()
	for definition in catalog.rows(category, data):
		if definition.group != group:
			group = definition.group
			var heading := Label.new()
			heading.text = group
			heading.add_theme_font_size_override("font_size", 23)
			heading.add_theme_color_override("font_color", KINETIC.CORAL)
			heading.custom_minimum_size.y = 37
			_list.add_child(heading)
		var row := ROW.new()
		row.configure(definition)
		_list.add_child(row)
		_rows[definition.id] = row
	_scroll.set_deferred("scroll_vertical", int(_scroll_positions.get(category, 0)))
	refresh()
	if audible and changed: _audio.play_action(&"tab")

func refresh() -> void:
	var data := catalog.capture()
	if data.is_empty(): return
	_level.text = "Lv. %d" % data.level
	_health.text = "%.0f / %.0f" % [data.health_current, data.health_max]
	_health_bar.max_value = maxf(1.0, data.health_max)
	_health_bar.value = data.health_current
	_context.text = data.ricochet_context + " · " + data.state_label if _category == &"ricochet" else "当前生效数值"
	for row in catalog.rows(_category, data):
		if _rows.has(row.id): _rows[row.id].set_readout(row)

func open_panel() -> void:
	if panel_open or not visible: return
	if get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null: return
	panel_open = true
	add_to_group(&"gameplay_input_blockers")
	_pause_tree = get_tree()
	_previous_pause = _pause_tree.paused
	_pause_tree.paused = true
	for path in ["LoadoutUI", "WavePrototype/WaveHUD", "WavePrototype/ScoreHUD"]:
		var hud := get_parent().get_node_or_null(NodePath(path)) as CanvasLayer
		if hud:
			_hud_visibility[hud] = hud.visible
			hud.hide()
	_launcher.hide()
	_root.show()
	select_category(_category)
	_canvas.modulate.a = 0.0
	if _appearance: _appearance.kill()
	_appearance = create_tween().set_ignore_time_scale(true)
	_appearance.tween_property(_canvas, "modulate:a", 1.0, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_refresh_remaining = 0.15
	set_process(true)
	_audio.play_action(&"open")
	panel_changed.emit(true)

func close_panel(audible := true) -> void:
	if not panel_open: return
	panel_open = false
	if _appearance: _appearance.kill()
	_root.hide()
	_launcher.show()
	set_process(false)
	remove_from_group(&"gameplay_input_blockers")
	_restore_pause()
	if audible: _audio.play_action(&"close")
	panel_changed.emit(false)

func _restore_pause() -> void:
	if not is_instance_valid(_pause_tree): return
	for hud: CanvasLayer in _hud_visibility:
		if is_instance_valid(hud): hud.visible = _hud_visibility[hud]
	_hud_visibility.clear()
	var player := get_parent().get_node_or_null("Player") as Player
	if is_instance_valid(player):
		if player.body_ricochet: player.body_ricochet.discard_blocked_input(_controls.movement_mask())
		if player._blink: player._blink.discard_buffered_input()
	_pause_tree.paused = _previous_pause
	_pause_tree = null

func _process(delta: float) -> void:
	_refresh_remaining -= delta
	if _refresh_remaining <= 0.0:
		_refresh_remaining = 0.15
		refresh()

func _input(event: InputEvent) -> void:
	if not visible: return
	var escape: bool = event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE)
	var focus := get_viewport().gui_get_focus_owner()
	var toggle: bool = _controls.pressed(event, &"character") and not (focus is LineEdit or focus is TextEdit)
	if panel_open and (escape or toggle):
		close_panel()
		get_viewport().set_input_as_handled()
	elif toggle and get_tree().get_first_node_in_group(&"gameplay_input_blockers") == null:
		open_panel()
		if panel_open: get_viewport().set_input_as_handled()

func _unhandled_input(_event: InputEvent) -> void:
	if panel_open: get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	_restore_pause()
