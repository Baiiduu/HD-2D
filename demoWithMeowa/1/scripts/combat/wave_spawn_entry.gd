class_name WaveSpawnEntry
extends Resource

@export var enemy: WaveEnemyDefinition
## 填写目录标识时从 Enemy Catalog 解析；Enemy 可留空。二者同时设置时须指向同一资源。
@export var enemy_id: StringName
## 从怪物目录自动混编同批成员，忽略 Enemy／Enemy Id；权重为 0 的怪物不参与。
@export var mixed_horde := false
@export_range(1, 16384, 1) var count := 5
## 相对本波开始的首次生成时间，秒。
@export_range(0.0, 120.0, 0.1) var start_delay := 0.3
## 每批同时到期的数量；1 保留逐只出场，大于 1 时同批集中从一个外围区域进场。
@export_range(1, 128, 1) var batch_size := 1
## 两批之间的间隔；Batch Size 为 1 时就是原来的逐只间隔。
@export_range(0.1, 10.0, 0.1) var interval := 1.3
## 留空使用全部启用区域；填写 WaveSpawnZone 的 Zone Id 或节点名。
@export var spawn_zone_ids := PackedStringArray()
## -1 沿用控制器预告时间；每组可单独调整，0 表示立即激活。
@export_range(-1.0, 5.0, 0.1, "suffix:s") var warning_seconds := -1.0

func spawn_duration() -> float:
	return maxf(ceilf(float(count) / maxi(batch_size, 1)) - 1.0, 0.0) * interval
