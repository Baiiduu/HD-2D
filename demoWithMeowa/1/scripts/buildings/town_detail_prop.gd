@tool
class_name TownDetailProp
extends RicochetProp

## 城镇生活细节；复用弹射道具的贴地、材质合批与真实表面碰撞。
enum DetailKind { BENCH, FLOWER_CART, NOTICE_BOARD, FLOWER_POT, WATER_BASIN, LITTER_BIN, CARGO_PALLET, SACK_PILE }
const CLAY := preload("res://assets/meowa/buildings/town_details/terracotta.png")
const CLOTH_SHADER := preload("res://shaders/environment/town_burlap.gdshader")
const SOIL := preload("res://assets/meowa/buildings/materials/compost.png")
const PLANT_SHADER := preload("res://shaders/environment/vegetation_wind.gdshader")
const BASIN_SHADER := preload("res://shaders/environment/town_basin_water.gdshader")
const PLANTS := [preload("res://assets/meowa/dressing/flowers/flower_02.png"),
	preload("res://assets/meowa/dressing/flowers/flower_03.png"),
	preload("res://assets/meowa/dressing/flowers/flower_05.png"),
	preload("res://assets/meowa/dressing/forest/plant_01.png")]

@export_group("城镇细节物件")
@export_enum("独立长椅", "手推花车", "告示牌", "陶制花盆", "石质水钵", "街边垃圾桶", "货运托盘", "麻袋堆") var detail_kind := 0:
	set(value): detail_kind = clampi(value, 0, 7); _queue_build()
@export var flowers_enabled := true:
	set(value): flowers_enabled = value; _queue_build()
@export var clay_texture: Texture2D = CLAY:
	set(value): clay_texture = value; _queue_build()
## 原生颗粒底图；默认复用新陶土纹理，织纹由着色器按 40px/m 叠加。
@export var fabric_texture: Texture2D = CLAY:
	set(value): fabric_texture = value; _queue_build()

var _plants: Array[ShaderMaterial] = []
var _weather: Node
var _wind_settings: Array = []

func _validate_property(property: Dictionary) -> void:
	if property.name in ["kind", "layout_variant", "passage_width", "turn_angle_degrees"]:
		property.usage = PROPERTY_USAGE_NONE

func _ready() -> void:
	super()
	var parent := get_parent()
	while parent and not _weather:
		_weather = parent.get_node_or_null("MapEffects/Weather")
		parent = parent.get_parent()

func _build_geometry() -> void:
	_prepare_geometry()
	_plants.clear()
	_wind_settings.clear()
	for key in ["clay", "soil"]:
		var material := _stone(clay_texture if key == "clay" else SOIL)
		material.set_shader_parameter("surface_roughness", 0.92 if key == "clay" else 0.98)
		_materials[key] = material
	var fabric := ShaderMaterial.new()
	fabric.shader = CLOTH_SHADER
	fabric.set_shader_parameter("grain_texture", fabric_texture)
	_materials["fabric"] = fabric
	_materials["paper"] = _plain(Color(0.76, 0.68, 0.49))
	_materials["ink"] = _plain(Color(0.12, 0.17, 0.19))
	_materials["rope"] = _plain(Color(0.3, 0.22, 0.12))
	var water := ShaderMaterial.new()
	water.shader = BASIN_SHADER
	_materials["water"] = water
	match detail_kind:
		DetailKind.BENCH: _bench()
		DetailKind.FLOWER_CART: _flower_cart()
		DetailKind.NOTICE_BOARD: _notice_board()
		DetailKind.FLOWER_POT: _flower_pot()
		DetailKind.WATER_BASIN: _water_basin()
		DetailKind.LITTER_BIN: _litter_bin()
		DetailKind.CARGO_PALLET: _cargo_pallet()
		DetailKind.SACK_PILE: _sack_pile()
	set_process(not _plants.is_empty())

