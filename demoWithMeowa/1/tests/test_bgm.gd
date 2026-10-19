extends SceneTree

const MUSIC := preload("res://scripts/audio/bgm.gd")
const SESSION := preload("res://tests/fixtures/ricochet_session.gd")
var checks := 0
var failures := 0
var bgm: BackgroundMusic
var session: WavePrototype
var starts: Array[StringName] = []

func _initialize() -> void:
	create_timer(35.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func phase(value: WavePrototype.Phase) -> void:
	session.phase = value
	session.phase_changed.emit(value)
	bgm.set_process(false)

func tick(seconds: float) -> void:
	bgm.set_process(false)
	bgm._process(seconds)
	bgm.set_process(false)

func wait_wall(seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline: await process_frame

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var exploration := load("res://data/audio/music/exploration_playlist.tres") as BgmPlaylist
	var combat := load("res://data/audio/music/combat_playlist.tres") as BgmPlaylist
	check(exploration.tracks[0].is_playable() and combat.tracks[0].is_playable(), "两首真实导入音源都可播放")
	check(exploration.tracks[0].stream is AudioStreamMP3 and combat.tracks[0].stream is AudioStreamOggVorbis, "曲目兼容现有 MP3 与 OGG")
	var third := exploration.tracks[0].duplicate() as BgmTrack
	third.track_id = &"third"
	var extra := BgmPlaylist.new()
	extra.context_id = &"boss"
	extra.tracks = [third]
	var pool := BgmPlaylist.new()
	pool.tracks = [null, exploration.tracks[0], combat.tracks[0], third, third, BgmTrack.new()]
	var random := RandomNumberGenerator.new()
	random.seed = 123
	check(pool.playable_tracks().size() == 3, "曲池忽略空条目、无效音源和重复标识")
	check(pool.next_track(null, random) == exploration.tracks[0] and pool.next_track(third, random) == exploration.tracks[0], "顺序曲池从第一曲开始并可绕回")
	check(pool.next_track(exploration.tracks[0], random) == combat.tracks[0], "新增曲目无需修改播放器即可参与轮播")
	pool.play_order = BgmPlaylist.Order.SHUFFLE
	var current := exploration.tracks[0]
	var no_repeat := true
	for index in 100:
		var next := pool.next_track(current, random)
		no_repeat = no_repeat and next != current
		current = next
	check(no_repeat, "随机曲池不连续重复同一曲")
	check(exploration.next_track(exploration.tracks[0], random) == exploration.tracks[0], "单曲曲池继续循环自身")
	session = SESSION.new()
	root.add_child(session)
	bgm = MUSIC.new()
	bgm.music_volume_db = 0.0
	bgm.session = session
	bgm.playlists = [exploration, combat, extra]
	bgm.track_started.connect(func(id): starts.append(id))
	root.add_child(bgm)
	await process_frame
	tick(3.0)
	check(bgm.get_playback_state().context == &"exploration" and bgm.get_playback_state().track == &"exploration", "准备阶段播放探索曲")
	check(bgm._players.size() == 2 and bgm._players[bgm._active].bus == &"Music", "固定两路播放器独立走 Music 总线")
	check(bgm._players[bgm._active].stream != exploration.tracks[0].stream and not bgm._players[bgm._active].stream.loop, "复制播放资源，不改写共享导入音源的循环设置")
	check(is_equal_approx(bgm._players[bgm._active].volume_db, -19.5), "探索曲使用与战斗曲响度对齐后的独立增益")
	phase(WavePrototype.Phase.BATTLE)
	check(bgm.get_playback_state().transitioning and bgm.get_playback_state().voices == 2 and bgm.get_playback_state().requested == &"garden_battle", "开战触发两曲交叉淡化")
	tick(1.25)
	check(is_equal_approx(bgm._gains[0] * bgm._gains[0] + bgm._gains[1] * bgm._gains[1], 1.0), "交叉淡化保持两路总功率")
	var before := bgm._gains.duplicate()
	var exploration_voice := bgm._players[0].stream
	phase(WavePrototype.Phase.RESULT)
	check(bgm._gains == before and bgm._players[0].stream == exploration_voice, "快速结算反向淡化保留增益与原曲播放实例")
	tick(2.6)
	check(bgm.get_playback_state().track == &"exploration" and bgm.get_playback_state().voices == 1, "结算回到探索曲并释放退出的播放实例")
	phase(WavePrototype.Phase.BATTLE)
	tick(2.6)
	check(bgm.get_playback_state().track == &"garden_battle" and is_equal_approx(bgm._players[bgm._active].volume_db, -15.0), "战斗曲保持原有音量")
	var count := starts.size()
	var battle_voice := bgm._players[bgm._active].stream
	phase(WavePrototype.Phase.REST)
	phase(WavePrototype.Phase.BATTLE)
	session.set_combat_frozen(true)
	check(starts.size() == count and bgm._players[bgm._active].stream == battle_voice and not bgm._players[bgm._active].stream_paused, "波间、续波与升级冻结均不重启或暂停音乐")
	session.set_combat_frozen(false)
	var position := bgm.get_playback_state().position as float
	paused = true
	await wait_wall(0.25)
	if DisplayServer.get_name() == "headless":
		check(bgm.process_mode == Node.PROCESS_MODE_ALWAYS and not bgm._players[bgm._active].stream_paused, "无声测试核对暂停时音乐保持播放资格；实际进度由原生音频测试验证")
	else:
		check(bgm.process_mode == Node.PROCESS_MODE_ALWAYS and bgm.get_playback_state().position > position + 0.08, "全局暂停仍保留真实音频播放进度")
	paused = false
	check(not bgm.play_context(&"missing") and bgm.get_playback_state().requested == &"garden_battle", "未知场合不打断现有音乐")
	phase(WavePrototype.Phase.RESULT)
	tick(0.2)
	check(bgm.play_context(&"boss") and bgm.get_playback_state().queued == &"third", "切换途中第三首进入待播请求，仍只占两路")
	check(bgm.play_context(&"combat") and bgm.get_playback_state().queued == &"", "快速重试以最新目标覆盖待播曲")
	tick(2.6)
	check(bgm.get_playback_state().track == &"garden_battle" and &"third" not in starts, "被替换的过期请求不会延迟播放")
	bgm.play_context(&"exploration")
	tick(0.2)
	bgm.play_context(&"boss")
	tick(0.3)
	tick(2.6)
	check(bgm.get_playback_state().track == &"third" and bgm.get_playback_state().voices == 1 and bgm._players.size() == 2, "新增场合完成排队衔接后回收旧曲且无播放器增长")
	var empty := BgmPlaylist.new()
	empty.context_id = &"empty"
	bgm.playlists.append(empty)
	check(not bgm.play_context(&"empty") and bgm.get_playback_state().track == &"third", "空曲池不造成静音")
	bgm.music_enabled = false
	tick(1.0)
	check(bgm._level > 0.0 and bgm._level < 1.0 and bgm.get_playback_state().voices > 0, "关闭音乐先淡出")
	bgm.play_context(&"combat")
	tick(3.1)
	check(bgm.get_playback_state().voices == 0 and bgm._tracks == [null, null] and bgm._players.all(func(voice): return voice.stream == null), "淡出结束释放两路解码实例")
	bgm.music_enabled = true
	tick(3.1)
	check(bgm.get_playback_state().track == &"garden_battle" and bgm.get_playback_state().voices == 1, "重新开启音乐播放最新目标而非旧请求")
	bgm.music_bus = &"missing_bus"
	tick(0.1)
	check(bgm._players[bgm._active].bus == &"Master", "缺失总线安全回退")
	bgm.free()
	session.free()
	bgm = MUSIC.new()
	bgm.follow_battle_session = false
	root.add_child(bgm)
	tick(3.1)
	check(bgm.get_playback_state().track == &"legacy" and bgm._players[bgm._active].stream is AudioStreamMP3, "旧预览场景仍使用原单曲播放方式")
	bgm.music_stream = null
	tick(3.1)
	check(bgm.get_playback_state().voices == 0, "清空旧单曲音源平滑停止")
	bgm.music_stream = exploration.tracks[0].stream
	tick(3.1)
	check(bgm.get_playback_state().voices == 1, "恢复同一个旧音源也能再次播放")
	bgm.music_stream = combat.tracks[0].stream
	bgm.music_stream = exploration.tracks[0].stream.duplicate()
	check(bgm._pending != null, "旧单曲连续换源仍共用同一套待播逻辑")
	bgm.music_stream = null
	tick(0.4)
	tick(3.1)
	check(bgm.get_playback_state().voices == 0 and bgm.get_playback_state().requested == &"", "清空音源后，正在淡化的旧待播请求不能重新启动音乐")
	bgm.free()
	await wait_wall(0.2)
	print("BGM framework: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
