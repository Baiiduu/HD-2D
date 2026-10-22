@tool
class_name ArmillaryMonument
extends PlazaProp

const PLANT_SHADER := preload("res://shaders/environment/vegetation_wind.gdshader")
const HALO_SHADER := preload("res://shaders/environment/halo.gdshader")
const SOIL := preload("res://assets/meowa/buildings/materials/compost.png")
const PLANTS := [preload("res://assets/meowa/dressing/flowers/flower_02.png"),
	preload("res://assets/meowa/dressing/flowers/flower_03.png"),
	preload("res://assets/meowa/dressing/flowers/flower_05.png"),
	preload("res://assets/meowa/dressing/forest/plant_01.png")]

@export_group("中心环球雕塑")
@export_range(0.65, 1.3, 0.05, "suffix:m") var globe_radius := 0.94:
	set(value): globe_radius = value; _queue_build()
@export_range(1.8, 3.3, 0.05, "suffix:m") var globe_center_height := 2.42:
	set(value): globe_center_height = value; _queue_build()
## 轨道相对球体的半径，轨道是真实金属环，可从任意水平角度观察。
@export_range(1.15, 1.7, 0.05) var orbit_ratio := 1.4:
	set(value): orbit_ratio = value; _queue_build()
@export_range(0.025, 0.07, 0.005, "suffix:m") var orbit_thickness := 0.04:
	set(value): orbit_thickness = value; _queue_build()
@export var globe_texture: Texture2D = GRAPHITE:
	set(value): globe_texture = value; _queue_build()
@export_range(0.2, 0.7, 0.05) var metal_roughness := 0.36:
	set(value): metal_roughness = value; _queue_build()

@export_group("基座与花圈")
@export_range(2.5, 4.0, 0.05, "suffix:m") var base_radius := 3.05:
	set(value): base_radius = value; _queue_build()
@export var flowers_enabled := true:
	set(value): flowers_enabled = value; _queue_build()
@export var stone_texture: Texture2D = MASONRY:
	set(value): stone_texture = value; _queue_build()
@export var cap_texture: Texture2D = LIMESTONE:
	set(value): cap_texture = value; _queue_build()
@export var garden_lights_enabled := true:
	set(value): garden_lights_enabled = value; _queue_build()
@export var glow_color := Color(1.0, 0.75, 0.42):
	set(value): glow_color = value; _queue_build()
## 只控制环上节点与铭牌的局部辉光；金属环主体仍接收真实灯光。
@export_range(0.0, 4.0, 0.1) var accent_emission := 2.2:
	set(value): accent_emission = value; _queue_build()

var _plants: Array[ShaderMaterial] = []
var _weather: Node
var _wind_strength := -1.0
var _wind_settings: Array = []
var _clock := 0.0

func _ready() -> void:
	var parent := get_parent()
	while parent:
		_weather = parent.get_node_or_null("MapEffects/Weather")
		if _weather: break
		parent = parent.get_parent()
	super()

