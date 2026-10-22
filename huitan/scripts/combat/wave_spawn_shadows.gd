class_name WaveSpawnShadows
extends Node3D
## 整张地图共用一个网格、图集与材质；只更新时钟，出生／撤销时才改实例缓冲。
const SHADER := preload("res://shaders/combat/wave_spawn_shadow.gdshader")
const ATLAS := preload("res://scripts/combat/wave_spawn_shadow_atlas.gd")
var atlas := ATLAS.new()
var settings: WaveSpawnShadowSettings
var _mesh: MultiMeshInstance3D
var _material: ShaderMaterial
var _entries: Array[Dictionary] = []
var _slots: Dictionary[int, int] = {}
var _tails: Dictionary[int, float] = {}
var _clock := 0.0

func configure(value: WaveSpawnShadowSettings, scenes: Array[PackedScene], area: Rect2) -> void:
	settings = value
	if not settings or not settings.enabled: clear(); return
	var rebuilt := atlas.prepare(scenes)
	if not _mesh:
		top_level = true
		global_transform = Transform3D.IDENTITY
		physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_mesh = MultiMeshInstance3D.new()
		_mesh.name = "SpawnShadowBatch"
		_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_mesh.multimesh = MultiMesh.new()
		_mesh.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		_mesh.multimesh.use_colors = true
		_mesh.multimesh.use_custom_data = true
		_mesh.multimesh.mesh = QuadMesh.new()
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_mesh.material_override = _material
		add_child(_mesh)
		_grow(16)
	if rebuilt: _material.set_shader_parameter("mask_atlas", atlas.texture)
	for property in ["shadow_color", "rim_color", "shadow_opacity", "rim_opacity", "fade_seconds", "contraction"]:
		_material.set_shader_parameter(property, settings.get(property))
	_mesh.custom_aabb = AABB(Vector3(area.position.x, -4, area.position.y), Vector3(area.size.x, 12, area.size.y)).grow(3.0)
	# 重新打包图集后只更新仍活跃实例的 UV，不改变落点和预告时钟。
	if rebuilt:
		for index in _entries.size(): _write(index)
	set_process(false)
	set_physics_process(false)

func prepare_feedback(capacity: int) -> void:
	if _mesh and _mesh.multimesh.instance_count < capacity: _grow(capacity)

func begin(id: int, scene: PackedScene, point: Vector3, seconds: float, clock: float) -> void:
	if not _mesh or not atlas.records.has(scene): return
	if _slots.has(id): end(id, false)
	if _entries.size() == _mesh.multimesh.instance_count: _grow(maxi(16, _entries.size() * 2))
	var size: Vector2 = atlas.records[scene].size * settings.footprint_scale
	size.y *= settings.footprint_depth_ratio
	var basis := Basis(Vector3.RIGHT * size.x, Vector3.FORWARD * size.y, Vector3.UP)
	_slots[id] = _entries.size()
	_entries.append({"id":id, "scene":scene, "transform":Transform3D(basis, point + Vector3.UP * 0.026),
		"data":Color(clock, seconds, -1.0, 0.0), "expires":INF})
	_write(_entries.size() - 1)
	_mesh.multimesh.visible_instance_count = _entries.size()
	_material.set_shader_parameter("effect_clock", clock)
	_clock = clock
	show()

func end(id: int, spawned: bool) -> void:
	if not _slots.has(id): return
	var index := _slots[id]
	if spawned and settings and settings.fade_seconds > 0.0:
		var entry := _entries[index]
		entry.data.b = _clock
		entry.expires = _clock + settings.fade_seconds
		_tails[id] = entry.expires
		_mesh.multimesh.set_instance_custom_data(index, entry.data)
	else: _remove(index)

func advance(clock: float) -> void:
	_clock = clock
	if _entries.is_empty(): return
	# 仍在预告的实例由 shader 读同一时钟；CPU 只检查已出怪的短尾段。
	for id: int in _tails.keys():
		if _tails[id] <= clock: _remove(_slots[id])
	if not _entries.is_empty(): _material.set_shader_parameter("effect_clock", clock)

func clear() -> void:
	_entries.clear()
	_slots.clear()
	_tails.clear()
	_clock = 0.0
	if _mesh: _mesh.multimesh.visible_instance_count = 0
	hide()
	set_process(false)
	set_physics_process(false)

func _remove(index: int) -> void:
	_tails.erase(int(_entries[index].id))
	_slots.erase(int(_entries[index].id))
	var last := _entries.size() - 1
	if index != last:
		_entries[index] = _entries[last]
		_slots[int(_entries[index].id)] = index
		_write(index)
	_entries.pop_back()
	_mesh.multimesh.visible_instance_count = _entries.size()
	if _entries.is_empty(): hide()

func _grow(capacity: int) -> void:
	_mesh.multimesh.instance_count = capacity
	for index in _entries.size(): _write(index)
	_mesh.multimesh.visible_instance_count = _entries.size()

func _write(index: int) -> void:
	var entry := _entries[index]
	_mesh.multimesh.set_instance_transform(index, entry.transform)
	_mesh.multimesh.set_instance_custom_data(index, entry.data)
	_mesh.multimesh.set_instance_color(index, atlas.records[entry.scene].region)
