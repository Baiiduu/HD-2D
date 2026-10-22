@tool
class_name BackgroundMusic
extends Node

## 场合选曲与双路等功率淡化。音乐独立于战斗冻结及管理界面。
signal context_changed(context_id: StringName)
signal track_started(track_id: StringName)

@export_group("背景音乐")
@export var music_enabled := true:
	set(value):
		music_enabled = value
		_wake()
## 不配置曲池的旧场景继续使用此单曲。
@export var music_stream: AudioStream = preload("res://assets/meowa/audio/bgm.mp3"):
	set(value):
		music_stream = value
		_configure()
## 所有曲目的统一增益，再叠加各曲目的独立增益。
@export_range(-40.0, 6.0, 0.5) var music_volume_db := -20.0
## 开关音乐时的淡入淡出时间。
@export_range(0.1, 10.0, 0.1, "suffix:s") var music_fade_time := 3.0
## 旧单曲场景的循环衔接时间；配置曲池后使用各曲目的设置。
@export_range(0.1, 15.0, 0.1, "suffix:s") var music_loop_crossfade := 6.0
@export var music_bus: StringName = &"Music"

@export_group("曲池与场合")
## 每个场合一份曲池；新增曲目直接加入对应曲池即可。
@export var playlists: Array[BgmPlaylist] = []
@export var default_context: StringName = &"exploration"
## 探索和战斗等不同场合之间的交叉淡化时间。
@export_range(0.1, 10.0, 0.1, "suffix:s") var music_transition_time := 2.5
@export var follow_battle_session := true
@export var session: WavePrototype
@export var exploration_context: StringName = &"exploration"
@export var combat_context: StringName = &"combat"

var _players: Array[AudioStreamPlayer] = []
var _tracks: Array[BgmTrack] = [null, null]
var _gains := PackedFloat32Array([1.0, 0.0])
var _blend_from := PackedFloat32Array([1.0, 0.0])
var _active := 0
var _destination := 0
var _level := 0.0
var _blending := false
var _blend_time := 0.0
var _blend_duration := 0.0
var _pending: BgmTrack
var _scheduled_next: BgmTrack
var _requested: BgmTrack
var _fallback: BgmTrack
var _playlist: BgmPlaylist
var _context: StringName
var _random := RandomNumberGenerator.new()

func _ready() -> void:
	if Engine.is_editor_hint():
		set_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_random.randomize()
	_configure()
	if not playlists.is_empty() and not play_context(default_context):
		push_warning("BGM 默认曲池为空或不存在：" + str(default_context))
	_bind_session.call_deferred()

func _exit_tree() -> void:
	if Engine.is_editor_hint(): return
	if is_instance_valid(session) and session.phase_changed.is_connected(_phase_changed):
		session.phase_changed.disconnect(_phase_changed)
	for player in _players: player.stop()

func _wake() -> void:
	if is_inside_tree() and not Engine.is_editor_hint(): set_process(true)

func _configure() -> void:
	if not is_inside_tree() or Engine.is_editor_hint(): return
	if _players.is_empty():
		for index in 2:
			var player := AudioStreamPlayer.new()
			player.name = "Music%d" % index
			player.volume_db = -80.0
			add_child(player)
			_players.append(player)
	if not playlists.is_empty(): return
	if not music_stream:
		_requested = null
		_pending = null
		_scheduled_next = null
		_wake()
		return
	if _fallback and _fallback.stream == music_stream:
		if not _requested: _request_track(_fallback)
		return
	_fallback = BgmTrack.new()
	_fallback.track_id = &"legacy"
	_fallback.stream = music_stream
	_fallback.loop_crossfade = music_loop_crossfade
	_playlist = null
	_request_track(_fallback)

func _bind_session() -> void:
	if not follow_battle_session or playlists.is_empty(): return
	if not session:
		var map := get_parent().get_parent() if get_parent() else null
		if map: session = map.get_node_or_null("WavePrototype") as WavePrototype
	if not is_instance_valid(session): return
	if not session.phase_changed.is_connected(_phase_changed): session.phase_changed.connect(_phase_changed)
	_phase_changed(session.phase)

func _phase_changed(phase: int) -> void:
	if not follow_battle_session: return
	match phase:
		WavePrototype.Phase.BATTLE, WavePrototype.Phase.REST: play_context(combat_context)
		WavePrototype.Phase.READY, WavePrototype.Phase.RESULT: play_context(exploration_context)

## 请求一个场合；重复请求保持当前进度，无有效候选时保留正在播放的音乐。
func play_context(context_id: StringName) -> bool:
	for playlist in playlists:
		if not playlist or playlist.context_id != context_id: continue
		if _context == context_id and _playlist == playlist and _requested: return true
		var track := playlist.next_track(null, _random)
		if not track: return false
		_playlist = playlist
		_context = context_id
		_scheduled_next = null
		_request_track(track)
		context_changed.emit(context_id)
		return true
	return false

func _same_track(first: BgmTrack, second: BgmTrack) -> bool:
	return first != null and second != null and first.track_id == second.track_id and first.stream == second.stream

