@tool
class_name TreePlanter
extends Node3D

## 根节点底部为地面、+Z 为长椅正面。所有内容跟随本节点移动，不改动地图数据。
const TREE_SHADER := preload("res://shaders/environment/tree_billboard.gdshader")
const PLANT_SHADER := preload("res://shaders/environment/vegetation_wind.gdshader")
const SURFACE_SHADER := preload("res://shaders/environment/lumina_building.gdshader")
const LANTERN := preload("res://scenes/props/lantern.tscn")
const TREE := preload("res://assets/meowa/buildings/tree_planter/tree.png")
const STONE := preload("res://assets/meowa/buildings/materials/masonry.png")
const CAP := preload("res://assets/meowa/buildings/materials/limestone.png")
const WOOD := preload("res://assets/meowa/buildings/ricochet/wood.png")
const SOIL := preload("res://assets/meowa/buildings/materials/compost.png")
const PLANTS := [
	preload("res://assets/meowa/dressing/forest/plant_01.png"),
	preload("res://assets/meowa/dressing/forest/plant_04.png"),
	preload("res://assets/meowa/dressing/flowers/flower_02.png"),
	preload("res://assets/meowa/dressing/flowers/flower_03.png"),
	preload("res://assets/meowa/dressing/flowers/flower_05.png"),
]

@export_group("花坛尺寸")
@export_range(1.8, 6.0, 0.1, "suffix:m") var width := 3.2:
	set(value): width = value; _queue_build()
@export_range(1.4, 5.0, 0.1, "suffix:m") var depth := 2.4:
	set(value): depth = value; _queue_build()
@export_range(0.25, 0.8, 0.01, "suffix:m") var height := 0.42:
	set(value): height = value; _queue_build()
@export_range(0.08, 0.3, 0.01, "suffix:m") var rim_width := 0.16:
	set(value): rim_width = value; _queue_build()
@export var collision_enabled := true:
	set(value): collision_enabled = value; _queue_build()
## 未指定时自动寻找所在世界的 Homestead 或 Ground。贴地按钮只改变本建筑的 Y。
@export var terrain: Terrain
@export_tool_button("贴合地面", "SnapToFloor") var snap_button: Callable = snap_to_ground

@export_group("完整树图")
@export var tree_texture: Texture2D = TREE:
	set(value): tree_texture = value; _queue_build()
## 每个原生像素对应的米数；0.025 即 40 像素/米，不重采样图片。
@export_range(0.015, 0.04, 0.001, "suffix:m") var tree_pixel_size := 0.025:
	set(value): tree_pixel_size = value; _queue_build()
## 原生图片中的根部像素位置；替换树图时一并调整。
@export var tree_anchor := Vector2(64.0, 122.0):
	set(value): tree_anchor = value; _queue_build()
## X/Z 在泥土内的偏移；Y 为根部离开泥土的高度。
@export var tree_offset := Vector3(0.0, 0.0, -0.12):
	set(value): tree_offset = value; _queue_build()
@export_range(0.0, 0.1, 0.005, "suffix:m") var crown_sway := 0.045:
	set(value): crown_sway = value; _queue_build()
@export_range(0.0, 1.0, 0.05) var tree_normal_strength := 0.5:
	set(value): tree_normal_strength = value; _queue_build()

@export_group("花草与配件")
@export var flowers_enabled := true:
	set(value): flowers_enabled = value; _queue_build()
@export_range(0.6, 1.4, 0.05) var flower_scale := 1.0:
	set(value): flower_scale = value; _queue_build()
@export var bench_enabled := true:
	set(value): bench_enabled = value; _queue_build()
## 使用已有路灯与公共金色粒子。关闭只移除本花坛的路灯。
@export var lamp_enabled := true:
	set(value): lamp_enabled = value; _queue_build()

@export_group("花坛材质")
@export var stone_texture: Texture2D = STONE:
	set(value): stone_texture = value; _queue_build()
@export var cap_texture: Texture2D = CAP:
	set(value): cap_texture = value; _queue_build()
@export var wood_texture: Texture2D = WOOD:
	set(value): wood_texture = value; _queue_build()
## 64 像素贴图默认覆盖 1.6 米。
@export_range(0.8, 3.2, 0.05, "suffix:m") var texture_meters := 1.6:
	set(value): texture_meters = value; _queue_build()
@export_range(0.3, 1.0, 0.05) var stone_roughness := 0.9:
	set(value): stone_roughness = value; _queue_build()

var _generated: Node3D
var _build_queued := false
var _streams: Dictionary = {}
var _wind_materials: Array[ShaderMaterial] = []
var _weather: Node
var _wind_state: Array = []
var _wind_clock := 0.0

