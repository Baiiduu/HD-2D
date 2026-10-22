extends Node
## 低频检测人物遮挡：房屋沿用分段碰撞，道具按各自显示表面检查。
const GROUP := &"occlusion_buildings"
const STATIC_BATCH = preload("res://scripts/rendering/static_geometry_batch.gd")
const CARD_SHADERS := ["res://shaders/environment/tree_billboard.gdshader", "res://shaders/environment/vegetation_wind.gdshader"]

@export_group("场景连接")
@export var camera: Camera3D
@export var player: Node3D
@export var building_root: Node3D
@export var world_entry: Node
@export var startup: Node
@export_group("人物遮挡淡化")
## 道具与导入模型按 building_root 收集；同地图的遮挡建筑分组独立登记。
@export var include_scene_props := false
@export var enabled := true:
	set(value):
		enabled = value
		if is_inside_tree():
			if not value: _restore_all()
			set_process(value)
## 淡化后保留的物件不透明度；碰撞、阴影和光源保持原有设置。
@export_range(0.05, 0.8, 0.05) var occluded_opacity := 0.25
@export_range(0.02, 0.3, 0.01, "suffix:s") var detection_interval := 0.05
@export_range(0.03, 0.5, 0.01, "suffix:s") var occlusion_fade_seconds := 0.12
@export_range(0.03, 0.8, 0.01, "suffix:s") var restore_seconds := 0.25
@export_range(0.0, 0.5, 0.01, "suffix:s") var restore_delay := 0.18

