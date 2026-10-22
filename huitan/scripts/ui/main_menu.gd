extends Control

const Stage = preload("res://scripts/ui/main_menu_stage.gd")
const ActionButton = preload("res://scripts/ui/main_menu_button.gd")
const Flow = preload("res://scripts/ui/main_menu_flow.gd")
const EntryRequest = preload("res://scripts/world/world_entry_request.gd")
const GraphicsPage = preload("res://scripts/ui/graphics_settings_page.gd")
const CameraPage = preload("res://scripts/ui/camera_settings_page.gd")
const ControlsPage = preload("res://scripts/ui/controls_settings_page.gd")
const LeaderboardWindow = preload("res://scripts/ui/leaderboard_window.gd")
const MENU_SIZE := Vector2(360, 620)
const FONT = preload("res://assets/fonts/maoken_assorted_sans/MaokenAssortedSans.ttf")
const CORE = preload("res://data/audio/core_sound_bank.tres")
const MUSIC = preload("res://data/audio/music/exploration.tres")
const PREFERENCES := "user://main_menu.cfg"

@export_group("主菜单")
@export var game_title := "回弹"
@export_file("*.tscn") var world_scene := "res://scenes/world/world.tscn"
@export_range(0.3, 2.0, 0.05, "suffix:s") var start_feedback_seconds := 1.05
@export var save_preferences := true
## Standalone F6 prepares World immediately; World embeds the final interactive menu.
@export var auto_prepare_world := true
@export_group("演出声音")
@export var audio_enabled := true
@export var ui_sounds: UISoundBank = preload("res://data/audio/ui_sounds.tres")
@export_range(-40.0, 0.0, 0.5) var performance_volume_db := -23.0

var stage: Node2D
var flow := Flow.new()
var buttons: Array[Button] = []
var settings_panel: Control
var _panel: Control
var _title: Label
var _status: Label
var _settings_dim: ColorRect
var _settings_back: Button
var _curtain: ColorRect
var _loading_notice: Label
var _ui_audio: UIAudio
var _action_audio: UIAudio
var _mix_manager: GameAudio
var _music: AudioStreamPlayer
var _graphics_page: VBoxContainer
var _camera_page: VBoxContainer
var _controls_page: VBoxContainer
var _leaderboard_window: Control
var _loading := false
var _selected := 0
var _opacity := 0.0
var _appearance_time := 0.0
var _load_progress: Array = []
var startup_controller: Node
var _boot_preparing := false
var _boot_failed := false
var _boot_scene: PackedScene
var _presentation: CanvasLayer
var _surface: Control
var _footer: Label

func _ready() -> void:
	get_window().title = game_title
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var menu_theme := Theme.new()
	menu_theme.default_font = FONT
	menu_theme.default_font_size = 24
	theme = menu_theme
	_presentation = CanvasLayer.new()
	_presentation.name = "Presentation"
	_presentation.layer = 1000
	add_child(_presentation)
	_surface = Control.new()
	_surface.theme = theme
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_presentation.add_child(_surface)
	_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage = get_node("Stage") if has_node("Stage") else Stage.new()
	if not stage.get_parent():
		stage.name = "Stage"
		_surface.add_child(stage)
	else: stage.reparent(_surface)
	stage.z_index = -100
	stage.cue.connect(_on_performance_cue)
	_build_audio()
	_load_preferences()
	_build_menu()
	_build_settings()
	_leaderboard_window = LeaderboardWindow.new()
	_surface.add_child(_leaderboard_window)
	_ui_audio.bind_controls(_leaderboard_window.page)
	_leaderboard_window.closed.connect(func():
		flow.modal_open = false
		for button in buttons: button.focus_mode = Control.FOCUS_ALL
		buttons[_selected].grab_focus()
		_ui_audio.play_action(&"close"))
	_curtain = ColorRect.new()
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_curtain.color = Color(0.015, 0.025, 0.045, 0.0)
	_surface.add_child(_curtain)
	_loading_notice = _label(_surface, "正在进入…", Vector2.ZERO, Vector2(420, 80), 24)
	_loading_notice.hide()
	resized.connect(_layout)
	_layout()
	buttons[0].grab_focus()
	if startup_controller: set_game_prepared(startup_controller.game_ready)
	elif auto_prepare_world:
		buttons[0].disabled = true
		begin_background_preparation.call_deferred()

