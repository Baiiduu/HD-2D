extends Node3D

## 只接管生成器登记的不透明静态表面；原节点保留显示资格与反射入口。
const SOURCE_WATCH = preload("res://scripts/rendering/static_geometry_source.gd")
const SHADERS := ["res://shaders/environment/lumina_building.gdshader", "res://shaders/environment/plaza_metal.gdshader"]

@export var enabled := true:
	set(value):
		if enabled == value: return
		enabled = value
		request_rebuild()
@export_range(2.0, 16.0, 1.0, "suffix:m") var cell_size := 8.0:
	set(value):
		cell_size = maxf(value, 2.0)
		request_rebuild()

var _owners: Dictionary[int, Array] = {}
var _sources: Array[MeshInstance3D] = []
var _batches: Array[MeshInstance3D] = []
var _resources: Dictionary[Resource, bool] = {}
var _pending := false
var _building := false
var _closing := false
var _stats := {}
var _fading_occluders: Dictionary[int, WeakRef] = {}

func _enter_tree() -> void:
	_closing = false

## 生成器在重建前撤销旧提交，完成后登记直接生成的静态表面。
static func for_owner(owner: Node) -> Node:
	if Engine.is_editor_hint(): return null
	var parent := owner.get_parent()
	while parent:
		var controller := parent.get_node_or_null("StaticGeometryBatch")
		if controller and controller.get_script() == load("res://scripts/rendering/static_geometry_batch.gd"): return controller
		parent = parent.get_parent()
	return null

func register_owner(owner: Node3D, geometry: Node3D) -> void:
	var id := owner.get_instance_id()
	var exiting := _owner_exiting.bind(id)
	if not owner.tree_exiting.is_connected(exiting): owner.tree_exiting.connect(exiting)
	var surfaces: Array = []
	for child in geometry.get_children():
		if not child is MeshInstance3D: continue
		surfaces.append(child)
		if child.get_script() == null and child.mesh is ArrayMesh:
			child.set_script(SOURCE_WATCH)
		if child.get_script() == SOURCE_WATCH:
			child.set("batch_owner", weakref(self))
			child.set_notify_transform(true)
	_owners[id] = surfaces
	request_rebuild()

func _owner_exiting(id: int) -> void:
	_owners.erase(id)
	request_rebuild()

## 淡化开始／完全恢复时才撤销或归还合批，不在透明度逐帧变化时重建。
## 花坛包含的附灯也属于同一遮挡物，其余道具继续参与合批。
func set_occluder_fading(occluder: Node3D, fading: bool) -> void:
	if not is_instance_valid(occluder): return
	var id := occluder.get_instance_id()
	if _fading_occluders.has(id) == fading: return
	if fading: _fading_occluders[id] = weakref(occluder)
	else: _fading_occluders.erase(id)
	if enabled: request_rebuild()

func _owner_is_fading(id: int) -> bool:
	var owner := instance_from_id(id)
	for key in _fading_occluders.keys():
		var occluder: Node = _fading_occluders[key].get_ref()
		if occluder == null:
			_fading_occluders.erase(key)
		elif occluder == owner or occluder.is_ancestor_of(owner):
			return true
	return false

## 原生绑定或无 changed 信号的材质参数修改，必须在写入前调用。
## 变更立即恢复源显示；合批只在本轮变更完成后重新建立。
func request_rebuild() -> void:
	if _closing or _building or Engine.is_editor_hint(): return
	_restore_sources()
	for batch in _batches:
		if is_instance_valid(batch):
			batch.hide()
			batch.queue_free()
	_batches.clear()
	if not is_inside_tree() or _pending: return
	_pending = true
	_rebuild.call_deferred()

func _restore_sources() -> void:
	for source in _sources:
		if is_instance_valid(source) and source.is_inside_tree():
			RenderingServer.instance_set_visible(source.get_instance(), source.is_visible_in_tree())
	_sources.clear()

func _watch(resource: Resource) -> void:
	if _resources.has(resource): return
	_resources[resource] = true
	resource.changed.connect(request_rebuild)

func _unwatch() -> void:
	for resource in _resources:
		if resource.changed.is_connected(request_rebuild): resource.changed.disconnect(request_rebuild)
	_resources.clear()