func _build_geometry() -> void:
	if get("stone_texture") == null: stone_texture = MASONRY
	if get("cap_texture") == null: cap_texture = LIMESTONE
	_plants.clear()
	_wind_settings.clear()
	_materials["stone"] = _stone(stone_texture)
	_materials["cap"] = _stone(cap_texture)
	_materials["brass"] = _metal(BRASS, metal_roughness)
	_materials["metal"] = _metal(GRAPHITE, 0.5, Color.WHITE, 0.55)
	var globe := _metal(globe_texture, metal_roughness, Color(0.78, 0.93, 1.12), 0.55)
	globe.set_shader_parameter("globe_engraving", true)
	globe.set_shader_parameter("globe_uv_span", Vector2(TAU * globe_radius, PI * globe_radius) / 1.6)
	_materials["globe"] = globe
	var glow := StandardMaterial3D.new()
	glow.albedo_color = glow_color
	glow.emission_enabled = true
	glow.emission = glow_color
	glow.emission_energy_multiplier = accent_emission
	_materials["accents"] = glow
	var soil := _stone(SOIL)
	soil.set_shader_parameter("surface_roughness", 0.98)
	_materials["soil"] = soil
	_cylinder(Vector3(0, 0.08, 0), base_radius, base_radius, 0.16, "cap", 8, Vector3(0, PI / 8.0, 0))
	_cylinder(Vector3(0, 0.31, 0), base_radius - 0.15, base_radius - 0.15, 0.06, "soil", 8, Vector3(0, PI / 8.0, 0))
	var apothem := base_radius * cos(PI / 8.0)
	for index in 8:
		var angle := index * TAU / 8.0
		var direction := Vector3(sin(angle), 0, cos(angle))
		_box(direction * (apothem - 0.09) + Vector3(0, 0.3, 0), Vector3(base_radius * 2.0 * sin(PI / 8.0) + 0.015, 0.28, 0.18), "stone", Vector3(0, angle, 0))
		_box(direction * (apothem - 0.09) + Vector3(0, 0.455, 0), Vector3(base_radius * 2.0 * sin(PI / 8.0), 0.035, 0.21), "brass", Vector3(0, angle, 0))
	_cylinder(Vector3(0, 0.405, 0), 1.14, 1.14, 0.15, "cap")
	_cylinder(Vector3(0, 0.545, 0), 1.04, 1.04, 0.13, "cap")
	_cylinder(Vector3(0, 0.65, 0), 0.92, 0.92, 0.08, "brass")
	_cylinder(Vector3(0, 0.85, 0), 0.85, 0.72, 0.32, "cap")
	_cylinder(Vector3(0, 1.035, 0), 0.78, 0.78, 0.05, "brass")
	_cylinder(Vector3(0, 1.24, 0), 0.36, 0.3, 0.35, "metal")
	_cylinder(Vector3(0, 1.45, 0), 0.43, 0.43, 0.07, "brass")
	var center := Vector3(0, globe_center_height, 0)
	_sphere(center, globe_radius, "globe", Vector3(0, 0.25, 0.22))
	var orbit_radius := globe_radius * orbit_ratio
	var orbits := [Vector3(68, 0, 24), Vector3(22, 20, -60), Vector3(75, 67, 0), Vector3(-18, 0, -15)]
	var radius_factors := [1.0, 1.08, 1.03, 0.96]
	for index in orbits.size():
		var angles: Vector3 = orbits[index] * PI / 180.0
		var radius: float = orbit_radius * radius_factors[index]
		_ring(center, radius, orbit_thickness, "brass", angles)
		var phase := 0.55 + index * 1.65
		var node_position := center + Basis.from_euler(angles) * Vector3(cos(phase) * radius, 0, sin(phase) * radius)
		_sphere(node_position, orbit_thickness * 1.65, "accents")
		_add_glow(node_position)
	var axis := Vector3(0.2, 0, -0.25)
	_cylinder(center, 0.035, 0.035, globe_radius * 2.4, "brass", 8, axis)
	for side in [-1.0, 1.0]:
		_sphere(center + Basis.from_euler(axis) * Vector3(0, side * globe_radius * 1.2, 0), 0.075, "brass")
	# Blank inset plaque and a restrained warm edge; no invented title or UI text.
	_box(Vector3(0, 0.31, apothem + 0.035), Vector3(1.18, 0.245, 0.06), "brass")
	_box(Vector3(0, 0.31, apothem + 0.072), Vector3(1.02, 0.15, 0.025), "metal")
	_box(Vector3(0, 0.39, apothem + 0.077), Vector3(1.02, 0.012, 0.025), "accents")
	if flowers_enabled: _build_flowers()
	if garden_lights_enabled:
		for side in [-1.0, 1.0]:
			var lamp := _lantern("GardenLeft" if side < 0 else "GardenRight", Vector3(side * base_radius * 0.57, 1.13, apothem * 0.62), 0.85, glow_color, 0.45)
			var post := BoxMesh.new()
			post.size = Vector3(0.09, 0.7, 0.09)
			post.material = (lamp.get_node("Post") as MeshInstance3D).mesh.surface_get_material(0)
			lamp.get_node("Post").mesh = post
			lamp.get_node("Post").position.y = 0.87
	if collision_enabled:
		var body := _body("MonumentCollision")
		var polygon := ConvexPolygonShape3D.new()
		var points := PackedVector3Array()
		for index in 8:
			var angle := index * TAU / 8.0 + PI / 8.0
			for y in [0.0, 0.48]:
				points.append(Vector3(sin(angle) * base_radius, y, cos(angle) * base_radius))
		polygon.points = points
		_collider(body, polygon, Vector3.ZERO)
		var pedestal := CylinderShape3D.new()
		pedestal.radius = 1.12
		pedestal.height = globe_center_height + globe_radius
		_collider(body, pedestal, Vector3(0, pedestal.height * 0.5, 0))
	set_process(not _plants.is_empty())

