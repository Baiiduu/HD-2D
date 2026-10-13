class_name UIAudio
extends Node

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

var _voices: Array[AudioStreamPlayer] = []
var _cursor := 0
var _last_played: Dictionary[StringName, int] = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index in 6:
		var voice := AudioStreamPlayer.new()
		voice.name = "Voice%d" % index
		add_child(voice)
		_voices.append(voice)

func play(cue: StringName) -> bool:
	if not enabled or not sounds or _voices.is_empty(): return false
	var clip := sounds.get_clip(cue)
	if not clip: return false
	var now := Time.get_ticks_msec()
	if _last_played.has(cue) and now - _last_played[cue] < repeat_interval * 1000.0: return false
	_last_played[cue] = now
	var voice := _voices[_cursor]
	_cursor = (_cursor + 1) % _voices.size()
	voice.stop()
	voice.stream = clip
	voice.bus = audio_bus
	voice.volume_db = volume_db + sounds.gains_db.get(cue, 0.0)
	voice.play()
	cue_played.emit(cue)
	return true
