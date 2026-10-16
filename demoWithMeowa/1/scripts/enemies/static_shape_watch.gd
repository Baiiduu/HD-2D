extends CollisionShape3D

var obstacle_field: WeakRef

func _init() -> void:
	set_notify_local_transform(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED and obstacle_field:
		var field = obstacle_field.get_ref()
		if field: field.make_dynamic(get_parent())
