class_name GameAudio
extends Node3D

enum Kind { ATTACK, HIT, DEATH, DANGER, HURT }
const PRIORITIES := [40, 10, 5, 80, 100]
const BUSES := [&"Combat", &"Music", &"Ambience", &"UI", &"Movement"]

@export_group("声音连接")
@export var player: Node3D
@export var camera: Camera3D
@export var session: Node
@export_group("全局战斗音效")
@export var enabled := true:
	set(value):
		enabled = value
		if not value: stop_all()
## 整张地图所有攻击共用的播放池，不包含 BGM、天气、UI 与脚步。
@export_range(1, 64, 1) var max_voices := 12
## 为人物受伤、危险预告等高优先级声音预留，不被普通命中占满。
@export_range(0, 8, 1) var important_reserve := 2
@export_range(1, 16, 1) var per_cue_limit := 3
@export_range(0.0, 0.2, 0.005, "suffix:s") var minimum_interval := 0.035
@export_group("密集反馈合并")
## 不同武器在同一小片区域的普通命中／死亡共用合并窗口。
@export_range(0.0, 0.5, 0.01, "suffix:s") var merge_window := 0.08
@export_range(0.0, 10.0, 0.1, "suffix:m") var merge_radius := 2.5
@export_group("空间声音")
@export_range(0.0, 10.0, 0.1, "suffix:m") var near_distance := 3.0
@export_range(1.0, 80.0, 1.0, "suffix:m") var far_distance := 20.0
@export_range(0.5, 3.0, 0.1) var distance_falloff := 1.25
## 只衰减普通画面外声音，危险和受伤不受此项影响。
@export_range(0.0, 1.0, 0.05) var offscreen_gain := 0.45
@export_range(0.0, 1.0, 0.05) var panning_strength := 0.35
@export_range(0.0, 2.0, 0.05, "suffix:m") var listener_height := 0.75
@export_group("分组混音")
@export_range(-40.0, 6.0, 0.5) var combat_volume_db := 0.0
@export_range(-40.0, 6.0, 0.5) var music_volume_db := 0.0
@export_range(-40.0, 6.0, 0.5) var ambience_volume_db := 0.0
@export_range(-40.0, 6.0, 0.5) var ui_volume_db := 0.0
@export_range(-40.0, 6.0, 0.5) var movement_volume_db := 0.0
@export_group("本机声音调试")
@export var load_local_mix := true
@export var mix_save_path := "user://audio_mix.cfg"
@export_group("战斗峰值控制")
@export var compression_enabled := true
@export_range(-40.0, 0.0, 1.0) var compression_threshold_db := -16.0
@export_range(1.0, 8.0, 0.25) var compression_ratio := 2.0
@export var limiter_enabled := true
@export_range(-12.0, 0.0, 0.1) var limiter_ceiling_db := -1.0

var _voices: Array[Dictionary] = []
var _listener: AudioListener3D
var _clock := 0.0
var _frozen := false
var _recent: Array[Dictionary] = []
var _last_request: Dictionary = {}
var _last_clip: Dictionary = {}
var _mix_values: Array = []
var mix := AudioMixSettings.new()
var _stats := {"played": 0, "merged": 0, "budget_dropped": 0, "distance_dropped": 0, "preempted": 0}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"game_audio")
	if load_local_mix and FileAccess.file_exists(mix_save_path): mix.load_from_path(mix_save_path)
	mix.changed.connect(_apply_mix)
	var effects := get_parent()
	var map := effects.get_parent() if effects else null
	if not player and map: player = map.get_node_or_null("Player") as Node3D
	if not camera and effects:
		camera = effects.get_map_camera() if effects.has_method("get_map_camera") else effects.get_node_or_null("Camera3D")
	if not session and map: session = map.get_node_or_null("WavePrototype")
	if session:
		session.combat_frozen_changed.connect(set_frozen)
		session.phase_changed.connect(_on_phase_changed)
		_frozen = session.combat_frozen
	_listener = AudioListener3D.new()
	_listener.name = "PlayerListener"
	add_child(_listener)
	if player: _listener.make_current()
	_resize_pool()
	_apply_mix()
	_update_listener()

func _exit_tree() -> void:
	stop_all()
	if is_instance_valid(session):
		if session.combat_frozen_changed.is_connected(set_frozen): session.combat_frozen_changed.disconnect(set_frozen)
		if session.phase_changed.is_connected(_on_phase_changed): session.phase_changed.disconnect(_on_phase_changed)

func _resize_pool() -> void:
	var count := clampi(max_voices, 1, 64)
	while _voices.size() > count:
		var slot: Dictionary = _voices.pop_back()
		slot.voice.stop()
		slot.voice.queue_free()
	while _voices.size() < count:
		var voice := AudioStreamPlayer3D.new()
		voice.name = "CombatVoice%d" % _voices.size()
		voice.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
		voice.attenuation_filter_cutoff_hz = 20500.0
		voice.max_db = 6.0
		voice.bus = &"Combat"
		add_child(voice)
		var slot := {"voice": voice, "active": false}
		voice.finished.connect(_release.bind(slot))
		_voices.append(slot)