# Constant native plant textures are shared by every planter. Cache their alpha
# bounds until that texture changes, so each instance does not read back the GPU.
static var _plant_bounds_cache: Dictionary[Texture2D, Rect2i] = {}

static func _plant_bounds(texture: Texture2D) -> Rect2i:
	if not _plant_bounds_cache.has(texture):
		var image := texture.get_image()
		if image.is_compressed(): image.decompress()
		_plant_bounds_cache[texture] = image.get_used_rect()
		var invalidate := _invalidate_plant_bounds.bind(texture)
		if not texture.changed.is_connected(invalidate): texture.changed.connect(invalidate)
	return _plant_bounds_cache[texture]

static func _invalidate_plant_bounds(texture: Texture2D) -> void:
	_plant_bounds_cache.erase(texture)

func _ready() -> void:
	_resolve_weather()
	build()

func _queue_build() -> void:
	if not is_inside_tree() or _build_queued: return
	_build_queued = true
	build.call_deferred()

func build() -> void:
	_build_queued = false
	if not is_inside_tree(): return
	if get("cap_texture") == null: cap_texture = CAP
	if is_instance_valid(_generated):
		remove_child(_generated)
		_generated.queue_free()
	_generated = Node3D.new()
	_generated.name = "PlanterGeometry"
	add_child(_generated)
	# Generated children remain unowned; scene saves only the prefab and its parameters.
	_streams.clear()
	_wind_materials.clear()
	_wind_state.clear()
	var rim := clampf(rim_width, 0.08, minf(width, depth) * 0.2)
	var soil_y := height - 0.065
	_box(Vector3(0, height * 0.5, 0), Vector3(width, height, depth), "stone", true)
	_box(Vector3(0, height + 0.025, -(depth - rim) * 0.5), Vector3(width + 0.06, 0.09, rim + 0.06), "cap")
	_box(Vector3(0, height + 0.025, (depth - rim) * 0.5), Vector3(width + 0.06, 0.09, rim + 0.06), "cap")
	for side in [-1.0, 1.0]:
		_box(Vector3(side * (width - rim) * 0.5, height + 0.025, 0), Vector3(rim + 0.06, 0.09, depth - rim * 2.0), "cap")
		for end in [-1.0, 1.0]:
			_box(Vector3(side * (width - rim) * 0.5, height * 0.5, end * (depth - rim) * 0.5), Vector3(rim + 0.1, height + 0.12, rim + 0.1), "stone")
	# The body has an open top; soil sits below the rim rather than covering its edge.
	_quad([Vector3(-width * 0.5 + rim, soil_y, -depth * 0.5 + rim),
		Vector3(width * 0.5 - rim, soil_y, -depth * 0.5 + rim),
		Vector3(width * 0.5 - rim, soil_y, depth * 0.5 - rim),
		Vector3(-width * 0.5 + rim, soil_y, depth * 0.5 - rim)], "soil")
	if bench_enabled: _build_bench()
	for key: String in _streams:
		var mesh: ArrayMesh = (_streams[key] as SurfaceTool).commit()
		mesh.surface_set_material(0, _surface_material(key))
		var instance := MeshInstance3D.new()
		instance.name = key.capitalize()
		instance.mesh = mesh
		_generated.add_child(instance)
	if tree_texture:
		var material := ShaderMaterial.new()
		material.shader = TREE_SHADER
		material.set_shader_parameter("tree_texture", tree_texture)
		material.set_shader_parameter("root_uv", tree_anchor.y / tree_texture.get_height())
		material.set_shader_parameter("crown_sway", crown_sway)
		material.set_shader_parameter("normal_strength", tree_normal_strength)
		_wind_materials.append(material)
		_card("Tree", tree_texture, tree_anchor, tree_pixel_size, Vector3(0, soil_y, 0) + tree_offset, material, 15)
	if flowers_enabled: _build_flowers(soil_y, rim)
	if collision_enabled:
		var body := StaticBody3D.new()
		body.name = "PlanterCollision"
		body.collision_layer = 1
		body.collision_mask = 0
		_generated.add_child(body)
		_collision(body, Vector3(0, (height + 0.07) * 0.5, 0), Vector3(width + 0.06, height + 0.07, depth + 0.06))
		if bench_enabled:
			_collision(body, Vector3(-0.15, 0.27, depth * 0.5 + 0.28), Vector3(width * 0.7, 0.54, 0.55))
	if lamp_enabled:
		var lamp: Node3D = LANTERN.instantiate()
		lamp.name = "Lamp"
		lamp.position = Vector3(width * 0.5 - 0.18, height + 0.075, depth * 0.5 - 0.18)
		lamp.set("direct_energy", 2.0)
		lamp.set("fill_energy", 0.95)
		lamp.set("water_energy", 0.0)
		lamp.set("scattering", 2.0)
		lamp.set("mist_density", 0.015)
		lamp.set("ground_haze", 0.0)
		lamp.set("beam_strength", 0.0)
		lamp.set("halo_energy", 0.6)
		lamp.set("halo_diameter", 0.8)
		_generated.add_child(lamp)
	_sync_wind()
	set_process(not _wind_materials.is_empty())

