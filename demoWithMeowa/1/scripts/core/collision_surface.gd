@tool
extends RefCounted

## 碰撞部位的语义材质；与渲染材质、建筑类型及碰撞规则解耦。
## collision_surface 使用字符串，旧 movement_surface 六类整数继续兼容。
const META: StringName = &"collision_surface"
const MOVEMENT_SURFACES: Array[StringName] = [&"stone", &"cobble", &"grass", &"soil", &"wood", &"metal"]

static func mark(node: Node, surface: StringName) -> void:
	node.set_meta(META, surface)

## 接受原生碰撞或射线给出的 collider 和 shape index；不另查物理世界。
static func resolve(collider: Object, shape_index: int) -> StringName:
	if not is_instance_valid(collider) or not collider is Node: return &""
	if collider is CollisionObject3D and shape_index >= 0:
		var body := collider as CollisionObject3D
		var owner_id := body.shape_find_owner(shape_index)
		if owner_id in body.get_shape_owners():
			var surface := _read(body.shape_owner_get_owner(owner_id) as Node)
			if surface != &"": return surface
	var node := collider as Node
	while node:
		var surface := _read(node)
		if surface != &"": return surface
		node = node.get_parent()
	return &""

static func movement_index(surface: StringName) -> int:
	return MOVEMENT_SURFACES.find(surface)

static func _read(node: Node) -> StringName:
	if not node: return &""
	var value: Variant = node.get_meta(META, &"")
	if (value is String or value is StringName) and not String(value).strip_edges().is_empty():
		return StringName(String(value).strip_edges().to_lower())
	var legacy: Variant = node.get_meta(&"movement_surface", -1)
	if legacy is int and legacy >= 0 and legacy < MOVEMENT_SURFACES.size():
		return MOVEMENT_SURFACES[legacy]
	return &""