class Building extends RefCounted:
	var owner: Node3D
	var surfaces: Array[MeshInstance3D] = []
	var original: Array[float] = []
	var shapes: Array[CollisionShape3D] = []
	var volumes: Array[AABB] = []
	var inverses: Array[Transform3D] = []
	var cards: Array[MeshInstance3D] = []
	var visual_bounds := false
	var alpha_images: Dictionary[Texture2D, Image] = {}
	var batch: Node
	var _batch_excluded := false
	var bounds := AABB()
	var blocked := false
	var hold := 0.0
	var amount := 0.0
	var _last_opacity := -1.0
	var dirty := true
	var _watched: Array[Node] = []

	func _init(source: Node3D, use_visual_bounds := false) -> void:
		owner = source
		visual_bounds = use_visual_bounds
		batch = STATIC_BATCH.for_owner(source)

	func invalidate() -> void:
		dirty = true

	func _collect(node: Node) -> void:
		node.child_order_changed.connect(invalidate)
		_watched.append(node)
		if node is MeshInstance3D:
			surfaces.append(node)
			original.append(node.transparency)
		if node is CollisionShape3D and node.shape is BoxShape3D:
			shapes.append(node)
		for child in node.get_children(): _collect(child)

	func _restore_surfaces() -> void:
		for index in surfaces.size():
			var mesh := surfaces[index]
			if is_instance_valid(mesh) and not is_equal_approx(mesh.transparency, original[index]): mesh.transparency = original[index]

	func restore() -> void:
		_restore_surfaces()
		blocked = false
		hold = 0.0
		amount = 0.0
		_last_opacity = -1.0
		_update_batch(false)

	func _update_batch(excluded: bool) -> void:
		if _batch_excluded == excluded: return
		_batch_excluded = excluded
		if is_instance_valid(batch): batch.set_occluder_fading(owner, excluded)

	func release() -> void:
		restore()
		_clear_geometry()

	func _clear_geometry() -> void:
		for node in _watched:
			if is_instance_valid(node) and node.child_order_changed.is_connected(invalidate): node.child_order_changed.disconnect(invalidate)
		_watched.clear()
		surfaces.clear()
		original.clear()
		shapes.clear()

	func _append_volume(box: AABB, pose: Transform3D, card: MeshInstance3D = null) -> void:
		if is_zero_approx(pose.basis.determinant()): return
		var world_box: AABB = pose * box
		bounds = world_box if volumes.is_empty() else bounds.merge(world_box)
		volumes.append(box)
		inverses.append(pose.affine_inverse())
		cards.append(card)

	func _card_texture(mesh: MeshInstance3D) -> Texture2D:
		if not mesh.mesh is QuadMesh: return null
		var material := mesh.get_active_material(0) as ShaderMaterial
		if material == null or material.shader == null or material.shader.resource_path not in CARD_SHADERS: return null
		return material.get_shader_parameter("tree_texture" if material.shader.resource_path == CARD_SHADERS[0] else "sprite_texture") as Texture2D

	func refresh_bounds(view: Camera3D = null) -> void:
		if dirty:
			# 重建几何记录时保留淡化状态，不在同一轮反复归还合批。
			_restore_surfaces()
			_clear_geometry()
			_collect(owner)
			_last_opacity = -1.0
			dirty = false
		volumes.clear()
		inverses.clear()
		cards.clear()
		if visual_bounds:
			for mesh in surfaces:
				if not is_instance_valid(mesh) or mesh.mesh == null or not mesh.is_visible_in_tree(): continue
				var texture := _card_texture(mesh)
				var pose := mesh.global_transform
				if texture != null and is_instance_valid(view):
					var right := Vector3.UP.cross(view.global_basis.z).normalized()
					var forward := view.global_basis.x.cross(Vector3.UP).normalized()
					pose.basis = Basis(right * pose.basis.x.length(), Vector3.UP * pose.basis.y.length(), forward * pose.basis.z.length())
				_append_volume(mesh.get_aabb().grow(0.025), pose, mesh if texture != null else null)
		else:
			for shape in shapes:
				if not is_instance_valid(shape) or shape.disabled or not shape.shape is BoxShape3D: continue
				_append_volume(AABB(-shape.shape.size * 0.5, shape.shape.size).grow(0.025), shape.global_transform)
		# Inspector 在未淡化时调整实例透明度，作为新的原始值保留。
		if amount <= 0.0:
			for index in surfaces.size():
				if is_instance_valid(surfaces[index]): original[index] = surfaces[index].transparency

	func blocks(from: Vector3, points: PackedVector3Array) -> bool:
		if volumes.is_empty() or not owner.is_visible_in_tree(): return false
		for point in points:
			# 留出目标前的一小段，避免贴墙接触点本身触发淡化。
			var end := point.move_toward(from, 0.08)
			if bounds.intersects_segment(from, end) == null: continue
			for index in volumes.size():
				var start := inverses[index] * from
				var finish := inverses[index] * end
				if volumes[index].intersects_segment(start, finish) == null: continue
				if cards[index] != null and not _card_covers(cards[index], start, finish): continue
				return true
		return false

	func _card_covers(mesh: MeshInstance3D, from: Vector3, to: Vector3) -> bool:
		var texture := _card_texture(mesh)
		if texture == null: return false
		if not alpha_images.has(texture):
			var image := texture.get_image()
			if image == null: return true
			if image.is_compressed(): image.decompress()
			alpha_images[texture] = image
		var image := alpha_images[texture]
		var box := mesh.get_aabb()
		if is_zero_approx(to.z - from.z): return false
		var weight := (box.position.z - from.z) / (to.z - from.z)
		if weight < 0.0 or weight > 1.0: return false
		var hit := from.lerp(to, weight)
		var uv := Vector2((hit.x - box.position.x) / box.size.x, 1.0 - (hit.y - box.position.y) / box.size.y)
		if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0: return false
		return image.get_pixel(mini(int(uv.x * image.get_width()), image.get_width() - 1), mini(int(uv.y * image.get_height()), image.get_height() - 1)).a >= 0.5

	func advance(delta: float, opacity: float, fade: float, recovery: float, delay: float) -> void:
		if blocked: hold = delay
		else: hold = maxf(0.0, hold - delta)
		var target := 1.0 if blocked or hold > 0.0 else 0.0
		var next := move_toward(amount, target, delta / maxf(fade if target > amount else recovery, 0.001))
		if is_equal_approx(next, amount) and is_equal_approx(_last_opacity, opacity): return
		amount = next
		_last_opacity = opacity
		if amount > 0.0: _update_batch(true)
		for index in surfaces.size():
			var value := original[index] + (1.0 - original[index]) * (1.0 - opacity) * amount
			if is_instance_valid(surfaces[index]) and not is_equal_approx(surfaces[index].transparency, value): surfaces[index].transparency = value
		if amount <= 0.0: _update_batch(false)