func _release(slot: Dictionary) -> void:
	slot.voice.stop()
	slot.active = false
	slot["source"] = null

func _process(delta: float) -> void:
	_resize_pool()
	_update_listener()
	_apply_mix()
	var paused := _frozen or get_tree().paused
	if not paused: _clock += delta
	_recent = _recent.filter(func(item): return _clock - item.time < merge_window)
	for key in _last_request.keys():
		if _clock - _last_request[key] > 1.0: _last_request.erase(key)
	for slot in _voices:
		if not slot.active: continue
		if not is_instance_valid(slot.source) or not slot.source.is_inside_tree():
			_release(slot)
			continue
		slot.voice.stream_paused = paused
		_update_spatial(slot)

func _update_listener() -> void:
	if not is_instance_valid(player) or not _listener: return
	_listener.global_position = player.global_position + Vector3.UP * listener_height
	if is_instance_valid(camera):
		var forward := -camera.global_basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.001: _listener.global_basis = Basis.looking_at(forward.normalized())

func _spatial_gain(position: Vector3, priority: int) -> float:
	if not is_instance_valid(player): return 1.0
	var offset := position - player.global_position
	offset.y = 0.0
	var distance := offset.length()
	var far := maxf(far_distance, near_distance + 0.1)
	var gain := pow(clampf((far - distance) / (far - near_distance), 0.0, 1.0), distance_falloff)
	# 人物近身反馈保持清楚，包括镜头跟随或切换时的短暂画面外位置。
	if priority < 70 and distance > near_distance and is_instance_valid(camera):
		var rect := camera.get_viewport().get_visible_rect()
		if camera.is_position_behind(position) or not rect.has_point(camera.unproject_position(position)):
			gain *= offscreen_gain
	return gain

func _update_spatial(slot: Dictionary, follow := true) -> void:
	if follow and slot.get("follow_source", false) and slot.source is Node3D:
		slot.position = slot.source.global_position
	var gain := _spatial_gain(slot.position, slot.priority)
	slot.voice.global_position = slot.position
	slot.voice.panning_strength = panning_strength
	slot.voice.volume_db = slot.gain_db + mix.clip_gain_db(slot.voice.stream) + linear_to_db(maxf(gain, 0.00001))
	slot["score"] = slot.priority * 1000.0 + slot.voice.volume_db

## 统一声音事件：source 为生命周期拥有者，position 为实际出声位置。
## kind 决定默认优先级；危险／受伤绕过普通密集合并，但仍受总上限限制。
func request(event: Dictionary) -> AudioStreamPlayer3D:
	if not enabled or _frozen or get_tree().paused: return null
	_resize_pool()
	_update_listener()
	var source := event.get("source") as Node
	var clips: Array = event.get("clips", [])
	var position: Vector3 = event.get("position", Vector3.ZERO)
	var cue: StringName = event.get("cue", &"")
	var kind: int = clampi(event.get("kind", Kind.ATTACK), Kind.ATTACK, Kind.HURT)
	var priority: int = clampi(event.get("priority", PRIORITIES[kind]), 0, 100)
	var gain_db: float = event.get("volume_db", -10.0)
	var pitch: float = event.get("pitch", 1.0)
	if not is_instance_valid(source) or not source.is_inside_tree() or clips.is_empty() or cue == &"": return null
	if not position.is_finite() or not is_finite(gain_db) or not is_finite(pitch) or pitch <= 0.0: return null
	var gain := _spatial_gain(position, priority)
	if gain <= 0.001:
		_stats.distance_dropped += 1
		return null
	var key := "%d:%s" % [source.get_instance_id(), cue]
	if priority < 70 and _clock - float(_last_request.get(key, -10.0)) < minimum_interval: return null
	if priority < 70 and kind in [Kind.HIT, Kind.DEATH]:
		for recent in _recent:
			var offset: Vector3 = position - recent.position
			offset.y = 0.0
			if recent.kind == kind and _clock - recent.time < merge_window and offset.length() <= merge_radius:
				_stats.merged += 1
				return null
	var active := 0
	var normal := 0
	var cue_count := 0
	var free: Dictionary = {}
	var worst: Dictionary = {}
	for slot in _voices:
		if not slot.active:
			if free.is_empty(): free = slot
			continue
		active += 1
		if slot.priority < 70: normal += 1
		if slot.cue == cue: cue_count += 1
		if slot.priority < 70 or priority >= 70:
			if worst.is_empty() or slot.score < worst.score: worst = slot
	var normal_limit := _voices.size() - clampi(important_reserve, 0, _voices.size() - 1)
	var full := active >= _voices.size() or (priority < 70 and normal >= normal_limit)
	if priority < 70 and cue_count >= per_cue_limit:
		_stats.budget_dropped += 1
		return null
	if full:
		var score := priority * 1000.0 + gain_db + linear_to_db(gain)
		if worst.is_empty() or score <= float(worst.score) + 0.1:
			_stats.budget_dropped += 1
			return null
		free = worst
	if free.is_empty(): return null
	var valid: Array = clips.filter(func(clip): return clip is AudioStream and not mix.is_clip_muted(clip))
	if valid.is_empty(): return null
	var index := randi_range(0, valid.size() - 1)
	if valid.size() > 1 and valid[index] == _last_clip.get(cue): index = (index + 1) % valid.size()
	if free.active:
		_release(free)
		_stats.preempted += 1
	free.merge({"active": true, "source": source, "cue": cue, "kind": kind, "priority": priority,
		"position": position, "gain_db": gain_db, "follow_source": event.get("follow_source", false)}, true)
	var voice: AudioStreamPlayer3D = free.voice
	voice.stream = valid[index]
	voice.pitch_scale = clampf(pitch, 0.25, 4.0)
	voice.stream_paused = false
	_update_spatial(free, false)
	voice.play()
	_last_clip[cue] = valid[index]
	_last_request[key] = _clock
	_recent.append({"kind": kind, "position": position, "time": _clock, "source_id": source.get_instance_id()})
	_stats.played += 1
	return voice