func _material_key(material: ShaderMaterial) -> Array:
	var key: Array = [material.shader, material.render_priority]
	for uniform in material.shader.get_shader_uniform_list():
		if uniform.usage & PROPERTY_USAGE_GROUP: continue
		key.append(uniform.name)
		key.append(material.get_shader_parameter(uniform.name))
	return key

func _eligible(source: MeshInstance3D) -> bool:
	if not is_instance_valid(source) or not source.is_inside_tree() or not source.is_visible_in_tree(): return false
	if source.get_script() != null and source.get_script() != SOURCE_WATCH: return false
	if not source.mesh is ArrayMesh or source.mesh.get_surface_count() != 1 or source.mesh.get_blend_shape_count() > 0: return false
	if source.mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES: return false
	if source.material_override or source.material_overlay or source.get_surface_override_material(0): return false
	if source.skin or source.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_BONES or source.global_basis.determinant() <= 0.0: return false
	if source.transparency != 0.0 or source.custom_aabb != AABB() or not source.visibility_parent.is_empty(): return false
	if source.visibility_range_begin != 0.0 or source.visibility_range_end != 0.0: return false
	var material := source.mesh.surface_get_material(0) as ShaderMaterial
	return material != null and material.shader != null and material.shader.resource_path in SHADERS and material.next_pass == null

func _rebuild() -> void:
	_pending = false
	if _closing or not is_inside_tree(): return
	_building = true
	_unwatch()
	var start := Time.get_ticks_usec()
	var groups := {}
	if enabled:
		for id in _owners:
			if _owner_is_fading(id): continue
			var surfaces: Array = _owners[id]
			for candidate in surfaces:
				if not is_instance_valid(candidate): continue
				var source := candidate as MeshInstance3D
				if not _eligible(source): continue
				if source.get_script() == null:
					source.set_script(SOURCE_WATCH)
					source.set("batch_owner", weakref(self))
					source.set_notify_transform(true)
				var material := source.mesh.surface_get_material(0) as ShaderMaterial
				_watch(source.mesh)
				_watch(material)
				_watch(material.shader)
				var point := source.global_position
				var cell := Vector2i(floori(point.x / cell_size), floori(point.z / cell_size))
				var key: Array = [cell, _material_key(material), source.layers, source.cast_shadow, source.gi_mode, source.ignore_occlusion_culling, source.lod_bias, source.extra_cull_margin]
				if not groups.has(key): groups[key] = []
				groups[key].append(source)
	var vertex_count := 0
	for key in groups:
		var members: Array = groups[key]
		if members.size() < 2: continue
		var center := Vector3((key[0].x + 0.5) * cell_size, 0.0, (key[0].y + 0.5) * cell_size)
		var origin := Transform3D(Basis.IDENTITY, center)
		var stream := SurfaceTool.new()
		stream.begin(Mesh.PRIMITIVE_TRIANGLES)
		for source: MeshInstance3D in members:
			stream.append_from(source.mesh, 0, origin.affine_inverse() * source.global_transform)
			vertex_count += source.mesh.surface_get_array_len(0)
			_sources.append(source)
		var mesh := stream.commit()
		mesh.surface_set_material(0, members[0].mesh.surface_get_material(0))
		var batch := MeshInstance3D.new()
		batch.name = "StaticBlock%d" % _batches.size()
		batch.mesh = mesh
		batch.layers = key[2]
		batch.cast_shadow = key[3]
		batch.gi_mode = key[4]
		batch.ignore_occlusion_culling = key[5]
		batch.lod_bias = key[6]
		batch.extra_cull_margin = key[7]
		batch.add_to_group(&"static_geometry_batches")
		add_child(batch)
		batch.global_transform = origin
		_batches.append(batch)
	for source in _sources: RenderingServer.instance_set_visible(source.get_instance(), false)
	_stats = {"enabled":enabled, "owners":_owners.size(), "sources":_sources.size(), "batches":_batches.size(), "vertices":vertex_count, "build_ms":(Time.get_ticks_usec() - start) / 1000.0, "cell_size":cell_size}
	_building = false

func get_batch_stats() -> Dictionary:
	return _stats.duplicate()

func _exit_tree() -> void:
	_closing = true
	_restore_sources()
	_unwatch()
