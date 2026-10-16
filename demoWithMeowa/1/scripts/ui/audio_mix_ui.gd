class_name AudioMixUI
extends CanvasLayer

signal settings_requested

@export var audio: GameAudio
@export var feedback: CoreFeedbackAudio
@export var loadout: LoadoutUI

const BUS_NAMES := ["战斗音效", "背景音乐", "雨声与风声", "界面与成长", "脚步与闪身"]
var menu_open := false
var _entries: Array[Dictionary] = []
var _index := 0
var _launcher: Button
var _root: Control
var _panel: PanelContainer
var _select: OptionButton
var _purpose: Label
var _clip_slider: HSlider
var _clip_number: SpinBox
var _mute: CheckBox
var _loop: CheckBox
var _status: Label
var _bus_sliders: Array[HSlider] = []
var _bus_labels: Array[Label] = []
var _preview: AudioStreamPlayer
var _save_timer: Timer
var _dirty := false
var _embedded := false
var _close_button: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	if not audio or not feedback or not feedback.sounds: return
	_entries = feedback.sounds.audition_entries()
	if _entries.is_empty(): return
	_build_ui()
	audio.mix.changed.connect(_mix_changed)
	get_viewport().size_changed.connect(_fit)
	_fit()
	_refresh()

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(callback)
	return button

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func _slider() -> HSlider:
	var slider := HSlider.new()
	slider.min_value = AudioMixSettings.MIN_DB
	slider.max_value = AudioMixSettings.MAX_DB
	slider.step = 0.5
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(100, 30)
	return slider

func _build_ui() -> void:
	var theme := loadout._theme.duplicate() as Theme if loadout and loadout._theme else Theme.new()
	theme.default_font_size = 18
	var select_skin := StyleBoxTexture.new()
	select_skin.texture = preload("res://assets/meowa/ui/journal/controls/category.png")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		select_skin.set_texture_margin(side, 16)
		select_skin.set_content_margin(side, 16 if side in [SIDE_LEFT, SIDE_RIGHT] else 7)
	# 表单不继承手帐动作按钮的尖角边框，保留原生勾选标记。
	for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		theme.set_stylebox(state, "CheckBox", StyleBoxEmpty.new())
		theme.set_stylebox(state, "OptionButton", select_skin)
	for color in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		theme.set_color(color, "CheckBox", LoadoutUI.INK)
		theme.set_color(color, "OptionButton", LoadoutUI.INK)
	_launcher = _button("声音调试", open_menu)
	_launcher.theme = theme
	_launcher.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	add_child(_launcher)
	_root = Control.new()
	_root.theme = theme
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.hide()
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.24)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	_panel = PanelContainer.new()
	var skin := StyleBoxTexture.new()
	skin.texture = preload("res://assets/meowa/ui/journal/controls/details.png")
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		skin.set_texture_margin(side, 16)
		skin.set_content_margin(side, 20)
	_panel.add_theme_stylebox_override("panel", skin)
	_root.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 9)
	scroll.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := _label("声音设置")
	title.add_theme_font_size_override("font_size", 25)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_close_button = _button("关闭 · ESC", close_menu)
	header.add_child(_close_button)
	content.add_child(_label("实时生效 · 本机自动保存 · 0 dB 为游戏默认音量"))
	content.add_child(HSeparator.new())
	for index in AudioMixSettings.BUSES.size():
		var row := HBoxContainer.new()
		content.add_child(row)
		var label := _label(BUS_NAMES[index])
		label.custom_minimum_size.x = 126
		row.add_child(label)
		var slider := _slider()
		row.add_child(slider)
		_bus_sliders.append(slider)
		var value := _label("0.0 dB")
		value.custom_minimum_size.x = 78
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)
		_bus_labels.append(value)
		slider.value_changed.connect(func(db: float): audio.mix.set_bus_gain(AudioMixSettings.BUSES[index], db))
	content.add_child(HSeparator.new())
	content.add_child(_label("%d 条核心音效 · 单独调整每个变体" % _entries.size()))
	_select = OptionButton.new()
	_select.fit_to_longest_item = false
	_select.custom_minimum_size.y = 40
	for entry in _entries: _select.add_item("%s · %s / %s" % [entry.id, entry.group, entry.label])
	_select.item_selected.connect(select_entry)
	content.add_child(_select)
	_purpose = _label("")
	_purpose.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_purpose.custom_minimum_size.y = 46
	content.add_child(_purpose)
	var clip_row := HBoxContainer.new()
	content.add_child(clip_row)
	clip_row.add_child(_label("本条增益"))
	_clip_slider = _slider()
	_clip_slider.value_changed.connect(_set_clip_gain)
	clip_row.add_child(_clip_slider)
	_clip_number = SpinBox.new()
	_clip_number.min_value = AudioMixSettings.MIN_DB
	_clip_number.max_value = AudioMixSettings.MAX_DB
	_clip_number.step = 0.5
	_clip_number.suffix = " dB"
	_clip_number.custom_minimum_size.x = 124
	_clip_number.value_changed.connect(_set_clip_gain)
	clip_row.add_child(_clip_number)
	_mute = CheckBox.new()
	_mute.custom_minimum_size.y = 36
	_mute.text = "静音本条（战斗中也生效）"
	_mute.toggled.connect(func(value: bool): audio.mix.set_clip_muted(_clip_path(), value))
	content.add_child(_mute)
	var playback := HBoxContainer.new()
	content.add_child(playback)
	playback.add_child(_button("试听当前", play_selected))
	playback.add_child(_button("停止", stop_preview))
	_loop = CheckBox.new()
	_loop.custom_minimum_size.y = 36
	_loop.text = "循环试听"
	playback.add_child(_loop)
	var footer := HBoxContainer.new()
	content.add_child(footer)
	footer.add_child(_button("恢复本条", func(): audio.mix.reset_clip(_clip_path())))
	footer.add_child(_button("全部默认", audio.mix.reset_all))
	footer.add_child(_button("保存到本机", save_mix))
	_status = _label("已读取本机音量；调整不会改写项目默认资源。")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_status)
	_preview = AudioStreamPlayer.new()
	_preview.name = "SingleAuditionVoice"
	_preview.finished.connect(func():
		if menu_open and _loop.button_pressed: _preview.play())
	add_child(_preview)
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.4
	_save_timer.timeout.connect(save_mix)
	add_child(_save_timer)

