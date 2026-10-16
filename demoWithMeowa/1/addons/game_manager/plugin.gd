@tool
extends EditorPlugin

const SYSTEM_PANEL = preload("res://addons/game_manager/panel.gd")
var _dock: EditorDock

func _enter_tree() -> void:
	_dock = EditorDock.new()
	_dock.title = "Game Manager"
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	_dock.available_layouts = EditorDock.DOCK_LAYOUT_VERTICAL | EditorDock.DOCK_LAYOUT_FLOATING
	_dock.add_child(SYSTEM_PANEL.new())
	add_dock(_dock)

func _exit_tree() -> void:
	remove_dock(_dock)
	_dock.queue_free()
