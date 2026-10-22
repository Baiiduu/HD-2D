extends SceneTree

const WORK := "D:/.codexfile/work/game-audio-mix-20261015"
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(35.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func near(actual: float, expected: float, label: String) -> void:
	check(is_equal_approx(actual, expected), "%s: %.3f / %.3f" % [label, actual, expected])

func run() -> void:
	DirAccess.make_dir_recursive_absolute(WORK)
	AudioServer.set_bus_mute(0, true)
	var bank := load("res://data/audio/core_sound_bank.tres") as CoreSoundBank
	var entries := bank.audition_entries()
	check(entries.size() == 54, "完整索引五十三条实战音源与一条停用候选")
	var paths := {}
	for entry in entries:
		check(entry.clip is AudioStream and not entry.clip.resource_path.is_empty(), "试听音源具有稳定的资源路径：" + entry.id)
		paths[entry.clip.resource_path] = true
	check(paths.size() == 54, "每个变体独立调节")
	check(entries[37].cue == &"storm_strike" and entries[39].cue == &"storm_chain", "试听编号与原网页一致")
	check(entries[40].cue == &"flight_loop" and entries[40].id == "S41", "新增动能气流追加在末尾，旧试听编号保持")
	check(entries[41].cue == &"kill_slime_retired" and entries[42].cue == &"kill_slime" and entries[45].cue == &"kill_land", "停用候选保留 S42，原击杀反馈编号不变")
	check(entries[46].id == "S47" and entries[48].cue == &"enemy_hit_common", "三条通用命中追加 S47–S49")
	check(entries[49].id == "S50" and entries[49].cue == &"leaf_windup" and entries[52].cue == &"pot_shatter", "怪物原有招式音源追加 S50–S53，不改变原编号")
	check(entries[53].id == "S54" and entries[53].cue == &"charge_wind", "聚力风追加 S54，原试听编号保持")
	var settings := AudioMixSettings.new()
	check(settings.has_method("set_bus_volume_percent"), "分组音量提供 0–100 百分比接口")
	if not settings.has_method("set_bus_volume_percent"):
		quit(1)
		return
	for bus in AudioMixSettings.BUSES:
		near(settings.bus_volume_percent(bus), 50.0, "默认音量在滑块中点：" + String(bus))
	settings.set_bus_volume_percent(&"Music", 50.0)
	near(settings.bus_volume_percent(&"Music"), 50.0, "百分比保留实际线性音量")
	near(float(settings.bus_gains.get("Music", 0.0)), 0.0, "50 对应既有默认混音")
	settings.set_bus_volume_percent(&"Music", 75.0)
	near(settings.bus_volume_percent(&"Music"), 75.0, "默认之上仍可调高")
	near(settings.bus_gains.Music, linear_to_db(1.5), "75 真正放大声音而不只是改变数字")
	settings.set_bus_volume_percent(&"Music", 0.0)
	check(settings.is_bus_muted(&"Music"), "0 对应静音")
	settings.set_bus_volume_percent(&"Music", 200.0)
	near(settings.bus_volume_percent(&"Music"), 100.0, "音量上限为 100")
	near(float(settings.bus_gains.get("Music", 0.0)), linear_to_db(2.0), "100 保留默认之上的完整放大余量")
	settings.set_bus_volume_percent(&"Music", -10.0)
	check(settings.is_bus_muted(&"Music"), "负音量钳制为静音")
	settings.set_bus_volume_percent(&"Music", NAN)
	check(settings.is_bus_muted(&"Music"), "非法数值不破坏当前音量")
	check(settings.save_to_path(WORK + "/percent.cfg") == OK, "零音量可保存")
	var percent_restore := AudioMixSettings.new()
	check(percent_restore.load_from_path(WORK + "/percent.cfg") == OK and percent_restore.is_bus_muted(&"Music"), "重启保留零音量")
	settings.set_bus_gain(&"Music", -6.0)
	near(settings.bus_volume_percent(&"Music"), db_to_linear(-6.0) * 50.0, "旧增益存档可转换成新刻度")
	settings.set_bus_gain(&"Music", 6.0)
	near(settings.bus_volume_percent(&"Music"), db_to_linear(6.0) * 50.0, "旧正增益仍可保留")
	var legacy := ConfigFile.new()
	legacy.set_value("mix", "version", 1)
	legacy.set_value("buses", "Music", -6.0)
	legacy.set_value("buses", "Combat", 6.0)
	legacy.save(WORK + "/legacy.cfg")
	check(percent_restore.load_from_path(WORK + "/legacy.cfg") == OK, "旧增益存档仍可加载")
	near(percent_restore.bus_volume_percent(&"Music"), db_to_linear(-6.0) * 50.0, "旧存档保留原衰减音量")
	near(percent_restore.bus_volume_percent(&"Combat"), db_to_linear(6.0) * 50.0, "旧存档保留原放大音量")
	var first := entries[0].clip as AudioStream
	var path := first.resource_path
	near(settings.clip_gain_db(first), 0.0, "默认保持原音量")
	settings.set_clip_gain(path, -6.0)
	near(settings.clip_gain_db(first), -6.0, "单条增益")
	settings.set_clip_gain(path, -100.0)
	near(settings.clip_gain_db(first), -40.0, "低端钳制")
	settings.set_clip_gain(path, 100.0)
	near(settings.clip_gain_db(first), 6.0, "高端钳制")
	settings.set_clip_gain(path, NAN)
	near(settings.clip_gain_db(first), 6.0, "忽略非法数值")
	settings.set_clip_gain(path, -8.5)
	settings.set_clip_muted(path, true)
	check(settings.is_clip_muted(first), "本条静音")
	settings.set_bus_gain(&"Combat", -10.0)
	check(settings.save_to_path(WORK + "/roundtrip.cfg") == OK, "本机配置可保存")
	var restored := AudioMixSettings.new()
	check(restored.load_from_path(WORK + "/roundtrip.cfg") == OK, "重建后可加载")
	check(restored.is_clip_muted(first), "重启保留静音")
	restored.set_clip_muted(path, false)
	near(restored.clip_gain_db(first), -8.5, "解除静音保留原调节")
	near(restored.bus_gains.Combat, -10.0, "重启保留分组增益")
	var corrupt := ConfigFile.new()
	corrupt.set_value("mix", "version", 99)
	corrupt.save(WORK + "/invalid.cfg")
	check(restored.load_from_path(WORK + "/invalid.cfg") == ERR_INVALID_DATA, "拒绝不兼容存档")
	near(restored.clip_gain_db(first), -8.5, "加载失败不破坏正在使用的调节")
	var world := Node3D.new()
	root.add_child(world)
	var listener := Node3D.new()
	world.add_child(listener)
	var audio := GameAudio.new()
	audio.player = listener
	audio.load_local_mix = false
	audio.mix_save_path = WORK + "/live.cfg"
	world.add_child(audio)
	var feedback := load("res://scenes/audio/core_feedback_audio.tscn").instantiate() as CoreFeedbackAudio
	world.add_child(feedback)
	var loadout := load("res://scenes/ui/loadout_ui.tscn").instantiate() as LoadoutUI
	loadout.save_enabled = false
	loadout.motion_enabled = false
	world.add_child(loadout)
	var panel := load("res://scenes/ui/audio_mix_ui.tscn").instantiate() as AudioMixUI
	panel.audio = audio
	panel.feedback = feedback
	panel.loadout = loadout
	world.add_child(panel)
	await process_frame
	near(panel._event_volume(&"flight_loop"), feedback.action_volume_db + feedback.flight_gain_db, "气流试听与实际参考速度共用基础音量")
	near(panel._event_volume(&"enemy_hit_common"), feedback.enemy_volume_db, "通用命中试听与实战共用音量基准")
	feedback.charge_progress_audio_enabled = true
	feedback.charge_full_gain_db = -4.0
	near(panel._event_volume(&"charge_loop"), feedback._charge_volume(1.0), "渐强蓄力试听与实际满蓄音量一致")
	near(panel._event_volume(&"charge_wind"), feedback._charge_wind_volume(1.0), "聚力风试听使用实际满蓄音量")
	near(panel._event_volume(&"charge_ready"), feedback.action_volume_db + feedback.charge_ready_gain_db, "满蓄提示试听与真实提示增益一致")
	feedback.launch_release_audio_enabled = true
	near(panel._event_volume(&"launch"), feedback.action_volume_db + feedback.launch_full_gain_db, "发射试听沿用满蓄发射增益与本机混音入口")
	feedback.launch_release_audio_enabled = false
	near(panel._event_volume(&"launch"), feedback.action_volume_db, "关闭释放编排保留原发射试听音量")
	var event := {"source": listener, "cue": &"mix_test", "kind": GameAudio.Kind.HURT,
		"clips": [first], "position": Vector3.ZERO, "volume_db": -11.0}
	audio.mix.set_clip_gain(path, -6.0)
	var voice := audio.request(event)
	check(voice != null, "真实战斗池可以播放")
	near(voice.volume_db, -17.0, "真实战斗音叠加单条增益")
	audio.mix.set_clip_gain(path, -3.0)
	audio._process(0.0)
	near(voice.volume_db, -14.0, "正在播放的声音实时更新")
	audio.mix.set_clip_muted(path, true)
	audio._process(0.0)
	check(voice.volume_db <= -80.0, "进行中的声音立即静音")
	check(audio.request(event) == null, "静音音源不创建新战斗播放")
	audio.mix.reset_all()
	audio.stop_all()
	var source_loop := bank.clips_for(&"charge_loop")[0] as AudioStream
	var loop := source_loop.duplicate() as AudioStream
	loop.set_meta(&"mix_source_path", source_loop.resource_path)
	audio.mix.set_clip_gain(source_loop.resource_path, -7.0)
	near(audio.mix.clip_gain_db(loop), -7.0, "蓄力运行时的循环副本仍匹配原音源")
	var confirmation := bank.clips_for(&"growth_apply")[0] as AudioStream
	audio.mix.set_clip_gain(confirmation.resource_path, -7.0)
	check(feedback._ui.play_clip(&"confirm", confirmation, 2.0), "真实 UI 池可播放成长确认")
	var ui_voice := feedback._ui._voices[0]
	near(ui_voice.volume_db, -17.0, "成长确认声也使用本机增益")
	audio.mix.set_clip_gain(confirmation.resource_path, -3.0)
	near(ui_voice.volume_db, -13.0, "进行中的界面声音实时更新")
	audio.mix.set_bus_gain(&"Combat", -8.0)
	near(AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"Combat")), audio.combat_volume_db - 8.0, "分组音量接入实际总线")
	for index in AudioMixSettings.BUSES.size():
		var bus: StringName = AudioMixSettings.BUSES[index]
		var bus_index := AudioServer.get_bus_index(bus)
		var slider := panel._bus_sliders[index]
		check(slider.min_value == 0 and slider.max_value == 100 and slider.step == 1, "分组滑块使用整数 0–100：" + String(bus))
		slider.value = 0
		check(AudioServer.is_bus_mute(bus_index) and panel._bus_labels[index].text == "0", "拖到 0 真正静音且不显示 dB：" + String(bus))
		slider.value = 50
		check(not AudioServer.is_bus_mute(bus_index) and panel._bus_labels[index].text == "50", "从静音恢复到 50：" + String(bus))
		near(audio.mix.bus_volume_percent(bus), 50.0, "滑块同步实际百分比：" + String(bus))
		var default_level := AudioServer.get_bus_volume_db(bus_index)
		slider.value = 100
		check(not AudioServer.is_bus_mute(bus_index), "满音量解除静音：" + String(bus))
		near(AudioServer.get_bus_volume_db(bus_index) - default_level, linear_to_db(2.0), "50–100 增加真实播放音量：" + String(bus))
	panel.open_menu()
	check(panel.menu_open and panel.is_in_group(&"gameplay_input_blockers"), "面板接管人物输入")
	check(not paused and not audio._frozen, "声音调试不会暂停世界或战斗音")
	for viewport_size in [Vector2i(1440, 900), Vector2i(1024, 640), Vector2i(640, 480)]:
		root.content_scale_size = Vector2i.ZERO
		root.size = viewport_size
		for frame in 4: await process_frame
		panel._fit()
		for frame in 4: await process_frame
		var viewport := panel.get_viewport().get_visible_rect()
		check(viewport.encloses(panel._panel.get_global_rect()), "调音面板适配视口：" + str(viewport_size))
		check(panel._clip_number.get_global_rect().end.x <= viewport.end.x, "数字输入不超出视口：" + str(viewport_size))
		check(panel._select.get_global_rect().end.x <= viewport.end.x, "音源选择不超出视口：" + str(viewport_size))
	for index in entries.size():
		panel.select_entry(index)
		panel.play_selected()
		check(panel._preview.stream == entries[index].clip and panel._preview.bus == panel._event_bus(entries[index].cue), "逐条试听实际音源与实际分组：" + entries[index].id)
	panel.select_entry(0)
	panel.play_selected()
	panel._clip_number.value = -8.0
	near(audio.mix.clip_gain_db(first), -8.0, "数字输入实际改变运行混音")
	panel._clip_slider.value = -9.0
	near(panel._clip_number.value, -9.0, "滑杆与数字同步")
	near(panel._preview.volume_db, feedback.action_volume_db - 2.0 - 9.0, "试听沿用当前动作事件音量")
	panel._mute.button_pressed = true
	check(audio.mix.is_clip_muted(first), "界面静音影响真实战斗音源")
	panel._loop.button_pressed = true
	panel._preview.finished.emit()
	check(panel._preview.playing, "循环试听复用单个播放器")
	check(panel.get_children().filter(func(node): return node is AudioStreamPlayer).size() == 1, "试听始终只有一个声道")
	await create_timer(0.55).timeout
	var after_restart := AudioMixSettings.new()
	check(after_restart.load_from_path(audio.mix_save_path) == OK, "界面调整自动保存到独立路径")
	near(after_restart.clip_gains.get(path, 0.0), -9.0, "自动保存单条增益")
	check(after_restart.is_clip_muted(first), "自动保存本条静音")
	panel.close_menu()
	check(not panel.menu_open and not panel.is_in_group(&"gameplay_input_blockers"), "关闭释放人物输入")
	check(not panel._preview.playing, "关闭停止循环试听")
	panel.open_menu()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	panel._input(escape)
	check(not panel.menu_open, "ESC 关闭调试页")
	panel.open_menu()
	audio.mix.reset_all()
	panel.close_menu()
	check(after_restart.load_from_path(audio.mix_save_path) == OK and after_restart.clip_gains.is_empty() and after_restart.bus_gains.is_empty() and after_restart.clip_mutes.is_empty(), "恢复默认完整保存，项目默认资源不变")
	panel.queue_free()
	await process_frame
	check(get_first_node_in_group(&"gameplay_input_blockers") == null, "界面卸载不残留输入占用")
	world.queue_free()
	await process_frame
	# 等音频线程完成最后一块混音及停止请求，避免在播放资源仍被持有时退出。
	await create_timer(0.15).timeout
	print("Audio mix: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