func stop_source(source: Node) -> void:
	for slot in _voices:
		if slot.active and slot.source == source: _release(slot)
	var id := source.get_instance_id()
	_recent = _recent.filter(func(item): return item.source_id != id)
	for key in _last_request.keys():
		if String(key).begins_with(str(id) + ":"): _last_request.erase(key)

## 只结束指定动作循环，不能停止同一来源的其它反馈或已被复用的声音。
func stop_cue(source: Node, cue: StringName) -> void:
	for slot in _voices:
		if slot.active and slot.source == source and slot.cue == cue: _release(slot)

## 更新持续动作的音量；按来源与事件定位，避免修改已被抢占复用的声道。
func set_cue_volume(source: Node, cue: StringName, volume_db: float) -> bool:
	if not is_finite(volume_db): return false
	for slot in _voices:
		if slot.active and slot.source == source and slot.cue == cue:
			slot.gain_db = volume_db
			_update_spatial(slot)
			return true
	return false

func stop_all() -> void:
	for slot in _voices: _release(slot)
	_recent.clear()
	_last_request.clear()

func set_frozen(value: bool) -> void:
	_frozen = value
	for slot in _voices:
		if slot.active: slot.voice.stream_paused = value or get_tree().paused

func _on_phase_changed(phase: int) -> void:
	# 正常休整允许短尾音完成；其余阶段切换清理旧事件。
	if phase != WavePrototype.Phase.REST: stop_all()

func get_debug_state() -> Dictionary:
	var result := _stats.duplicate()
	result["active"] = _voices.filter(func(slot): return slot.active).size()
	result["frozen"] = _frozen
	return result

func _apply_mix() -> void:
	var values: Array = [combat_volume_db, music_volume_db, ambience_volume_db, ui_volume_db, movement_volume_db,
		compression_enabled, compression_threshold_db, compression_ratio, limiter_enabled, limiter_ceiling_db]
	for index in BUSES.size(): values[index] += float(mix.bus_gains.get(String(BUSES[index]), 0.0))
	if values == _mix_values: return
	_mix_values = values
	for index in BUSES.size():
		var bus := AudioServer.get_bus_index(BUSES[index])
		if bus < 0:
			AudioServer.add_bus()
			bus = AudioServer.bus_count - 1
			AudioServer.set_bus_name(bus, BUSES[index])
			AudioServer.set_bus_send(bus, &"Master")
		AudioServer.set_bus_volume_db(bus, values[index])
	var combat := AudioServer.get_bus_index(&"Combat")
	if AudioServer.get_bus_effect_count(combat) == 0: AudioServer.add_bus_effect(combat, AudioEffectCompressor.new())
	var compressor := AudioServer.get_bus_effect(combat, 0) as AudioEffectCompressor
	if compressor:
		compressor.threshold = compression_threshold_db
		compressor.ratio = compression_ratio
		compressor.gain = 0.0
		compressor.attack_us = 3000.0
		compressor.release_ms = 120.0
		AudioServer.set_bus_effect_enabled(combat, 0, compression_enabled)
	if AudioServer.get_bus_effect_count(0) == 0: AudioServer.add_bus_effect(0, AudioEffectHardLimiter.new())
	var limiter := AudioServer.get_bus_effect(0, 0) as AudioEffectHardLimiter
	if limiter:
		limiter.ceiling_db = limiter_ceiling_db
		AudioServer.set_bus_effect_enabled(0, 0, limiter_enabled)