func _plain(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.95
	return material

func _bench() -> void:
	var w := dimensions.x
	var h := dimensions.y
	var d := dimensions.z
	for x: float in [-w * 0.35, w * 0.35]:
		for z: float in [-d * 0.32, d * 0.32]:
			_solid_box(Vector3(x, h * 0.22, z), Vector3(0.07, h * 0.44, 0.09), "metal", Vector3.ZERO, "BenchLeg")
		_solid_box(Vector3(x, h * 0.6, -d * 0.32), Vector3(0.065, h * 0.78, 0.065), "metal", Vector3.ZERO, "BackSupport")
	for index in 5:
		_solid_box(Vector3(0, h * 0.46, (index - 2) * d * 0.16), Vector3(w, 0.09, d * 0.135), "wood_frame", Vector3.ZERO, "SeatSlat")
	for index in 3:
		_solid_box(Vector3(0, h * (0.67 + index * 0.14), -d * 0.32), Vector3(w, h * 0.115, 0.085), "wood_frame", Vector3.ZERO, "BackSlat")
	for side: float in [-1.0, 1.0]:
		_solid_box(Vector3(side * w * 0.43, h * 0.65, 0), Vector3(0.06, 0.07, d * 0.8), "metal", Vector3.ZERO, "ArmRest")
		_solid_box(Vector3(side * w * 0.43, h * 0.56, d * 0.31), Vector3(0.06, h * 0.18, 0.06), "metal")

func _flower_cart() -> void:
	var w := dimensions.x
	var h := dimensions.y
	var d := dimensions.z
	_solid_box(Vector3(0, h * 0.5, 0), Vector3(w, 0.1, d), "wood_frame", Vector3.ZERO, "CartFloor")
	for side: float in [-1.0, 1.0]:
		_solid_box(Vector3(side * (w - 0.1) * 0.5, h * 0.64, 0), Vector3(0.1, h * 0.28, d), "wood", Vector3.ZERO, "CartSide")
		_solid_box(Vector3(0, h * 0.64, side * (d - 0.1) * 0.5), Vector3(w, h * 0.28, 0.1), "wood", Vector3.ZERO, "CartEnd")
		_solid_box(Vector3(side * w * 0.22, h * 0.52, d * 0.82), Vector3(0.055, 0.055, d * 0.68), "metal", Vector3.ZERO, "CartHandle")
		_solid_box(Vector3(side * w * 0.37, h * 0.25, -d * 0.34), Vector3(0.07, h * 0.5, 0.07), "metal", Vector3.ZERO, "CartStand")
		_wheel(Vector3(side * (w * 0.5 + 0.07), 0.34, d * 0.24), 0.34)
	_solid_box(Vector3(0, h * 0.52, d * 1.16), Vector3(w * 0.49, 0.065, 0.065), "wood_frame", Vector3.ZERO, "CartGrip")
	_box(Vector3(0, h * 0.59, 0), Vector3(w - 0.2, 0.08, d - 0.2), "soil")
	if flowers_enabled:
		for index in 6:
			_flower(Vector3((index % 3 - 1) * w * 0.29, h * 0.63, (0.5 if index >= 3 else -0.5) * d * 0.42), index % 4)

func _wheel(center: Vector3, radius: float) -> void:
	var rotation := Vector3(0, 0, PI * 0.5)
	_solid_ring(center, radius * 0.88, 0.08, "metal", rotation)
	_cylinder(center, 0.075, 0.075, 0.16, "brass", 16, rotation)
	var hub := CylinderShape3D.new()
	hub.radius = 0.075
	hub.height = 0.16
	_collide(hub, center, rotation, "WheelHub")
	for index in 8:
		_solid_box(center, Vector3(0.045, 0.045, radius * 1.72), "wood_frame", Vector3(index * PI / 8, 0, 0), "WheelSpoke")

func _notice_board() -> void:
	var w := dimensions.x
	var h := dimensions.y
	var d := dimensions.z
	for side: float in [-1.0, 1.0]:
		_solid_box(Vector3(side * w * 0.34, h * 0.41, 0), Vector3(0.12, h * 0.82, 0.13), "wood_frame", Vector3.ZERO, "NoticePost")
	_solid_box(Vector3(0, h * 0.65, 0), Vector3(w * 0.92, h * 0.52, 0.14), "wood", Vector3.ZERO, "NoticePanel")
	for side: float in [-1.0, 1.0]:
		_box(Vector3(side * w * 0.46, h * 0.65, 0.09), Vector3(0.1, h * 0.55, 0.07), "wood_frame")
		_box(Vector3(0, h * (0.65 + side * 0.26), 0.09), Vector3(w, 0.1, 0.07), "wood_frame")
		_solid_box(Vector3(side * w * 0.25, h * 0.94, 0), Vector3(w * 0.54, 0.08, d * 1.25), "wood_frame", Vector3(0, 0, side * -0.14), "NoticeRoof")
	for index in 3:
		var center := Vector3((index - 1) * w * 0.27, h * (0.64 + (index % 2) * 0.07), 0.101)
		_box(center, Vector3(w * 0.225, h * 0.29, 0.012), "paper", Vector3(0, 0, (index - 1) * 0.045))
		for line in 4:
			_box(center + Vector3(0, h * (0.055 - line * 0.035), 0.008), Vector3(w * (0.14 if line == 3 else 0.17), 0.012, 0.008), "ink")
		_cylinder(center + Vector3(w * 0.05, -h * 0.095, 0.012), 0.035, 0.035, 0.012, "brass", 12, Vector3(PI * 0.5, 0, 0))

func _flower_pot() -> void:
	var radius := minf(dimensions.x, dimensions.z) * 0.46
	var h := dimensions.y
	_solid_taper(Vector3(0, h * 0.38, 0), radius * 0.66, radius, h * 0.76, "clay")
	_solid_ring(Vector3(0, h * 0.77, 0), radius * 0.98, 0.085, "clay")
	_cylinder(Vector3(0, h * 0.72, 0), radius * 0.87, radius * 0.87, 0.025, "soil")
	if flowers_enabled:
		for index in 4:
			var angle := index * TAU / 4.0
			_flower(Vector3(sin(angle) * radius * 0.27, h * 0.73, cos(angle) * radius * 0.27), index)

func _water_basin() -> void:
	var radius := minf(dimensions.x, dimensions.z) * 0.46
	var h := dimensions.y
	_solid_taper(Vector3(0, h * 0.06, 0), radius * 0.7, radius * 0.7, h * 0.12, "stone", 16)
	_solid_taper(Vector3(0, h * 0.3, 0), radius * 0.34, radius * 0.26, h * 0.48, "cap", 16)
	_solid_taper(Vector3(0, h * 0.61, 0), radius * 0.27, radius * 0.88, h * 0.14, "cap", 24)
	_solid_taper(Vector3(0, h * 0.71, 0), radius * 0.88, radius * 0.95, h * 0.08, "cap", 24)
	_solid_ring(Vector3(0, h * 0.79, 0), radius * 0.92, h * 0.15, "cap")
	_cylinder(Vector3(0, h * 0.78, 0), radius * 0.83, radius * 0.83, 0.007, "water", 32)
	_solid_taper(Vector3(0, h * 0.86, 0), radius * 0.13, radius * 0.09, h * 0.3, "cap", 16)
	_ring(Vector3(0, h * 0.99, 0), radius * 0.095, 0.025, "brass")

func _litter_bin() -> void:
	var radius := minf(dimensions.x, dimensions.z) * 0.4
	var h := dimensions.y
	_solid_taper(Vector3(0, h * 0.08, 0), radius, radius, h * 0.16, "metal", 24)
	for index in 16:
		var angle := index * TAU / 16
		_solid_box(Vector3(sin(angle) * radius * 0.95, h * 0.52, cos(angle) * radius * 0.95), Vector3(0.065, h * 0.78, 0.055), "metal", Vector3(0, angle, 0), "BinSlat")
	_solid_ring(Vector3(0, h * 0.92, 0), radius * 0.96, 0.055, "brass")
	_solid_ring(Vector3(0, h * 0.29, 0), radius * 0.97, 0.035, "metal")
	_box(Vector3(0, h * 0.13, 0), Vector3(radius * 0.7, 0.025, radius * 0.9), "paper", Vector3(0, 0.25, 0))

func _cargo_pallet() -> void:
	var w := dimensions.x
	var h := dimensions.y
	var d := dimensions.z
	for index in 5:
		_solid_box(Vector3(0, 0.15, (index - 2) * d * 0.19), Vector3(w, 0.085, d * 0.155), "wood_frame", Vector3.ZERO, "PalletSlat")
	for side: float in [-1.0, 0.0, 1.0]:
		_solid_box(Vector3(side * w * 0.37, 0.06, 0), Vector3(0.12, 0.12, d * 0.85), "wood", Vector3.ZERO, "PalletRunner")
	var box := Vector3(w * 0.47, h * 0.7, d * 0.75)
	_crate(Vector3(-w * 0.2, 0.2 + box.y * 0.5, 0), box, -0.1)
	_sack(Vector3(w * 0.29, 0.2, 0), w * 0.32, h * 0.77)

func _sack_pile() -> void:
	var w := dimensions.x
	var h := dimensions.y
	var d := dimensions.z
	_sack(Vector3(-w * 0.23, 0, -d * 0.15), w * 0.45, h * 0.86)
	_sack(Vector3(w * 0.23, 0, -d * 0.08), w * 0.4, h * 0.7)
	_sack(Vector3(0, 0, d * 0.32), w * 0.35, h * 0.57)

func _sack(base: Vector3, width: float, height: float) -> void:
	# 平底和收肩让它读作布袋；网格与碰撞共同使用这一轮廓。
	var profile := [Vector2(0, 0.3), Vector2(0.09, 0.43), Vector2(0.36, 0.48), Vector2(0.65, 0.38), Vector2(0.83, 0.14)]
	var stream := SurfaceTool.new()
	stream.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row in profile.size() - 1:
		for sector in 24:
			for corner in [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 0), Vector2i(1, 1), Vector2i(1, 0)]:
				var level: Vector2 = profile[row + corner.y]
				var angle: float = (sector + corner.x) * TAU / 24
				var point := Vector3(sin(angle) * level.y * width - level.x * width * 0.07, level.x * height, cos(angle) * level.y * width * 0.87)
				stream.set_uv(Vector2((sector + corner.x) / 24.0 * PI * width, level.x * height))
				stream.add_vertex(point)
	for upper: bool in [false, true]:
		var level: Vector2 = profile[-1] if upper else profile[0]
		var center := Vector3(-level.x * width * 0.07, level.x * height, 0)
		for sector in 24:
			var first := sector + 1 if upper else sector
			var last := sector if upper else sector + 1
			for point_index in [-1, first, last]:
				var point := center
				if point_index >= 0:
					var angle: float = point_index * TAU / 24
					point += Vector3(sin(angle) * level.y * width, 0, cos(angle) * level.y * width * 0.87)
				stream.set_uv(Vector2(point.x, point.z))
				stream.add_vertex(point)
	stream.generate_normals()
	stream.index()
	var mesh := stream.commit()
	_append(mesh, "fabric", base)
	if _collision_body:
		var shape := ConvexPolygonShape3D.new()
		shape.points = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		_collide(shape, base, Vector3.ZERO, "SackBody")
	var neck := base + Vector3(-width * 0.058, height * 0.86, 0)
	_solid_taper(neck, width * 0.1, width * 0.17, height * 0.14, "fabric", 12)
	_ring(neck, width * 0.13, 0.025, "rope")
	_box(neck + Vector3(width * 0.12, -height * 0.035, width * 0.06), Vector3(width * 0.19, 0.025, 0.025), "rope", Vector3(0, -0.5, -0.3))

