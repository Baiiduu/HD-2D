@tool
class_name PlazaProp
extends Node3D

const STATIC_BATCH = preload("res://scripts/rendering/static_geometry_batch.gd")

## 广场道具共用本地网格合批与贴地；生成物不写进场景文件。
const METAL_SHADER := preload("res://shaders/environment/plaza_metal.gdshader")
const STONE_SHADER := preload("res://shaders/environment/lumina_building.gdshader")
const GRAPHITE := preload("res://assets/meowa/buildings/plaza_landmarks/graphite.png")
const BRASS := preload("res://assets/meowa/buildings/plaza_landmarks/brass.png")
# 旧房屋石材保留；非房屋道具显式传入下面的独立材质。
const STONE := preload("res://assets/meowa/city_plaza/fixed/02-stone.png")
const MASONRY := preload("res://assets/meowa/buildings/materials/masonry.png")
const LIMESTONE := preload("res://assets/meowa/buildings/materials/limestone.png")
const COMPOST := preload("res://assets/meowa/buildings/materials/compost.png")
const LANTERN := preload("res://scenes/props/lantern.tscn")

@export_group("放置与碰撞")
@export var terrain: Terrain
@export var collision_enabled := true:
	set(value): collision_enabled = value; _queue_build()
@export_tool_button("贴合地面", "SnapToFloor") var snap_button: Callable = snap_to_ground

var _generated: Node3D
var _build_queued := false
var _streams: Dictionary = {}
var _materials: Dictionary = {}

func _enter_tree() -> void:
	_register_static_geometry.call_deferred()

func _register_static_geometry() -> void:
	if not is_inside_tree() or not is_instance_valid(_generated): return
	var batch: Node = STATIC_BATCH.for_owner(self)
	if batch: batch.register_owner(self, _generated)

func _ready() -> void:
	build()

func _queue_build() -> void:
	if not is_inside_tree() or _build_queued: return
	_build_queued = true
	build.call_deferred()

func build() -> void:
	_build_queued = false
	if not is_inside_tree(): return
	var batch: Node = STATIC_BATCH.for_owner(self)
	if batch: batch.request_rebuild()
	if is_instance_valid(_generated):
		remove_child(_generated)
		_generated.queue_free()
	_generated = Node3D.new()
	_generated.name = "Geometry"
	add_child(_generated)
	_streams.clear()
	_materials.clear()
	_build_geometry()
	for key: String in _streams:
		var mesh: ArrayMesh = (_streams[key] as SurfaceTool).commit()
		mesh.surface_set_material(0, _materials[key])
		var instance := MeshInstance3D.new()
		instance.name = key.capitalize()
		instance.mesh = mesh
		_generated.add_child(instance)
	if batch: batch.register_owner(self, _generated)

func _build_geometry() -> void:
	pass

func _metal(texture: Texture2D, roughness: float, tint := Color.WHITE, metallic := 0.65) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = METAL_SHADER
	material.set_shader_parameter("metal_texture", texture)
	material.set_shader_parameter("roughness", roughness)
	material.set_shader_parameter("metallic", metallic)
	material.set_shader_parameter("tint", tint)
	return material

func _stone(texture: Texture2D = STONE) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = STONE_SHADER
	material.set_shader_parameter("surface_texture", texture)
	material.set_shader_parameter("surface_roughness", 0.9)
	material.set_shader_parameter("lumina_relief_enabled", true)
	material.set_shader_parameter("lumina_relief_strength", 0.4)
	material.set_shader_parameter("relief_sample_pixels", 1.0)
	material.set_shader_parameter("relief_height", 0.003)
	material.set_shader_parameter("lumina_tone_strength", 0.025)
	return material

