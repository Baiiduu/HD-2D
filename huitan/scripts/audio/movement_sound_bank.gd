class_name MovementSoundBank
extends Resource

## 同一材质可以放入多条音效，运行时随机选择并避免连续重复。
@export var grass: Array[AudioStream] = []
@export var cobble: Array[AudioStream] = []
@export var stone: Array[AudioStream] = []
@export var soil: Array[AudioStream] = []
@export var wood: Array[AudioStream] = []
@export var metal: Array[AudioStream] = []
@export var jump: Array[AudioStream] = []

func clips(surface: int) -> Array[AudioStream]:
	match surface:
		GroundAudioSampler.Surface.GRASS: return grass
		GroundAudioSampler.Surface.COBBLE: return cobble
		GroundAudioSampler.Surface.SOIL: return soil
		GroundAudioSampler.Surface.WOOD: return wood
		GroundAudioSampler.Surface.METAL: return metal
		_: return stone
