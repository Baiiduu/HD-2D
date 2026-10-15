class_name AimPathData
extends RefCounted

## 世界坐标的只读预览结果；调用方每次预测前 clear，显示层不依赖人物或伤害系统。
var segments: Array[Dictionary] = []
var contacts := PackedVector3Array()
var crowd_contacts := PackedVector3Array()
var total_distance := 0.0
var total_seconds := 0.0
var end_reason: StringName = &""

func clear() -> void:
	segments.clear()
	contacts.clear()
	crowd_contacts.clear()
	total_distance = 0.0
	total_seconds = 0.0
	end_reason = &""

func append(start: Vector3, end: Vector3, heading: Vector3, seconds: float) -> void:
	var length := Vector2(end.x - start.x, end.z - start.z).length()
	if length <= 0.00001: return
	segments.append({"start": start, "end": end, "heading": heading, "seconds": seconds,
		"distance": total_distance, "time": total_seconds, "bounce": contacts.size()})
	total_distance += length
	total_seconds += seconds
