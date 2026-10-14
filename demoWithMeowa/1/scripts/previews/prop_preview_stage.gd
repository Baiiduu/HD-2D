extends RefCounted

## Preview samples share the formal battle ground; hide its placed obstacles
## before _ready creates their collisions so samples can be inspected alone.
static func prepare(world: Node3D) -> void:
	var placed: Array[Node] = world.get_node("WorldDetails/BattleCourts").get_children()
	for child in world.get_children():
		if child is TreePlanter or child is PlazaProp: placed.append(child)
	for prop in placed:
		prop.visible = false
		prop.collision_enabled = false
		prop.process_mode = Node.PROCESS_MODE_DISABLED
