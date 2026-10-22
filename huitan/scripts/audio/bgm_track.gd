@tool
class_name BgmTrack
extends Resource

## 稳定标识；用于重复请求去重，不随文件名或显示名称变化。
@export var track_id: StringName
@export var track_title := ""
@export var stream: AudioStream
## 单曲增益，再叠加 BGM 节点与 Music 总线的音量。
@export_range(-40.0, 6.0, 0.5) var volume_db := 0.0
## 播放到结尾前多少秒开始接下一曲；只有一曲时接回自身。
@export_range(0.1, 15.0, 0.1, "suffix:s") var loop_crossfade := 6.0

func is_playable() -> bool:
	return track_id != &"" and stream != null and is_finite(stream.get_length()) and stream.get_length() > 0.0 and is_finite(volume_db) and is_finite(loop_crossfade) and loop_crossfade > 0.0