func _fit() -> void:
	if not _root or _embedded: return
	var viewport := get_viewport().get_visible_rect().size
	_launcher.position = Vector2(viewport.x - 148, 22)
	_launcher.size = Vector2(126, 42)
	_panel.size = Vector2(minf(660.0, viewport.x - 32), minf(790.0, viewport.y - 32))
	_panel.position = Vector2(viewport.x - _panel.size.x - 16, 16)

func open_menu() -> void:
	if _embedded:
		settings_requested.emit()
		return
	if not _root or get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null: return
	menu_open = true
	add_to_group(&"gameplay_input_blockers")
	_root.show()
	_launcher.hide()
	_refresh()

func close_menu() -> void:
	if _embedded:
		set_embedded_visible(false)
		return
	if not menu_open: return
	stop_preview()
	if _dirty: save_mix()
	menu_open = false
	remove_from_group(&"gameplay_input_blockers")
	_root.hide()
	_launcher.show()

func _input(event: InputEvent) -> void:
	if not _embedded and menu_open and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_menu()
		get_viewport().set_input_as_handled()

func embed_in(host: Control, settings_theme: Theme) -> void:
	if not _panel: return
	_embedded = true
	_launcher.hide()
	_close_button.hide()
	_panel.reparent(host)
	_panel.theme = settings_theme
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	set_embedded_visible(false)

func set_embedded_visible(value: bool) -> void:
	menu_open = value
	_panel.visible = value
	if value:
		_refresh()
	else:
		stop_preview()
		if _dirty: save_mix()

func _unhandled_key_input(_event: InputEvent) -> void:
	if menu_open: get_viewport().set_input_as_handled()

func select_entry(index: int) -> void:
	if index < 0 or index >= _entries.size(): return
	stop_preview()
	_index = index
	_refresh()

func _clip_path() -> String:
	return audio.mix.clip_path(_entries[_index].clip)

