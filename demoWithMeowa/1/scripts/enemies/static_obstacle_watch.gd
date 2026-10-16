extends StaticBody3D

## Installed only on scriptless static bodies. Keep native physics behaviour.
var obstacle_field: WeakRef

func _init() -> void:
	set_notify_transform(true)
	set_notify_local_transform(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		if obstacle_field:
			var field = obstacle_field.get_ref()
			if field: field.make_dynamic(self)