func _request_track(track: BgmTrack, loop := false, duration := -1.0) -> void:
	if not track or not track.is_playable(): return
	_requested = track
	_scheduled_next = null
	_wake()
	if _players.is_empty() or (not music_enabled and _level <= 0.0001): return
	# 首帧真正开始淡入时再启动，避免场景同步载入期间静默跳过曲目前奏。
	if _level <= 0.0001 and not _players[_active].playing and not _blending: return
	if not loop:
		for index in 2:
			if not _players[index].playing or not _same_track(_tracks[index], track): continue
			_pending = null
			if (not _blending and index == _active) or (_blending and index == _destination): return
			# 快速重试返回仍在淡出的曲目时，沿用其真实播放进度。
			_start_blend(index, music_transition_time)
			return
	if not _players[_active].playing and not _blending:
		_start_track(_active, track)
		_gains[_active] = 1.0
		_gains[1 - _active] = 0.0
		return
	if _blending:
		if _same_track(_pending, track): return
		_pending = track
		# 两路都占用时先平滑收完当前衔接，再处理最新请求，不增加播放器。
		_start_blend(_destination, minf(0.25, _blend_duration - _blend_time))
		return
	var next := 1 - _active
	_start_track(next, track)
	_gains[next] = 0.0
	_start_blend(next, duration if duration > 0.0 else music_transition_time)

func _start_track(index: int, track: BgmTrack) -> void:
	var player := _players[index]
	player.stop()
	# 不修改共享导入资源；引擎自带循环关闭，由这里统一衔接。
	player.stream = track.stream.duplicate() as AudioStream
	if player.stream is AudioStreamMP3 or player.stream is AudioStreamOggVorbis:
		player.stream.loop = false
	elif player.stream is AudioStreamWAV:
		player.stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	_tracks[index] = track
	player.bus = music_bus if AudioServer.get_bus_index(music_bus) >= 0 else &"Master"
	player.volume_db = -80.0
	player.play()
	track_started.emit(track.track_id)

func _start_blend(destination: int, duration: float) -> void:
	_blend_from = _gains.duplicate()
	_destination = destination
	_blend_time = 0.0
	_blend_duration = maxf(duration, 0.01)
	_blending = true

func _next_track(current: BgmTrack) -> BgmTrack:
	if _playlist:
		var next := _playlist.next_track(current, _random)
		return next if next else current
	if _fallback: _fallback.loop_crossfade = music_loop_crossfade
	return _fallback

func _stop_players() -> void:
	for index in 2:
		_players[index].stop()
		_players[index].stream = null
		_tracks[index] = null
	_blending = false
	_pending = null
	_scheduled_next = null
	_active = 0
	_gains = PackedFloat32Array([1.0, 0.0])

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _players.is_empty(): return
	var target := 1.0 if music_enabled and _requested else 0.0
	_level = move_toward(_level, target, delta / maxf(music_fade_time, 0.1))
	if _level <= 0.0001:
		_stop_players()
		set_process(false)
		return
	if not _players[_active].playing and not _blending and _requested:
		var track := _next_track(_tracks[_active]) if _tracks[_active] else _requested
		if track:
			_requested = track
			_start_track(_active, track)
	if _blending:
		_blend_time += delta
		var phase := clampf(_blend_time / _blend_duration, 0.0, 1.0)
		for index in 2:
			# 从当前增益继续插值，反向或改目标不会重置音量；两路功率和保持不变。
			_gains[index] = sqrt(lerpf(_blend_from[index] * _blend_from[index], 1.0 if index == _destination else 0.0, phase))
		if phase >= 1.0:
			_active = _destination
			_players[1 - _active].stop()
			_players[1 - _active].stream = null
			_tracks[1 - _active] = null
			_blending = false
			var pending := _pending
			_pending = null
			if pending: _request_track(pending)
	else:
		var current := _tracks[_active]
		if current and _requested:
			var length := current.stream.get_length()
			var position := _players[_active].get_playback_position()
			if position >= length - minf(current.loop_crossfade, length * 0.25):
				if not _scheduled_next: _scheduled_next = _next_track(current)
				if _scheduled_next:
					var duration := minf(current.loop_crossfade, minf(length, _scheduled_next.stream.get_length()) * 0.25)
					if position >= length - duration: _request_track(_scheduled_next, true, duration)
	var bus := music_bus if AudioServer.get_bus_index(music_bus) >= 0 else &"Master"
	for index in 2:
		_players[index].bus = bus
		var gain_db := _tracks[index].volume_db if _tracks[index] else 0.0
		_players[index].volume_db = music_volume_db + gain_db + linear_to_db(maxf(_level * _gains[index], 0.0001))

func get_playback_state() -> Dictionary:
	var voices := 0
	for player in _players:
		if player.playing: voices += 1
	return {"context": _context, "track": _tracks[_active].track_id if _tracks[_active] else &"",
		"requested": _requested.track_id if _requested else &"", "transitioning": _blending,
		"queued": _pending.track_id if _pending else &"", "voices": voices, "level": _level,
		"position": _players[_active].get_playback_position() if not _players.is_empty() else 0.0}