func _build_audio() -> void:
	# The same local mix and UI pools as the map; no duplicate mix configuration.
	if startup_controller:
		_mix_manager = startup_controller.get_parent().get_node("MapEffects/GameAudio") as GameAudio
	else:
		_mix_manager = GameAudio.new()
		_mix_manager.name = "GameAudio"
		_mix_manager.max_voices = 3
		_mix_manager.important_reserve = 0
		_mix_manager.load_local_mix = save_preferences
		add_child(_mix_manager)
		_mix_manager.get_node("PlayerListener").make_current()
	_ui_audio = UIAudio.new()
	_ui_audio.sounds = ui_sounds
	_ui_audio.enabled = audio_enabled
	add_child(_ui_audio)
	_action_audio = UIAudio.new()
	_action_audio.audio_bus = &"Movement"
	_action_audio.volume_db = performance_volume_db
	_action_audio.enabled = audio_enabled
	add_child(_action_audio)
	_music = AudioStreamPlayer.new()
	_music.stream = MUSIC.stream
	_music.bus = &"Music"
	_music.finished.connect(func():
		if audio_enabled and not flow.committed: _music.play())
	add_child(_music)
	_mix_manager.mix.changed.connect(_sync_music_mix)
	_sync_music_mix()
	if audio_enabled and DisplayServer.get_name() != "headless": _music.play()

func _sync_music_mix() -> void:
	# 菜单与准备阶段共用曲目增益，内嵌菜单同时读取地图的统一 BGM 增益。
	var base_volume: float = MUSIC.volume_db
	if is_instance_valid(startup_controller):
		var bgm := startup_controller.get_parent().get_node("MapEffects/BGM") as BackgroundMusic
		base_volume += bgm.music_volume_db
	_music.volume_db = base_volume + _mix_manager.mix.clip_gain_db(_music.stream) - _opacity * 26.0

