class_name UISoundBank
extends Resource

const CUES := [&"journal_open", &"journal_close", &"page_turn", &"select", &"drag_start", &"item_drop", &"equip", &"confirm", &"cancel", &"error"]

@export var journal_open: AudioStream
@export var journal_close: AudioStream
@export var page_turn: AudioStream
@export var select: AudioStream
@export var drag_start: AudioStream
@export var item_drop: AudioStream
@export var equip: AudioStream
@export var confirm: AudioStream
@export var cancel: AudioStream
@export var error: AudioStream
## 各操作相对于 UI 总音量的增益，dB；负数降低音量。
@export var gains_db: Dictionary[StringName, float] = {&"select": -4.0, &"drag_start": -3.0, &"error": -2.0}
## 控件只描述操作，音源由这里分配；空字符串关闭对应反馈，也可添加自定义操作。
@export var actions: Dictionary[StringName, StringName] = {
	&"button": &"confirm", &"confirm": &"confirm", &"toggle": &"select",
	&"choice": &"select", &"tab": &"page_turn", &"adjust": &"select",
	&"open": &"journal_open", &"close": &"cancel", &"error": &"error", &"navigate": &"select",
}

func get_clip(cue: StringName) -> AudioStream:
	return get(cue) as AudioStream if cue in CUES else null
