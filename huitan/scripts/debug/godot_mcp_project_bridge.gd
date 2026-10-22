extends "res://addons/godot-mcp/runtime_bridge.gd"
## Match the project's physical keyboard bindings as well as logical UI keys.

func _cmd_input(params: Dictionary) -> Dictionary:
	var keycode := int(params.get("keycode", 0))
	var action: String = params.get("action", "press")
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = action != "release"
	Input.parse_input_event(event)
	return {"ok": true, "action": action}
