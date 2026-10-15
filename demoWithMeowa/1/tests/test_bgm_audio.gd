extends SceneTree

## 原生音频集成验证：真实 MP3／OGG 接缝、快速切换与正式地图状态。
const OUT := "D:/.codexfile/work/bgm-framework-20261015/"
const MUSIC := preload("res://scripts/audio/bgm.gd")
var bgm: BackgroundMusic
var capture: AudioEffectCapture
var samples := PackedVector2Array()
var checks := 0
var failures := 0
var bus := -1
var effect_index := -1
var starts: Array[StringName] = []

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func segment(label: String, seconds: float, require_sound := true) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	var energy := 0.0
	var count := 0
	var silent_windows := 0
	var window_energy := 0.0
	var window_count := 0
	var peak := 0.0
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var frames := capture.get_buffer(capture.get_frames_available())
		samples.append_array(frames)
		count += frames.size()
		for sample in frames:
			var power := sample.length_squared() * 0.5
			energy += power
			window_energy += power
			window_count += 1
			peak = maxf(peak, maxf(absf(sample.x), absf(sample.y)))
			if window_count == 4096:
				if sqrt(window_energy / window_count) < db_to_linear(-80.0): silent_windows += 1
				window_count = 0
				window_energy = 0.0
	check(capture.get_discarded_frames() == 0, label + "：音频采集无丢帧")
	if require_sound:
		check(count > 0 and energy > 0.0 and peak < 1.0 and silent_windows == 0, label + "：实际输出非静音、无削波或长静音缝隙")
	print("AUDIO ", label, " samples=", count, " peak=", linear_to_db(maxf(peak, 0.000001)), " silent_windows=", silent_windows, " ", bgm.get_playback_state())

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("此测试需要原生音频设备；逻辑检查使用 test_bgm.gd")
		quit(2)
		return
	AudioServer.set_bus_mute(0, true)
	bus = AudioServer.get_bus_index(&"Music")
	check(bus >= 0, "项目已有独立 Music 总线")
	capture = AudioEffectCapture.new()
	# 正式地图同步载入期间主线程不能取样，预留足够的音频线程缓冲。
	capture.buffer_length = 12.0
	effect_index = AudioServer.get_bus_effect_count(bus)
	AudioServer.add_bus_effect(bus, capture)
	bgm = MUSIC.new()
	bgm.music_volume_db = 0.0
	bgm.music_fade_time = 0.1
	bgm.follow_battle_session = false
	bgm.playlists = [load("res://data/audio/music/exploration_playlist.tres"), load("res://data/audio/music/combat_playlist.tres")]
	bgm.track_started.connect(func(id): starts.append(id))
	root.add_child(bgm)
	await segment("首次淡入", 0.6, false)
	var active := bgm._active
	var track := bgm._tracks[active]
	bgm._players[active].seek(track.stream.get_length() - track.loop_crossfade - 0.4)
	await segment("探索曲真实 MP3 循环", track.loop_crossfade + 1.0)
	check(bgm._active != active and not bgm._blending and bgm.get_playback_state().voices == 1, "真实探索曲末尾进入下一轮并回收旧实例")
	bgm.play_context(&"combat")
	await segment("探索转战斗", bgm.music_transition_time + 0.3)
	check(bgm.get_playback_state().track == &"garden_battle", "原生播放器完成两首曲目之间的切换")
	active = bgm._active
	track = bgm._tracks[active]
	bgm._players[active].seek(track.stream.get_length() - track.loop_crossfade - 0.4)
	await segment("战斗曲真实 OGG 循环", track.loop_crossfade + 1.0)
	check(bgm._active != active and not bgm._blending and bgm.get_playback_state().voices == 1, "真实战斗曲末尾进入下一轮并回收旧实例")
	var voice := bgm._players[bgm._active].stream
	var position := bgm.get_playback_state().position as float
	paused = true
	await segment("暂停连续播放", 0.4)
	paused = false
	check(bgm._players[bgm._active].stream == voice and bgm.get_playback_state().position > position + 0.2, "暂停期间真实播放头继续前进")
	bgm.play_context(&"exploration")
	await segment("短暂结算", 0.35)
	bgm.play_context(&"combat")
	await segment("快速重试反向衔接", bgm.music_transition_time + 0.3)
	check(bgm._players[bgm._active].stream == voice and bgm.get_playback_state().voices == 1, "快速重试沿用尚未退出的战斗音轨")
	bgm.play_context(&"exploration")
	await segment("战斗转结算", bgm.music_transition_time + 0.3)
	check(bgm.get_playback_state().track == &"exploration", "结算实际切回探索曲")
	await expanded_pool()
	bgm.queue_free()
	await process_frame
	await process_frame
	await formal_scene()
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 4)
	for index in samples.size():
		bytes.encode_s16(index * 4, int(clampf(samples[index].x, -1.0, 1.0) * 32767.0))
		bytes.encode_s16(index * 4 + 2, int(clampf(samples[index].y, -1.0, 1.0) * 32767.0))
	var recording := AudioStreamWAV.new()
	recording.format = AudioStreamWAV.FORMAT_16_BITS
	recording.mix_rate = int(AudioServer.get_mix_rate())
	recording.stereo = true
	recording.data = bytes
	DirAccess.make_dir_recursive_absolute(OUT)
	recording.save_to_wav(OUT + "transitions-qa.wav")
	AudioServer.remove_bus_effect(bus, effect_index)
	capture = null
	await process_frame
	print("BGM audio integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func expanded_pool() -> void:
	var track := bgm._tracks[bgm._active]
	bgm._players[bgm._active].seek(track.stream.get_length() - track.loop_crossfade + 0.1)
	await segment("单曲循环衔接进行中", 0.25)
	check(bgm._blending and bgm.get_playback_state().voices == 2, "真实单曲循环同时占用两路")
	bgm.play_context(&"combat")
	check(bgm.get_playback_state().queued == &"garden_battle", "单曲循环中收到开战请求，以最新曲目进入待播")
	await segment("循环途中开战衔接", 3.0)
	check(bgm.get_playback_state().track == &"garden_battle" and bgm.get_playback_state().voices == 1, "循环途中开战无额外播放器或旧目标滞留")
	var rotation := BgmPlaylist.new()
	rotation.context_id = &"rotation"
	rotation.tracks = [bgm.playlists[0].tracks[0], bgm.playlists[1].tracks[0]]
	bgm.playlists.append(rotation)
	bgm.play_context(&"rotation")
	await segment("新增多曲池入场", bgm.music_transition_time + 0.3)
	check(bgm.get_playback_state().track == &"exploration", "新增曲池从首曲开始实际播放")
	track = bgm._tracks[bgm._active]
	bgm._players[bgm._active].seek(track.stream.get_length() - track.loop_crossfade - 0.4)
	await segment("多曲池自动轮播", track.loop_crossfade + 1.0)
	check(bgm.get_playback_state().context == &"rotation" and bgm.get_playback_state().track == &"garden_battle" and bgm._players.size() == 2, "同一曲池真实播放到结尾自动衔接下一首")

func formal_scene() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	world.get_node("MapEffects/GameAudio").enabled = false
	var wave: WavePrototype = world.get_node("WavePrototype")
	wave.population_rules = wave.population_rules.duplicate(true)
	wave.population_rules.simulation_mode = true
	wave.population_rules.simulation_enemy_count = 1
	bgm = world.get_node("MapEffects/BGM")
	bgm.music_fade_time = 0.1
	root.add_child(world)
	current_scene = world
	await segment("正式地图准备阶段", 1.0, false)
	check(bgm.session == wave and bgm.get_playback_state().context == &"exploration", "正式地图绑定真实波次，准备阶段选曲正确")
	var player: Player = world.get_node("Player")
	player.global_position = wave.global_position + Vector3.UP * 0.03
	for frame in 5: await physics_frame
	check(wave.start_run(), "真实巨量怪潮模式开始成功")
	await segment("正式地图真实开战", 2.9)
	check(bgm.get_playback_state().context == &"combat" and bgm.get_playback_state().track == &"garden_battle", "真实开战事件切入战斗曲")
	var voice := bgm._players[bgm._active].stream
	wave._set_phase(WavePrototype.Phase.REST)
	await segment("正式地图波间休整", 0.4)
	check(bgm._players[bgm._active].stream == voice, "真实波次节点切入休整不重播音乐")
	wave._set_phase(WavePrototype.Phase.BATTLE)
	wave.set_combat_frozen(true)
	await segment("正式地图升级冻结", 0.4)
	check(bgm._players[bgm._active].stream == voice and not bgm._players[bgm._active].stream_paused, "真实战斗冻结保留音乐连续播放")
	wave.set_combat_frozen(false)
	wave.retreat()
	await segment("正式地图真实结算", 2.9)
	check(bgm.get_playback_state().context == &"exploration" and bgm.get_playback_state().track == &"exploration", "真实撤退结算切回探索曲")
	bgm.music_enabled = false
	await segment("关闭音乐", 0.4, false)
	check(bgm.get_playback_state().voices == 0, "正式地图音乐关闭后停止两路播放")
	world.queue_free()
	for frame in 4: await process_frame