func _append(mesh: Mesh, key: String, center: Vector3, rotation := Vector3.ZERO,
		uv_span := Vector2.ONE, planar := false, rotate_side_uv := false) -> void:
	if not _streams.has(key):
		var stream := SurfaceTool.new()
		stream.begin(Mesh.PRIMITIVE_TRIANGLES)
		_streams[key] = stream
	var stream: SurfaceTool = _streams[key]
	var arrays: Array = (mesh as PrimitiveMesh).get_mesh_arrays() if mesh is PrimitiveMesh else mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var basis := Basis.from_euler(rotation)
	var meters := 1.6
	if key in ["stone", "cap"]:
		var texture: Texture2D = (_materials[key] as ShaderMaterial).get_shader_parameter("surface_texture")
		meters = texture.get_width() / 40.0
	for index in indices:
		var vertex := basis * vertices[index] + center
		var normal := basis * normals[index]
		var uv := uvs[index] * uv_span / meters
		if mesh is CylinderMesh and absf(normals[index].y) > 0.99:
			uv = Vector2(vertices[index].x, vertices[index].z) / meters
		elif rotate_side_uv:
			uv = Vector2(uv.y, uv.x)
		if planar:
			var axis := normal.abs().max_axis_index()
			uv = (Vector2(vertex.z, -vertex.y) if axis == 0 else Vector2(vertex.x, vertex.z) if axis == 1 else Vector2(vertex.x, -vertex.y)) / meters
		stream.set_normal(normal)
		stream.set_uv(uv)
		stream.add_vertex(vertex)

func _box(center: Vector3, size: Vector3, key: String, rotation := Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_append(mesh, key, center, rotation, Vector2.ONE, true)

func _cylinder(center: Vector3, bottom: float, top: float, height: float, key: String,
		segments := 24, rotation := Vector3.ZERO, rotate_side_uv := false) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = segments
	_append(mesh, key, center, rotation, Vector2(TAU * maxf(bottom, top), height), false, rotate_side_uv)

func _sphere(center: Vector3, radius: float, key: String, rotation := Vector3.ZERO) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 32
	mesh.rings = 16
	_append(mesh, key, center, rotation, Vector2(TAU * radius, PI * radius))

func _ring(center: Vector3, radius: float, thickness: float, key: String, rotation := Vector3.ZERO) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - thickness * 0.5
	mesh.outer_radius = radius + thickness * 0.5
	mesh.rings = 64
	mesh.ring_segments = 6
	_append(mesh, key, center, rotation, Vector2(TAU * radius, PI * thickness))

func _body(label: String) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = label
	body.collision_layer = 1
	body.collision_mask = 0
	# Generated bindings are immutable between build() calls, which remove the
	# old subtree. Direct native binding edits must revoke the obstacle raster first.
	body.set_meta(&"obstacle_layout_managed", true)
	_generated.add_child(body)
	return body

func _collider(body: StaticBody3D, shape: Shape3D, center: Vector3) -> void:
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = center
	body.add_child(collision)

func _lantern(label: String, lamp_center: Vector3, energy: float, color: Color, halo: float) -> Node3D:
	var lamp: Node3D = LANTERN.instantiate()
	lamp.name = label
	lamp.position = lamp_center - Vector3(0, 1.22, 0)
	lamp.set("light_color", color)
	lamp.set("direct_energy", energy)
	lamp.set("fill_energy", energy * 0.45)
	lamp.set("light_range", 6.0)
	lamp.set("water_energy", energy * 0.45)
	lamp.set("water_range", 6.0)
	lamp.set("tilt", 0.0)
	lamp.set("azimuth", 0.0)
	lamp.set("scattering", 2.0)
	lamp.set("mist_density", 0.0)
	lamp.set("ground_haze", 0.0)
	lamp.set("beam_strength", 0.0)
	lamp.set("halo_energy", halo)
	lamp.set("halo_diameter", 0.9)
	_generated.add_child(lamp)
	return lamp

func snap_to_ground() -> void:
	if not is_inside_tree(): return
	var ground := terrain
	var parent := get_parent()
	while not ground and parent:
		ground = parent.get_node_or_null("Homestead") as Terrain
		if not ground: ground = parent.get_node_or_null("Ground") as Terrain
		parent = parent.get_parent()
	if not ground or not ground.data: return
	var point := ground.to_local(global_position)
	var cell := ground.data.world_to_cell(point)
	if not ground.data.has_cell(cell): return
	var heights: PackedFloat32Array = ground._corner_heights(cell)
	var uv := (Vector2(point.x, point.z) / ground.data.cell_size - Vector2(cell) + Vector2(0.5, 0.5)).clamp(Vector2.ZERO, Vector2.ONE)
	var elevation := lerpf(lerpf(heights[0], heights[1], uv.x), lerpf(heights[3], heights[2], uv.x), uv.y)
	global_position.y = ground.to_global(Vector3(point.x, elevation, point.z)).y
	reset_physics_interpolation()