func _set_clip_gain(value: float) -> void:
	audio.mix.set_clip_gain(_clip_path(), value)

func _mix_changed() -> void:
	_dirty = true
	_refresh()
	_status.text = "已实时应用 · 正在保存到本机…"
	_save_timer.start()

func _refresh() -> void:
	for index in AudioMixSettings.BUSES.size():
		var gain := float(audio.mix.bus_gains.get(String(AudioMixSettings.BUSES[index]), 0.0))
		_bus_sliders[index].set_value_no_signal(gain)
		_bus_labels[index].text = "%+.1f dB" % gain
	var entry := _entries[_index]
	_select.select(_index)
	_purpose.text = entry.purpose
	var gain := float(audio.mix.clip_gains.get(_clip_path(), 0.0))
	_clip_slider.set_value_no_signal(gain)
	_clip_number.set_value_no_signal(gain)
	_mute.set_pressed_no_signal(audio.mix.is_clip_muted(entry.clip))
	if _preview and _preview.stream:
		_preview.volume_db = _event_volume(entry.cue) + audio.mix.clip_gain_db(_preview.stream)

func _event_volume(cue: StringName) -> float:
	if cue == &"flight_loop": return feedback.action_volume_db + feedback.flight_gain_db
	if cue in [&"bounce_stone", &"bounce_wood", &"bounce_metal"]:
		return feedback.action_volume_db + feedback.bounce_gain_db
	if cue in [&"storm_strike", &"storm_chain"]:
		var storm := feedback.session.get_node_or_null("RicochetStorm") as RicochetStorm if feedback.session else null
		if storm: return storm.hit_volume_db + (storm.propagation_layer_gain_db if cue == &"storm_chain" else 0.0)
		return -19.0 if cue == &"storm_strike" else -22.0
	if cue in [&"enemy_hit_soft", &"enemy_hit_hard", &"slime_death", &"creature_death", &"split_spawn"]:
		return feedback.enemy_volume_db
	if cue == &"growth_apply" and feedback.session:
		var skills := feedback.session.get_node_or_null("RunSkills") as RunSkills
		if skills and skills.initial_choice:
			var ui := skills.initial_choice._audio
			return ui.volume_db + float(ui.sounds.gains_db.get(&"confirm", 0.0))
	var offsets := {&"charge_start": -2.0, &"charge_loop": -3.0, &"charge_ready": -2.0,
		&"flight_end": -5.0, &"push_stun": -3.0, &"player_hurt": 1.0,
		&"experience": -5.0, &"low_health": -2.0, &"card_reveal": -4.0,
		&"reroll": -2.0, &"wave_start": -3.0, &"horde_arrival": -4.0}
	var bus := _event_bus(cue)
	return (feedback.feedback_volume_db if bus == &"UI" else feedback.action_volume_db) + float(offsets.get(cue, 0.0))

func _event_bus(cue: StringName) -> StringName:
	return &"UI" if cue in [&"experience", &"level_up", &"card_reveal", &"reroll", &"growth_apply",
		&"low_health", &"defeat", &"wave_start", &"horde_arrival", &"wave_clear"] else &"Combat"

func play_selected() -> void:
	if not menu_open: return
	_preview.stop()
	var entry := _entries[_index]
	_preview.stream = entry.clip
	_preview.bus = _event_bus(entry.cue)
	_preview.volume_db = _event_volume(entry.cue) + audio.mix.clip_gain_db(entry.clip)
	_preview.play()
	_status.text = "试听 %s · %s%s" % [entry.id, entry.label, "（当前已静音）" if _mute.button_pressed else ""]

func stop_preview() -> void:
	if _preview: _preview.stop()

func save_mix() -> void:
	_save_timer.stop()
	var result := audio.mix.save_to_path(audio.mix_save_path)
	_dirty = result != OK
	_status.text = "已保存到本机，重启后继续生效。" if result == OK else "保存失败：%s；当前音量仍已实时生效。" % error_string(result)

func _exit_tree() -> void:
	if is_instance_valid(_preview): _preview.stop()
	if _dirty and is_instance_valid(audio): audio.mix.save_to_path(audio.mix_save_path)
