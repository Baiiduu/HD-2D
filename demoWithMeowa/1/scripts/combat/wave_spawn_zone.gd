@tool
class_name WaveSpawnZone
extends Marker3D

## 编辑器可配置的外围刷新区域；游戏中不增加可见道具。
signal settings_changed

@export var enabled := true:
	set(value): enabled = value; _changed()
## 留空使用节点名；WaveSpawnEntry 可用该标识限定进场方向。
@export var zone_id: StringName = &"":
	set(value): zone_id = value; _changed()
@export_range(0.8, 12.0, 0.4, "suffix:m") var radius := 3.2:
	set(value): radius = value; _changed()
## 相对其他区域的选择权重；设为 0 可停用。
@export_range(0.0, 10.0, 0.1) var weight := 1.0:
	set(value): weight = value; _changed()

func _ready() -> void:
	set_notify_transform(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED: _changed()

func _changed() -> void:
	if is_inside_tree(): settings_changed.emit()

func get_zone_id() -> StringName:
	return zone_id if zone_id != &"" else StringName(name)