func _add_glow(point: Vector3) -> void:
	var material := ShaderMaterial.new()
	material.shader = HALO_SHADER
	material.set_shader_parameter("energy", accent_emission * 0.08)
	material.set_shader_parameter("street_style", true)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.42, 0.42)
	mesh.material = material
	var glow := MeshInstance3D.new()
	glow.mesh = mesh
	glow.position = point
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow.set_instance_shader_parameter("halo_color", glow_color)
	_generated.add_child(glow)

func _build_flowers() -> void:
	for index in PLANTS.size():
		var material := ShaderMaterial.new()
		material.shader = PLANT_SHADER
		material.set_shader_parameter("sprite_texture", PLANTS[index])
		material.set_shader_parameter("root_uv", 27.0 / 32.0 if index == 3 else 44.0 / 48.0)
		material.set_shader_parameter("stable_shadows", false)
		material.set_shader_parameter("flexibility", 0.035)
		material.set_shader_parameter("wind_strength", 0.0)
		_plants.append(material)
	for index in 24:
		var angle := index * TAU / 24.0 + 0.12
		var radius := base_radius * (0.68 if index % 3 else 0.78)
		var kind := index % PLANTS.size()
		var mesh := QuadMesh.new()
		var pixel_size := 0.0234375
		mesh.size = PLANTS[kind].get_size() * pixel_size
		mesh.subdivide_width = 3
		mesh.subdivide_depth = 7
		mesh.material = _plants[kind]
		var root_y := (27.0 - 16.0) * pixel_size if kind == 3 else (44.0 - 24.0) * pixel_size
		var card := MeshInstance3D.new()
		card.name = "Flower%02d" % index
		card.mesh = mesh
		card.position = Vector3(sin(angle) * radius, 0.345 + root_y, cos(angle) * radius)
		card.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		card.extra_cull_margin = 0.1
		_generated.add_child(card)

func _process(delta: float) -> void:
	var strength := 0.65
	var direction := Vector2(1, 0.25)
	var speed := 1.6
	var gust := 0.3
	if is_instance_valid(_weather):
		strength = _weather.call("_effective_wind")
		direction = _weather.get("wind_direction")
		speed = _weather.get("wind_speed")
		gust = _weather.get("gust_strength")
	var state := [strength, direction, speed, gust]
	if state != _wind_settings:
		_wind_settings = state
		_wind_strength = strength
		for material in _plants:
			material.set_shader_parameter("wind_strength", strength)
			material.set_shader_parameter("wind_direction", direction.normalized())
			material.set_shader_parameter("wind_speed", speed)
			material.set_shader_parameter("gust_strength", gust)
	if _wind_strength <= 0.0: return
	_clock += delta
	var clock: float = _weather.get("_clock") if is_instance_valid(_weather) else _clock
	for material in _plants: material.set_shader_parameter("wind_time", clock)