func _build_bench() -> void:
	var bench_width := width * 0.7
	var front := depth * 0.5 + 0.28
	for row in 3:
		_box(Vector3(-0.15, 0.49, front + (row - 1) * 0.16), Vector3(bench_width, 0.07, 0.13), "wood")
	for side in [-1.0, 1.0]:
		_box(Vector3(-0.15 + side * bench_width * 0.38, 0.22, front), Vector3(0.16, 0.44, 0.4), "stone")

func _build_flowers(soil_y: float, rim: float) -> void:
	var materials: Array[ShaderMaterial] = []
	for index in PLANTS.size():
		var material := ShaderMaterial.new()
		material.shader = PLANT_SHADER
		material.set_shader_parameter("sprite_texture", PLANTS[index])
		material.set_shader_parameter("root_uv", 27.0 / 32.0 if index < 2 else 44.0 / 48.0)
		material.set_shader_parameter("stable_shadows", true)
		var bounds := _plant_bounds(PLANTS[index])
		material.set_shader_parameter("visible_height_uv", float(bounds.size.y) / PLANTS[index].get_height())
		material.set_shader_parameter("visible_width_uv", float(bounds.size.x) / PLANTS[index].get_width())
		material.set_shader_parameter("flexibility", 0.035)
		material.set_shader_parameter("root_occlusion", 0.2)
		materials.append(material)
		_wind_materials.append(material)
	var span := Vector2(width * 0.5 - rim - 0.2, depth * 0.5 - rim - 0.12)
	var placements := [Vector2(-0.76, -0.65), Vector2(0.62, -0.72), Vector2(-0.85, 0.15),
		Vector2(0.8, 0.05), Vector2(-0.58, 0.65), Vector2(-0.06, 0.78), Vector2(0.47, 0.68),
		Vector2(-0.22, -0.75), Vector2(0.92, -0.38), Vector2(-0.93, -0.38), Vector2(0.26, 0.22)]
	for index in placements.size():
		var kind := index % PLANTS.size()
		var root: Vector2 = placements[index] * span
		var anchor := Vector2(16, 27) if kind < 2 else Vector2(24, 44)
		_card("Plant%02d" % index, PLANTS[kind], anchor, 0.0234375 * flower_scale,
			Vector3(root.x, soil_y + 0.012, root.y), materials[kind], 7)

func _card(label: String, texture: Texture2D, anchor: Vector2, pixel_size: float,
		root: Vector3, material: ShaderMaterial, subdivisions: int) -> void:
	var canvas := texture.get_size()
	var mesh := QuadMesh.new()
	mesh.size = canvas * pixel_size
	mesh.center_offset.x = (canvas.x * 0.5 - anchor.x) * pixel_size
	mesh.subdivide_width = 3
	mesh.subdivide_depth = subdivisions
	mesh.material = material
	var card := MeshInstance3D.new()
	card.name = label
	card.mesh = mesh
	card.position = root + Vector3(0, (anchor.y - canvas.y * 0.5) * pixel_size, 0)
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	card.extra_cull_margin = 0.15
	_generated.add_child(card)

func _surface_material(key: String) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	var texture: Texture2D = wood_texture if key == "wood" else SOIL if key == "soil" else cap_texture if key == "cap" else stone_texture
	material.set_shader_parameter("surface_texture", texture)
	material.set_shader_parameter("surface_texture_linear", texture)
	material.set_shader_parameter("surface_roughness", stone_roughness if key in ["stone", "cap"] else 0.96)
	material.set_shader_parameter("lumina_relief_enabled", true)
	material.set_shader_parameter("lumina_relief_strength", 0.4)
	material.set_shader_parameter("relief_sample_pixels", 1.0)
	material.set_shader_parameter("relief_height", 0.004)
	material.set_shader_parameter("lumina_tone_strength", 0.025)
	return material

