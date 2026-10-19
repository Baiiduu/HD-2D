extends Node
## 建筑级遮挡淡化：低频检测现有分段盒碰撞，复用模型与材质，不提交物理射线。
const GROUP := &"occlusion_buildings"

@export_group("场景连接")
@export var camera: Camera3D
@export var player: Node3D
@export var building_root: Node3D
@export var world_entry: Node
@export var startup: Node
@export_group("建筑遮挡淡化")
@export var enabled := true:
	set(value):
		enabled = value
		if is_inside_tree():
			if not value: _restore_all()
			set_process(value)
## 淡化后保留的建筑不透明度；碰撞、阴影和光源保持原有设置。
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
	var bounds := AABB()
	var blocked := false
	var hold := 0.0
	var amount := 0.0
	var _last_opacity := -1.0
	var dirty := true
	var _watched: Array[Node] = []

	func _init(source: Node3D) -> void:
		owner = source

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

	func restore() -> void:
		for index in surfaces.size():
			var mesh := surfaces[index]
			if is_instance_valid(mesh) and not is_equal_approx(mesh.transparency, original[index]): mesh.transparency = original[index]
		blocked = false
		hold = 0.0
		amount = 0.0
		_last_opacity = -1.0

	func release() -> void:
		restore()
		for node in _watched:
			if is_instance_valid(node) and node.child_order_changed.is_connected(invalidate): node.child_order_changed.disconnect(invalidate)
		_watched.clear()
		surfaces.clear()
		original.clear()
		shapes.clear()

	func refresh_bounds() -> void:
		if dirty:
			var previous := amount
			release()
			amount = previous
			_collect(owner)
			dirty = false
		volumes.clear()
		inverses.clear()
		for shape in shapes:
			if not is_instance_valid(shape) or shape.disabled or not shape.shape is BoxShape3D: continue
			var box := AABB(-shape.shape.size * 0.5, shape.shape.size).grow(0.025)
			var pose := shape.global_transform
			var world_box: AABB = pose * box
			bounds = world_box if volumes.is_empty() else bounds.merge(world_box)
			volumes.append(box)
			inverses.append(pose.affine_inverse())
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
				if volumes[index].intersects_segment(inverses[index] * from, inverses[index] * end) != null: return true
		return false

	func advance(delta: float, opacity: float, fade: float, recovery: float, delay: float) -> void:
		if blocked: hold = delay
		else: hold = maxf(0.0, hold - delta)
		var target := 1.0 if blocked or hold > 0.0 else 0.0
		var next := move_toward(amount, target, delta / maxf(fade if target > amount else recovery, 0.001))
		if is_equal_approx(next, amount) and is_equal_approx(_last_opacity, opacity): return
		amount = next
		_last_opacity = opacity
		for index in surfaces.size():
			var value := original[index] + (1.0 - original[index]) * (1.0 - opacity) * amount
			if is_instance_valid(surfaces[index]) and not is_equal_approx(surfaces[index].transparency, value): surfaces[index].transparency = value

var _buildings: Dictionary[int, Building] = {}
var _targets := PackedVector3Array()
var _poll_left := 0.0
var _registry_left := 0.0
var _suspended := false

func _ready() -> void:
	set_process(enabled)

func refresh_buildings() -> void:
	var active := {}
	var scope: Node = building_root if is_instance_valid(building_root) else get_parent()
	for node in get_tree().get_nodes_in_group(GROUP):
		if not node is Node3D or (node != scope and not scope.is_ancestor_of(node)): continue
		var id: int = node.get_instance_id()
		active[id] = true
		if not _buildings.has(id): _buildings[id] = Building.new(node)
	for id in _buildings.keys():
		if not active.has(id):
			_buildings[id].release()
			_buildings.erase(id)

func _append_target(point: Vector3, height: float) -> void:
	var upper := point + Vector3.UP * height
	var middle := point + Vector3.UP * height * 0.5
	if not camera.is_position_in_frustum(upper) and not camera.is_position_in_frustum(middle): return
	_targets.append(upper)
	_targets.append(middle)

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
		record.refresh_bounds()
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
