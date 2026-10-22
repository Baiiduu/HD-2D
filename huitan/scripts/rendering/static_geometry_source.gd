extends MeshInstance3D

var batch_owner: WeakRef

func _ready() -> void:
	set_notify_transform(true)

func _notification(what: int) -> void:
	if what not in [NOTIFICATION_TRANSFORM_CHANGED, NOTIFICATION_VISIBILITY_CHANGED, NOTIFICATION_EXIT_TREE]: return
	if not batch_owner: return
	var batch: Node = batch_owner.get_ref()
	if is_instance_valid(batch): batch.request_rebuild()