func _quad(points: Array[Vector3], key: String) -> void:
	if not _streams.has(key):
		var stream := SurfaceTool.new()
		stream.begin(Mesh.PRIMITIVE_TRIANGLES)
		_streams[key] = stream
	var stream: SurfaceTool = _streams[key]
	var normal := -(points[1] - points[0]).cross(points[2] - points[0]).normalized()
	var span := Vector2(points[0].distance_to(points[1]), points[0].distance_to(points[3])) / texture_meters
	var uvs := [Vector2.ZERO, Vector2(span.x, 0), span, Vector2(0, span.y)]
	for index in [0, 1, 2, 0, 2, 3]:
		stream.set_normal(normal)
		stream.set_uv(uvs[index])
		stream.add_vertex(points[index])

func _box(center: Vector3, size: Vector3, key: String, open_top := false) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(-h.x,h.y,-h.z),Vector3(h.x,h.y,-h.z),Vector3(h.x,h.y,h.z),Vector3(-h.x,h.y,h.z)],
		[Vector3(-h.x,-h.y,h.z),Vector3(h.x,-h.y,h.z),Vector3(h.x,-h.y,-h.z),Vector3(-h.x,-h.y,-h.z)],
		[Vector3(-h.x,h.y,h.z),Vector3(h.x,h.y,h.z),Vector3(h.x,-h.y,h.z),Vector3(-h.x,-h.y,h.z)],
		[Vector3(h.x,h.y,-h.z),Vector3(-h.x,h.y,-h.z),Vector3(-h.x,-h.y,-h.z),Vector3(h.x,-h.y,-h.z)],
		[Vector3(h.x,h.y,h.z),Vector3(h.x,h.y,-h.z),Vector3(h.x,-h.y,-h.z),Vector3(h.x,-h.y,h.z)],
		[Vector3(-h.x,h.y,-h.z),Vector3(-h.x,h.y,h.z),Vector3(-h.x,-h.y,h.z),Vector3(-h.x,-h.y,-h.z)]]
	for index in faces.size():
		# Do not close the planter's central top: its soil is recessed.
		if open_top and index == 0: continue
		var points: Array[Vector3] = []
		for corner: Vector3 in faces[index]: points.append(center + corner)
		_quad(points, key)

func _collision(body: StaticBody3D, center: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position = center
	body.add_child(collider)

func _resolve_weather() -> void:
	var parent := get_parent()
	while parent:
		_weather = parent.get_node_or_null("MapEffects/Weather")
		if _weather: return
		parent = parent.get_parent()

func _process(delta: float) -> void:
	_sync_wind()
	if _wind_state.is_empty() or _wind_state[0] <= 0.0: return
	_wind_clock += delta
	var clock: float = _weather.get("_clock") if is_instance_valid(_weather) else _wind_clock
	for material in _wind_materials:
		if material.shader == PLANT_SHADER:
			material.set_shader_parameter("wind_time", clock)

func _sync_wind() -> void:
	# Six cached materials and four values; no terrain or dressing scans while moving.
	var strength := 0.65
	var direction := Vector2(1.0, 0.25)
	var speed := 1.6
	var gust := 0.3
	if is_instance_valid(_weather):
		strength = _weather.call("_effective_wind")
		direction = _weather.get("wind_direction")
		speed = _weather.get("wind_speed")
		gust = _weather.get("gust_strength")
	var state := [strength, direction, speed, gust]
	if state == _wind_state: return
	_wind_state = state
	for material in _wind_materials:
		material.set_shader_parameter("wind_strength", strength)
		material.set_shader_parameter("wind_direction", direction.normalized())
		material.set_shader_parameter("wind_speed", speed)
		material.set_shader_parameter("gust_strength", gust)

func snap_to_ground() -> void:
	if not is_inside_tree(): return
	var ground := terrain
	var parent := get_parent()
	while not ground and parent:
		ground = parent.get_node_or_null("Homestead") as Terrain
		if not ground: ground = parent.get_node_or_null("Ground") as Terrain
		parent = parent.get_parent()
	if not ground or not ground.data: return
	var local_point := ground.to_local(global_position)
	var cell := ground.data.world_to_cell(local_point)
	if not ground.data.has_cell(cell): return
	var heights: PackedFloat32Array = ground._corner_heights(cell)
	var uv := (Vector2(local_point.x, local_point.z) / ground.data.cell_size - Vector2(cell) + Vector2(0.5, 0.5)).clamp(Vector2.ZERO, Vector2.ONE)
	var elevation := lerpf(lerpf(heights[0], heights[1], uv.x), lerpf(heights[3], heights[2], uv.x), uv.y)
	global_position.y = ground.to_global(Vector3(local_point.x, elevation, local_point.z)).y
	reset_physics_interpolation()
