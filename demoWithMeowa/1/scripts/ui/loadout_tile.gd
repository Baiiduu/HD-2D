class_name LoadoutTile
extends Button

signal dropped(data: Dictionary)

var payload: Dictionary = {}
var drag_icon: Texture2D
var loadout: LoadoutState
var equipment_slot := -1
var skill_slot := -1
var quick_slot := -1
var audio: UIAudio
var _drag_started := false

func _get_drag_data(_position: Vector2) -> Variant:
	if payload.is_empty():
		return null
	var preview := TextureRect.new()
	preview.texture = drag_icon
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(80, 80)
	set_drag_preview(preview)
	_drag_started = true
	if audio: audio.play(&"drag_start")
	return payload.duplicate()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _drag_started:
		_drag_started = false
		if audio and not get_viewport().gui_is_drag_successful():
			var hovered: Node = get_viewport().gui_get_hovered_control()
			while hovered and not hovered is LoadoutTile: hovered = hovered.get_parent()
			var rejected_slot: bool = hovered is LoadoutTile and (hovered.equipment_slot >= 0 or hovered.skill_slot >= 0 or hovered.quick_slot >= 0)
			audio.play(&"error" if rejected_slot else &"cancel")

func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	if not loadout or not data is Dictionary or not data.get("id") is String:
		return false
	var id: String = data.id
	if quick_slot >= 0 and data.get("kind") in ["item", "equipment"]:
		return loadout.get_quantity(id) > 0
	if equipment_slot >= 0 and data.get("kind") == "equipment":
		var entry := loadout.catalog.get_equipment(id)
		return entry != null and entry.slot == equipment_slot and loadout.owns_equipment(id)
	return skill_slot >= 0 and data.get("kind") == "skill" and loadout.has_learned_skill(id)

func _drop_data(_position: Vector2, data: Variant) -> void:
	dropped.emit(data)
