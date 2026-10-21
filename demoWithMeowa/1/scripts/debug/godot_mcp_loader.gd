extends Node
## Development bridge: absent from exported games and headless logic tests.

func _ready() -> void:
	if not OS.has_feature("editor") or DisplayServer.get_name() == "headless":
		return
	var bridge_script: Script = load("res://scripts/debug/godot_mcp_project_bridge.gd")
	if bridge_script:
		var bridge: Node = bridge_script.new()
		bridge.name = "Bridge"
		add_child(bridge)
