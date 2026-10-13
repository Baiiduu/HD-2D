class_name WaveSpawnEntry
extends Resource

@export var enemy: WaveEnemyDefinition
@export_range(1, 200, 1) var count := 5
## 相对本波开始的首次生成时间，秒。
@export_range(0.0, 120.0, 0.1) var start_delay := 0.3
@export_range(0.1, 10.0, 0.1) var interval := 1.3
## 留空使用全部启用区域；填写 WaveSpawnZone 的 Zone Id 或节点名。
@export var spawn_zone_ids := PackedStringArray()
## -1 沿用控制器预告时间；每组可单独调整，0 表示立即激活。
@export_range(-1.0, 5.0, 0.1, "suffix:s") var warning_seconds := -1.0
