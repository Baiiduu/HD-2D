extends Node

const MODEL := preload("res://scripts/input/control_bindings.gd")
signal changed
var model := MODEL.new()
var save_enabled := true
var config_path := "user://controls.cfg"
var last_error := ""
var _baseline: Dictionary
var _world: Node
var _movement_keys: Array[int] = []
const KEY_FIELDS := {
	"VisualSample": {"style_key": &"cycle_style"},
	"MapEffects/Camera3D": {"follow_toggle_key": &"camera_follow"},
	"WavePrototype": {"interact_key": &"interact", "retry_key": &"retry"},
	"LoadoutUI": {"toggle_key": &"inventory"},
	"TrainingUI": {"interact_key": &"interact"},
}

func _ready() -> void:
	save_enabled = DisplayServer.get_name() != "headless"
	# Preserve the project's existing four combat-action defaults.
	for action in [&"blink", &"jump", &"normal_attack", &"body_charge"]:
		var events := InputMap.action_get_events(action)
		if events.size() != 1: continue
		var event := events[0]
		var code: int = (event.physical_keycode if event.physical_keycode else event.keycode) if event is InputEventKey else -event.button_index
		model.defaults[action] = [code]
	model.reset_defaults()
	_baseline = model.defaults.duplicate(true)
	if save_enabled:
		var error := model.load_from_path(config_path)
		if error not in [OK, ERR_FILE_NOT_FOUND]: last_error = "按键存档无效，当前使用默认按键。"
	_apply()

func configure_world(world: Node) -> void:
	if _world == world: return
	_world = world
	var defaults := _baseline.duplicate(true)
	for path in KEY_FIELDS:
		var node := world.get_node_or_null(NodePath(path))
		if not node: continue
		for property in KEY_FIELDS[path]: defaults[KEY_FIELDS[path][property]] = [int(node.get(property))]
	var error: String = model.use_defaults(defaults)
	if not error.is_empty(): last_error = error
	_apply()

func _apply() -> void:
	model.apply_input_map()
	_movement_keys = model.movement_keys()
	if is_instance_valid(_world):
		for path in KEY_FIELDS:
			var node := _world.get_node_or_null(NodePath(path))
			if not node: continue
			for property in KEY_FIELDS[path]: node.set(property, model.bindings[KEY_FIELDS[path][property]][0])
		var wave := _world.get_node_or_null("WavePrototype")
		if wave and wave.is_node_ready(): wave.changed.emit()
	changed.emit()

func rebind(action: StringName, slot: int, code: int) -> String:
	last_error = model.set_binding(action, slot, code)
	if not last_error.is_empty(): return last_error
	_apply()
	_save()
	return ""

func release_world(world: Node) -> void:
	if _world == world: _world = null

func reset_defaults() -> void:
	model.reset_defaults()
	last_error = ""
	_apply()
	_save()

func _save() -> void:
	if save_enabled and model.save_to_path(config_path) != OK: last_error = "按键已生效，但本次未能保存。"

func pressed(event: InputEvent, action: StringName) -> bool:
	return event.is_action_pressed(action, false, true) and not event.is_echo()

func movement_mask() -> int:
	var mask := 0
	for index in _movement_keys.size():
		if Input.is_physical_key_pressed(_movement_keys[index]): mask |= 1 << index
	return mask
