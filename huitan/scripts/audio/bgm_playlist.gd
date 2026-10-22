@tool
class_name BgmPlaylist
extends Resource

enum Order { SEQUENTIAL, SHUFFLE }

## 播放场合，例如 exploration、combat；后续可添加 boss 等自定义场合。
@export var context_id: StringName
@export var tracks: Array[BgmTrack] = []
## 顺序轮播，或随机选择且避免连续重复；单曲自动循环。
@export var play_order := Order.SEQUENTIAL

func playable_tracks() -> Array[BgmTrack]:
	var result: Array[BgmTrack] = []
	var ids := {}
	for track in tracks:
		if track and track.is_playable() and not ids.has(track.track_id):
			result.append(track)
			ids[track.track_id] = true
	return result

func next_track(current: BgmTrack, random: RandomNumberGenerator) -> BgmTrack:
	var available := playable_tracks()
	if available.is_empty(): return null
	var index := -1
	if current:
		for candidate in available.size():
			if available[candidate].track_id == current.track_id:
				index = candidate
				break
	if play_order == Order.SHUFFLE:
		if index >= 0 and available.size() > 1: available.remove_at(index)
		return available[random.randi_range(0, available.size() - 1)]
	return available[(index + 1) % available.size()]