func _solid_taper(center: Vector3, bottom: float, top: float, height: float, key: String, segments := 24) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = segments
	_append(mesh, key, center, Vector3.ZERO, Vector2(TAU * maxf(bottom, top), height))
	if not _collision_body: return
	var shape := ConvexPolygonShape3D.new()
	shape.points = mesh.get_mesh_arrays()[Mesh.ARRAY_VERTEX]
	_collide(shape, center, Vector3.ZERO, key.capitalize() + "Body")

func _solid_ring(center: Vector3, radius: float, thickness: float, key: String, rotation := Vector3.ZERO) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - thickness * 0.5
	mesh.outer_radius = radius + thickness * 0.5
	mesh.rings = 32
	mesh.ring_segments = 8
	_append(mesh, key, center, rotation, Vector2(TAU * radius, PI * thickness))
	if _collision_body: _collide(mesh.create_trimesh_shape(), center, rotation, "HollowRim")

func _flower(base: Vector3, kind_index: int) -> void:
	while _plants.size() < PLANTS.size():
		var index := _plants.size()
		var material := ShaderMaterial.new()
		material.shader = PLANT_SHADER
		material.set_shader_parameter("sprite_texture", PLANTS[index])
		material.set_shader_parameter("root_uv", 27.0 / 32.0 if index == 3 else 44.0 / 48.0)
		material.set_shader_parameter("stable_shadows", true)
		material.set_shader_parameter("flexibility", 0.025)
		_plants.append(material)
	var mesh := QuadMesh.new()
	mesh.size = PLANTS[kind_index].get_size() * 0.025
	mesh.subdivide_width = 3
	mesh.subdivide_depth = 7
	mesh.material = _plants[kind_index]
	var card := MeshInstance3D.new()
	card.name = "Flower" + str(_generated.get_child_count())
	card.mesh = mesh
	card.position = base + Vector3(0, (27.0 - 16.0 if kind_index == 3 else 44.0 - 24.0) * 0.025, 0)
	card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	card.extra_cull_margin = 0.1
	_generated.add_child(card)

func _process(_delta: float) -> void:
	if _plants.is_empty(): return
	var state := [0.0, Vector2(1, 0.25), 1.6, 0.3]
	if is_instance_valid(_weather):
		state = [_weather.call("_effective_wind"), _weather.get("wind_direction"), _weather.get("wind_speed"), _weather.get("gust_strength")]
	if state != _wind_settings:
		_wind_settings = state
		for material in _plants:
			material.set_shader_parameter("wind_strength", state[0])
			material.set_shader_parameter("wind_direction", state[1].normalized())
			material.set_shader_parameter("wind_speed", state[2])
			material.set_shader_parameter("gust_strength", state[3])
	if state[0] <= 0.0 or not is_instance_valid(_weather): return
	for material in _plants: material.set_shader_parameter("wind_time", _weather.get("_clock"))