var _buildings: Dictionary[int, Building] = {}
var _targets := PackedVector3Array()
var _poll_left := 0.0
var _registry_left := 0.0
var _suspended := false
var _alpha_images: Dictionary[Texture2D, Image] = {}

func _ready() -> void:
	set_process(enabled)

func refresh_buildings() -> void:
	var active := {}
	var scope: Node = building_root if is_instance_valid(building_root) else get_parent()
	var map_scope := get_parent()
	var grouped := get_tree().get_nodes_in_group(GROUP)
	var candidates: Array[Node] = []
	if include_scene_props:
		_collect_props(scope, candidates)
		# Editor-added building instances may sit beside WorldDetails under World.
		# Keep prop collection scoped, while explicit building membership spans this map.
		for node in grouped:
			if node != scope and not scope.is_ancestor_of(node): candidates.append(node)
	else:
		candidates = grouped
	for node in candidates:
		if not node is Node3D: continue
		var registration_scope: Node = map_scope if node.is_in_group(GROUP) else scope
		if node != registration_scope and not registration_scope.is_ancestor_of(node): continue
		var id: int = node.get_instance_id()
		active[id] = true
		if not _buildings.has(id):
			var record := Building.new(node, not node.is_in_group(GROUP))
			record.alpha_images = _alpha_images
			_buildings[id] = record
	for id in _buildings.keys():
		if not active.has(id):
			_buildings[id].release()
			_buildings.erase(id)

func _collect_props(node: Node, result: Array[Node]) -> void:
	for child in node.get_children():
		if child is Node3D and (child.is_in_group(GROUP) or child is PlazaProp or child is TreePlanter or child.is_in_group(&"ricochet_obstacles") or not child.scene_file_path.is_empty() or child is MeshInstance3D):
			result.append(child)
		else:
			_collect_props(child, result)

func _append_target(point: Vector3, height: float) -> void:
	var upper := point + Vector3.UP * height
	var middle := point + Vector3.UP * height * 0.5
	if not camera.is_position_in_frustum(upper) and not camera.is_position_in_frustum(middle): return
	_targets.append(upper)
	_targets.append(middle)
	if include_scene_props:
		_targets.append(point + Vector3.UP * 0.08)
		var side := camera.global_basis.x.normalized() * 0.15
		_targets.append(middle + side)
		_targets.append(middle - side)

func detect_occlusion() -> void:
	if not enabled or not is_instance_valid(camera):
		_restore_all()
		return
	if _buildings.is_empty(): return
	_targets.clear()
	if is_instance_valid(player) and player.is_visible_in_tree(): _append_target(player.global_position, 0.75)
	var origin := camera.global_position
	for record: Building in _buildings.values():
		if not is_instance_valid(record.owner): continue
		record.refresh_bounds(camera)
		record.blocked = record.blocks(origin, _targets)

func advance_fades(delta: float) -> void:
	for record: Building in _buildings.values():
		if is_instance_valid(record.owner): record.advance(delta, occluded_opacity, occlusion_fade_seconds, restore_seconds, restore_delay)

func _restore_all() -> void:
	for record: Building in _buildings.values(): record.restore()

func _process(delta: float) -> void:
	var hidden: bool = (is_instance_valid(world_entry) and world_entry.get("active")) or (is_instance_valid(startup) and (startup.get("menu") != null or startup.get("_cover") != null))
	if hidden:
		if not _suspended: _restore_all()
		_suspended = true
		_poll_left = 0.0
		return
	_suspended = false
	delta /= maxf(Engine.time_scale, 0.001)
	_registry_left -= delta
	if _registry_left <= 0.0:
		refresh_buildings()
		_registry_left = 0.5
	_poll_left -= delta
	if _poll_left <= 0.0:
		detect_occlusion()
		_poll_left = detection_interval
	advance_fades(delta)

func _exit_tree() -> void:
	for record: Building in _buildings.values(): record.release()
	_buildings.clear()
	_alpha_images.clear()
