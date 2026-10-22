class_name UIAudio
extends Node

const BINDINGS = preload("res://scripts/audio/ui_audio_bindings.gd")
signal cue_played(cue: StringName)

@export var sounds: UISoundBank
@export var enabled := true:
	set(value):
		enabled = value
		if not value:
			for voice in _voices: voice.stop()
## UI 单独的总增益，dB；不改变背景音乐、雨声或风声。
@export_range(-40.0, 6.0, 0.5) var volume_db := -12.0
@export var audio_bus: StringName = &"UI"
## 相同声音的最短触发间隔，防止双击或同帧回调重复堆叠。
@export_range(0.0, 0.2, 0.01) var repeat_interval := 0.05
## 连续操作的独立限频，按真实时间计时，不改变控件数值更新。
@export var action_intervals: Dictionary[StringName, float] = {&"adjust": 0.12}

var _voices: Array[AudioStreamPlayer] = []
var _cursor := 0
var _last_played: Dictionary[StringName, int] = {}
var _mix_manager: GameAudio
var _bindings: Node
var _last_actions: Dictionary[StringName, int] = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index in 6:
		var voice := AudioStreamPlayer.new()
		voice.name = "Voice%d" % index
		add_child(voice)
		_voices.append(voice)

func play(cue: StringName) -> bool:
	if not sounds: return false
	var clip := sounds.get_clip(cue)
	return play_clip(cue, clip, sounds.gains_db.get(cue, 0.0))

## 新界面使用语义操作；原手帐及战斗提示仍可直接播放原 cue。
func play_action(action: StringName) -> bool:
	if not sounds or action.is_empty(): return false
	var cue: StringName = sounds.actions.get(action, &"")
	if cue.is_empty(): return false
	var now := Time.get_ticks_msec()
	if _last_actions.has(action) and now - _last_actions[action] < action_intervals.get(action, 0.0) * 1000.0: return false
	if not play(cue): return false
	_last_actions[action] = now
	return true

## 一次绑定页面，后续新增子控件自动加入；没有每帧扫描。
func bind_controls(scope: Node) -> void:
	if not _bindings:
		_bindings = BINDINGS.new()
		_bindings.name = "ControlBindings"
		_bindings.audio = self
		add_child(_bindings)
	_bindings.bind_tree(scope)

## 成长和波次提示复用同一短音效池；战斗冻结不暂停 UI 声音。
func play_clip(cue: StringName, clip: AudioStream, gain_db := 0.0, pitch := 1.0) -> bool:
	if not enabled or _voices.is_empty(): return false
	if not clip: return false
	_bind_mix()
	if is_instance_valid(_mix_manager) and _mix_manager.mix.is_clip_muted(clip): return false
	var now := Time.get_ticks_msec()
	if _last_played.has(cue) and now - _last_played[cue] < repeat_interval * 1000.0: return false
	_last_played[cue] = now
	var voice := _voices[_cursor]
	_cursor = (_cursor + 1) % _voices.size()
	voice.stop()
	voice.stream = clip
	voice.bus = audio_bus
	voice.set_meta(&"base_volume_db", volume_db + gain_db)
	voice.volume_db = volume_db + gain_db + (_mix_manager.mix.clip_gain_db(clip) if is_instance_valid(_mix_manager) else 0.0)
	voice.pitch_scale = pitch
	voice.play()
	cue_played.emit(cue)
	return true

func _bind_mix() -> void:
	if is_instance_valid(_mix_manager): return
	_mix_manager = get_tree().get_first_node_in_group(&"game_audio") as GameAudio
	if _mix_manager: _mix_manager.mix.changed.connect(_refresh_mix)

func _refresh_mix() -> void:
	if not is_instance_valid(_mix_manager): return
	for voice in _voices:
		if voice.playing:
			voice.volume_db = float(voice.get_meta(&"base_volume_db", volume_db)) + _mix_manager.mix.clip_gain_db(voice.stream)