func _label(parent: Node, text_value: String, point: Vector2, dimensions: Vector2, font_size: int, color := Color("e8dcc2")) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = point
	label.size = dimensions
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _build_menu() -> void:
	_panel = Control.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.add_child(_panel)
	_panel.draw.connect(_draw_panel)
	_title = _label(_panel, game_title, Vector2(0, 32), Vector2(360, 126), 108, Color("fff0ce"))
	_title.add_theme_color_override("font_shadow_color", Color(0.91, 0.44, 0.10, 0.45))
	_title.add_theme_constant_override("shadow_offset_y", 3)
	_label(_panel, "DEMO", Vector2(0, 167), Vector2(360, 30), 18, Color("bfa875"))
	var titles := ["开始游戏", "设置", "排行榜", "退出游戏"]
	for i in titles.size():
		var button := ActionButton.new()
		button.name = ["Start", "Settings", "Leaderboard", "Quit"][i]
		button.text = titles[i]
		button.position = Vector2(34, 232 + i * 80)
		button.size = Vector2(292, 68)
		_panel.add_child(button)
		button.focus_entered.connect(_select.bind(i))
		button.mouse_entered.connect(func():
			if not flow.busy and not flow.modal_open: button.grab_focus())
		button.pressed.connect(_activate.bind(i))
		buttons.append(button)
	for i in buttons.size():
		buttons[i].focus_neighbor_top = buttons[posmod(i - 1, buttons.size())].get_path()
		buttons[i].focus_neighbor_bottom = buttons[(i + 1) % buttons.size()].get_path()
	_status = _label(_panel, "", Vector2(10, 567), Vector2(340, 44), 18, Color("d5bd8d"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer = _label(_surface, "↑ ↓ 选择   ENTER 确认", Vector2.ZERO, Vector2(500, 28), 18, Color("8fdbf5"))
	_footer.add_theme_color_override("font_outline_color", Color("101723"))
	_footer.add_theme_constant_override("outline_size", 2)
	_footer.name = "Footer"

func _draw_panel() -> void:
	var rect := Rect2(Vector2.ZERO, MENU_SIZE)
	_panel.draw_rect(rect, Color(0.025, 0.04, 0.065, 0.88))
	_panel.draw_rect(rect.grow(-5), Color(0.75, 0.56, 0.30, 0.14), false, 1.0)
	var border := Color(0.96, 0.73, 0.36, 0.62 + _opacity * 0.25)
	for corner in [Vector2.ZERO, Vector2(MENU_SIZE.x, 0), Vector2(0, MENU_SIZE.y), MENU_SIZE]:
		var direction := Vector2(1 if corner.x == 0 else -1, 1 if corner.y == 0 else -1)
		_panel.draw_line(corner, corner + Vector2(27 * direction.x, 0), border, 2.0)
		_panel.draw_line(corner, corner + Vector2(0, 27 * direction.y), border, 2.0)
	_panel.draw_line(Vector2(88, 207), Vector2(272, 207), Color(0.91, 0.68, 0.32, 0.5), 1.0)

func panel_rect_for(view_size: Vector2) -> Rect2:
	var fit := minf(1.0, minf((view_size.x - 40.0) / MENU_SIZE.x, (view_size.y - 54.0) / MENU_SIZE.y))
	fit = maxf(fit, 0.1)
	var dimensions := MENU_SIZE * fit
	return Rect2((view_size - dimensions) * 0.5, dimensions)

func _layout() -> void:
	if not _panel: return
	stage.fit_view(size)
	var rect := panel_rect_for(size)
	_panel.position = rect.position
	_panel.size = MENU_SIZE
	_panel.scale = Vector2.ONE * rect.size.x / 360.0
	_panel.pivot_offset = MENU_SIZE * 0.5
	# Scale around the panel center without moving its safe area.
	_panel.position += (_panel.scale - Vector2.ONE) * _panel.pivot_offset
	_footer.position = Vector2((size.x - 500) * 0.5, size.y - 35)
	if _settings_dim: _settings_dim.size = size
	if settings_panel:
		var fit := maxf(0.2, minf(1.0, minf((size.x - 32) / 700.0, (size.y - 32) / 640.0)))
		settings_panel.scale = Vector2.ONE * fit
		settings_panel.position = (size - Vector2(700, 640) * fit) * 0.5
	if _curtain: _curtain.size = size
	if _loading_notice: _loading_notice.position = (size - _loading_notice.size) * 0.5

func _select(index: int) -> void:
	if _selected != index and not flow.busy and not flow.modal_open:
		_ui_audio.play_action(&"navigate")
	_selected = index

func _activate(index: int) -> void:
	if flow.busy or flow.modal_open: return
	match index:
		0: start_game()
		1: open_settings()
		2: open_leaderboard()
		3:
			_ui_audio.play_action(&"confirm")
			flow.begin()
			for button in buttons: button.disabled = true
			var tween := create_tween()
			tween.tween_property(_curtain, "color:a", 1.0, 0.25)
			tween.parallel().tween_property(_music, "volume_db", -80.0, 0.25)
			tween.tween_callback(func(): get_tree().quit())

func start_game() -> void:
	if startup_controller and not startup_controller.game_ready: return
	if _boot_preparing: return
	if _boot_failed:
		begin_background_preparation()
		return
	if not flow.begin(): return
	flow.minimum_transition = start_feedback_seconds
	for button in buttons: button.disabled = true
	_ui_audio.play_action(&"confirm")
	stage.celebrate()
	_status.text = "正在出发…"
	EntryRequest.clear()
	if startup_controller:
		_loading = true
		return
	var result := ResourceLoader.load_threaded_request(world_scene, "PackedScene")
	if result != OK:
		_restore_after_error()
		return
	_loading = true
	_loading_notice.show()

func set_game_prepared(prepared: bool) -> void:
	buttons[0].disabled = not prepared
	_status.text = "" if prepared else "正在准备游戏…"

func begin_background_preparation() -> void:
	if _boot_preparing or flow.busy or startup_controller: return
	_boot_failed = false
	_boot_preparing = true
	_boot_scene = null
	buttons[0].disabled = true
	_status.text = "正在准备游戏…"
	_load_world_before_start.call_deferred()

func _load_world_before_start() -> void:
	# Present the menu first. World's scripted resource defaults initialize on the main
	# thread; the normal F5 World entry has already loaded these before showing its menu.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree() or not _boot_preparing: return
	if not ResourceLoader.exists(world_scene, "PackedScene"):
		_background_failed()
		return
	_boot_scene = load(world_scene) as PackedScene
	if not _boot_scene: _background_failed()

func _background_failed() -> void:
	_boot_preparing = false
	_boot_failed = true
	EntryRequest.clear()
	_status.text = "准备失败，点击开始重试"
	buttons[0].disabled = false

func _poll_background_preparation() -> void:
	# Keep settings usable while loading; promote only after the user closes them.
	if not _boot_scene or flow.modal_open or flow.busy: return
	_boot_preparing = false
	EntryRequest.request_menu()
	if get_tree().change_scene_to_packed(_boot_scene) != OK: _background_failed()

func _process(delta: float) -> void:
	_appearance_time += delta
	if _panel:
		var reveal := smoothstep(0.0, 0.45, _appearance_time)
		_panel.modulate.a = reveal * (1.0 - _opacity)
		_panel.queue_redraw()
	if _boot_preparing: _poll_background_preparation()
	if not _loading: return
	if startup_controller:
		var action: StringName = flow.advance(delta, startup_controller.game_ready, false)
		_update_start_fade()
		if action == &"commit":
			_loading = false
			if not startup_controller.begin_game(): _restore_after_error()
		return
	_load_progress.clear()
	var status := ResourceLoader.load_threaded_get_status(world_scene, _load_progress)
	var percent := roundi(float(_load_progress[0]) * 100.0) if not _load_progress.is_empty() else 0
	_loading_notice.text = "正在进入 · %d%%" % percent
	_loading_notice.modulate.a = 0.8 + sin(_appearance_time * 3.0) * 0.2
	var result: StringName = flow.advance(delta, status == ResourceLoader.THREAD_LOAD_LOADED, status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE])
	_update_start_fade()
	if result == &"failed": _restore_after_error()
	elif result == &"commit":
		_loading = false
		# Only fetch after LOADED, so large maps cannot freeze menu animation.
		var scene := ResourceLoader.load_threaded_get(world_scene) as PackedScene
		_handoff(scene)

func _update_start_fade() -> void:
	_opacity = smoothstep(0.3, maxf(start_feedback_seconds, 0.35), flow.elapsed) * 0.94
	_curtain.color.a = _opacity
	_sync_music_mix()

func _handoff(scene: PackedScene) -> void:
	if not scene:
		_restore_after_error()
		return
	EntryRequest.request()
	if get_tree().change_scene_to_packed(scene) != OK: _restore_after_error()

func _restore_after_error() -> void:
	EntryRequest.clear()
	_loading = false
	_loading_notice.hide()
	flow.recover()
	_opacity = 0.0
	_curtain.color.a = 0.0
	_status.text = "暂时无法进入，请重试"
	for button in buttons: button.disabled = false
	buttons[0].grab_focus()
	_sync_music_mix()
	_ui_audio.play_action(&"error")

func _on_performance_cue(event: StringName) -> void:
	if not audio_enabled or DisplayServer.get_name() == "headless": return
	var cue_name: StringName = {&"launch":&"launch", &"bounce":&"bounce_stone", &"hit":&"enemy_hit_soft", &"flyby":&"flight_end"}.get(event, &"")
	var clips := CORE.clips_for(cue_name)
	if clips.is_empty(): return
	if event == &"hit":
		var listener_position := _mix_manager.player.global_position if is_instance_valid(_mix_manager.player) else Vector3.ZERO
		_mix_manager.request({"source": self, "cue": &"menu:hit", "clips": clips,
			"position": listener_position, "kind": GameAudio.Kind.HIT, "volume_db": performance_volume_db - 3.0})
	else:
		_action_audio.play_clip(event, clips[0])

func _build_settings() -> void:
	_settings_dim = ColorRect.new()
	_settings_dim.color = Color(0.01, 0.02, 0.035, 0.80)
	_surface.add_child(_settings_dim)
	settings_panel = PanelContainer.new()
	settings_panel.name = "SettingsPanel"
	settings_panel.size = Vector2(700, 640)
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color("101c2b")
	skin.border_color = Color("a98650")
	skin.set_border_width_all(1)
	skin.set_content_margin_all(24)
	settings_panel.add_theme_stylebox_override("panel", skin)
	_surface.add_child(settings_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	settings_panel.add_child(column)
	var heading := Label.new()
	heading.text = "设置"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 36)
	column.add_child(heading)
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(tabs)
	var audio_tab := VBoxContainer.new()
	audio_tab.name = "声音与动感"
	audio_tab.add_theme_constant_override("separation", 16)
	tabs.add_child(audio_tab)
	var bus_labels := {&"Music":"音乐", &"UI":"界面反馈", &"Movement":"弹射演出", &"Combat":"战斗", &"Ambience":"环境"}
	for bus: StringName in bus_labels:
		var slider := _slider(audio_tab, bus_labels[bus], 0, 100, 1, _mix_manager.mix.bus_volume_percent(bus), "")
		slider.value_changed.connect(func(value: float):
			_mix_manager.mix.set_bus_volume_percent(bus, value)
			if save_preferences: _mix_manager.mix.save_to_path(_mix_manager.mix_save_path))
	var motion := _slider(audio_tab, "演出动感", 0, 1.5, 0.05, stage.motion_strength, "")
	motion.value_changed.connect(func(value: float):
		stage.motion_strength = value
		_save_preferences())
	var reduced := CheckButton.new()
	reduced.text = "减弱动态（关闭击飞、晃动与视差）"
	reduced.button_pressed = stage.reduced_motion
	audio_tab.add_child(reduced)
	reduced.toggled.connect(func(value: bool):
		stage.reduced_motion = value
		_save_preferences())
	var graphics_scroll := ScrollContainer.new()
	graphics_scroll.name = "画面"
	tabs.add_child(graphics_scroll)
	_graphics_page = GraphicsPage.new()
	_graphics_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graphics_page.save_enabled = save_preferences
	graphics_scroll.add_child(_graphics_page)
	_graphics_page.configure(startup_controller.get_parent() if startup_controller else self, theme)
	_camera_page = CameraPage.new()
	_camera_page.name = "镜头"
	_camera_page.save_enabled = save_preferences and DisplayServer.get_name() != "headless"
	tabs.add_child(_camera_page)
	_camera_page.configure(startup_controller.get_parent() if startup_controller else self, theme)
	get_node("/root/GameControls").changed.connect(_camera_page.sync_controls)
	var controls_scroll := ScrollContainer.new()
	controls_scroll.name = "按键"
	tabs.add_child(controls_scroll)
	_controls_page = ControlsPage.new()
	_controls_page.audio = _ui_audio
	_controls_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_scroll.add_child(_controls_page)
	_controls_page.configure(theme)
	_settings_back = Button.new()
	_settings_back.set_meta(&"ui_audio_action", &"")
	_settings_back.text = "返回"
	_settings_back.custom_minimum_size.y = 48
	_settings_back.pressed.connect(close_settings)
	column.add_child(_settings_back)
	_settings_dim.hide()
	settings_panel.hide()
	_ui_audio.bind_controls(settings_panel)

func _slider(parent: Node, label_text: String, minimum: float, maximum: float, step_size: float, initial: float, suffix: String) -> HSlider:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 132
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step_size
	slider.value = initial
	slider.custom_minimum_size.x = 290
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 88
	row.add_child(value_label)
	var update_label := func(value: float): value_label.text = ("%d" % roundi(value) if step_size >= 1.0 else "%.2f" % value) + suffix
	slider.value_changed.connect(update_label)
	update_label.call(initial)
	return slider

func open_settings() -> void:
	if flow.busy or flow.modal_open: return
	flow.modal_open = true
	for button in buttons: button.focus_mode = Control.FOCUS_NONE
	_settings_dim.show()
	settings_panel.show()
	_settings_back.grab_focus()
	_ui_audio.play_action(&"open")

func close_settings() -> void:
	if not settings_panel.visible: return
	_controls_page.cancel_capture()
	flow.modal_open = false
	_settings_dim.hide()
	settings_panel.hide()
	for button in buttons: button.focus_mode = Control.FOCUS_ALL
	buttons[_selected].grab_focus()
	_ui_audio.play_action(&"close")

func open_leaderboard() -> void:
	if flow.busy or flow.modal_open: return
	flow.modal_open = true
	for button in buttons: button.focus_mode = Control.FOCUS_NONE
	_leaderboard_window.open()
	_ui_audio.play_action(&"open")

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		if _leaderboard_window.visible: _leaderboard_window.close()
		elif flow.modal_open: close_settings()
		elif not flow.busy: buttons[-1].grab_focus()
		get_viewport().set_input_as_handled()

func _load_preferences() -> void:
	if not save_preferences: return
	var config := ConfigFile.new()
	if config.load(PREFERENCES) != OK: return
	var strength: Variant = config.get_value("stage", "motion_strength", 1.0)
	if (strength is float or strength is int) and is_finite(float(strength)):
		stage.motion_strength = clampf(float(strength), 0.0, 1.5)
	stage.reduced_motion = config.get_value("stage", "reduced_motion", false) == true

func _save_preferences() -> void:
	if not save_preferences: return
	var config := ConfigFile.new()
	config.set_value("stage", "motion_strength", stage.motion_strength)
	config.set_value("stage", "reduced_motion", stage.reduced_motion)
	config.save(PREFERENCES)
