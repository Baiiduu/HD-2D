class_name WaveDefinition
extends Resource

## 一波可包含多种怪物，各组独立配置数量与进场节奏。
@export var description := ""
@export var entries: Array[WaveSpawnEntry] = []
