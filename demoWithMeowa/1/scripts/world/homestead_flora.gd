@tool
extends Node3D

signal dressing_rebuilt

## 小院低矮植被：使用原生 Meowa 像素素材，地形与道路留空由父节点决定。
const WIND_SHADER := preload("res://shaders/environment/vegetation_wind.gdshader")
const TEXTURES := [
	"res://assets/meowa/dressing/grass/grass_01.png",
	"res://assets/meowa/dressing/grass/grass_02.png",
	"res://assets/meowa/dressing/grass/grass_03.png",
	"res://assets/meowa/dressing/flowers/flower_01.png",
	"res://assets/meowa/dressing/flowers/flower_02.png",
	"res://assets/meowa/dressing/flowers/flower_03.png",
]
const VISIBLE_HEIGHTS := [20.0, 27.0, 34.0, 16.0, 19.0, 20.0]
const BOUNDS := Rect2(-30.0, -26.0, 60.0, 52.0)
const SPACING := 0.24
const FLOWER_CENTERS := [Vector2(-10.5, -4.0), Vector2(-3.8, 5.5), Vector2(5.8, -6.0), Vector2(4.0, 5.8), Vector2(12.0, 1.5)]

@export_group("编辑器预览")
## 关闭只隐藏编辑器中的生成植被，游戏中仍显示。
@export var editor_preview_enabled := true:
	set(value): editor_preview_enabled = value; _queue_rebuild()
@export_tool_button("刷新预览", "Reload") var refresh_preview = rebuild

@export_group("分布与尺寸")
## 平均草丛数/平方米；道路及预留空间会降低实际数量。
@export_range(0.0, 3.0, 0.01) var grass_density := 0.40:
	set(value): grass_density = maxf(value, 0.0); _queue_rebuild()
## 平均花簇数/平方米；白花较多，粉紫花点缀在独立的花丛中。
@export_range(0.0, 0.5, 0.005) var flower_density := 0.075:
	set(value): flower_density = maxf(value, 0.0); _queue_rebuild()
## 可见草叶的最小/最大高度，米；不是透明画布尺寸。
@export var grass_height := Vector2(0.18, 0.35):
	set(value): grass_height = _height_range(value); _queue_rebuild()
## 可见花簇的最小/最大高度，米。
@export var flower_height := Vector2(0.24, 0.42):
	set(value): flower_height = _height_range(value); _queue_rebuild()
## 同一种子与密度重现相同的草花位置；改变它可试不同的疏密分布。
@export var scatter_seed := 12102026:
	set(value): scatter_seed = value; _queue_rebuild()

@export_group("花草受光")
@export var lighting_enabled := true:
	set(value): lighting_enabled = value; _apply_lighting()
@export var stable_shadows := true:
	set(value): stable_shadows = value; _apply_lighting()
@export_range(0.0, 1.0, 0.05) var normal_strength := 0.35:
	set(value): normal_strength = value; _apply_lighting()
@export_range(0.0, 0.8, 0.05) var root_occlusion := 0.3:
	set(value): root_occlusion = value; _apply_lighting()
@export_range(0.0, 0.5, 0.01) var backlight_strength := 0.12:
	set(value): backlight_strength = value; _apply_lighting()
@export_range(0.0, 0.02, 0.001) var ground_relief := 0.008:
	set(value): ground_relief = value; _apply_lighting()
@export_range(0.0, 0.5, 0.01) var ground_wet_response := 0.2:
	set(value): ground_wet_response = value; _apply_lighting()
@export_range(0.0, 0.6, 0.01) var ground_sheen := 0.35:
	set(value): ground_sheen = value; _apply_lighting()

@export_group("花草风摆")
@export var wind_enabled := true:
	set(value): wind_enabled = value; _apply_wind()
## 世界 X/Z 平面的风向，零向量表示不摆动。
@export var wind_direction := Vector2(1.0, 0.25):
	set(value): wind_direction = value; _apply_wind()
@export_range(0.0, 3.0, 0.01) var wind_strength := 0.55:
	set(value): wind_strength = maxf(value, 0.0); _apply_wind()
@export_range(0.1, 5.0, 0.05) var wind_speed := 1.35:
	set(value): wind_speed = maxf(value, 0.1); _apply_wind()
@export_range(0.0, 1.0, 0.01) var gust_strength := 0.25:
	set(value): gust_strength = clampf(value, 0.0, 1.0); _apply_wind()

var instance_count := 0
var _generated: Node3D
var _materials: Array[ShaderMaterial] = []
var _rebuild_queued := false
var _wind_time := 0.0
var _root_map: ImageTexture

func _height_range(value: Vector2) -> Vector2:
	return Vector2(maxf(minf(value.x, value.y), 0.05), maxf(maxf(value.x, value.y), 0.05))

func _ready() -> void:
	# 初次加载由父 Homestead 在地表就绪后调用；避免先后生成两次。
	if get_parent() and get_parent().is_node_ready():
		rebuild()

func _process(delta: float) -> void:
	_wind_time += delta
	for material in _materials:
		material.set_shader_parameter("wind_time", _wind_time)

func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()

## 父地形重建后调用；所有生成节点无 owner，不写入场景文件。
func rebuild() -> void:
	_rebuild_queued = false
	if not is_inside_tree():
		return
	if not is_instance_valid(_generated):
		_generated = get_node_or_null("GeneratedFlora") as Node3D
	if is_instance_valid(_generated):
		_generated.free()
	_generated = null
	_materials.clear()
	_root_map = null
	instance_count = 0
	if Engine.is_editor_hint() and not editor_preview_enabled:
		_apply_lighting()
		dressing_rebuilt.emit()
		return
	var homestead := get_parent() as Node3D
	if not homestead or not homestead.has_method("ground_height") or not homestead.has_method("clearance"):
		return
	_generated = Node3D.new()
	_generated.name = "GeneratedFlora"
	add_child(_generated)
	var random := RandomNumberGenerator.new()
	random.seed = scatter_seed
	var occupied: Dictionary = {}
	var batches: Dictionary = {}
	var roots := PackedVector2Array()
	for category in 2:
		var density := grass_density if category == 0 else flower_density
		var centers := _cluster_centers(random, homestead, category)
		var target := roundi(BOUNDS.get_area() * density)
		var placed := 0
		for attempt in target * 8:
			if placed >= target:
				break
			var point := _candidate(random, centers, category)
			if not BOUNDS.has_point(point):
				continue
			var clearance := float(homestead.call("clearance", point))
			if clearance <= 0.7:
				continue
			# 松散草缘过渡；院心保持更开阔，走入草地才逐渐变密。
			var courtyard := Rect2(-12.0, -11.0, 22.0, 22.0).has_point(point)
			var edge := minf(minf(point.x + 30.0, 30.0 - point.x), minf(point.y + 26.0, 26.0 - point.y))
			var probability := clampf((clearance - 0.7) / 1.1, 0.0, 1.0) * clampf(edge / 1.5, 0.0, 1.0)
			if courtyard:
				probability *= 0.45
			if random.randf() > probability or not _has_space(point, occupied):
				continue
			var variant := _variant(random, category, point, centers)
			var size_index := random.randi_range(0, 2)
			var key := Vector2i(variant, size_index)
			var ranges := grass_height if category == 0 else flower_height
			var height := lerpf(ranges.x, ranges.y, float(size_index) * 0.5)
			var pixel_size := height / float(VISIBLE_HEIGHTS[variant])
			var ground := float(homestead.call("ground_height", point))
			var position := homestead.to_global(Vector3(point.x, ground + 20.0 * pixel_size, point.y))
			if not batches.has(key):
				batches[key] = []
			batches[key].append(to_local(position))
			roots.append(Vector2(position.x, position.z))
			var cell := Vector2i(floori(point.x / SPACING), floori(point.y / SPACING))
			if not occupied.has(cell):
				occupied[cell] = []
			occupied[cell].append(point)
			placed += 1
			instance_count += 1
	for variant in TEXTURES.size():
		var material := ShaderMaterial.new()
		material.shader = WIND_SHADER
		material.set_shader_parameter("sprite_texture", load(TEXTURES[variant]))
		material.set_shader_parameter("root_uv", 44.0 / 48.0)
		material.set_shader_parameter("visible_height_uv", float(VISIBLE_HEIGHTS[variant]) / 48.0)
		material.set_shader_parameter("flexibility", 0.042 if variant < 3 else 0.032)
		_materials.append(material)
	for key: Vector2i in batches:
		var ranges := grass_height if key.x < 3 else flower_height
		var height := lerpf(ranges.x, ranges.y, float(key.y) * 0.5)
		var mesh := QuadMesh.new()
		mesh.size = Vector2.ONE * 48.0 * height / float(VISIBLE_HEIGHTS[key.x])
		mesh.subdivide_depth = 11
		mesh.material = _materials[key.x]
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = mesh
		var points: Array = batches[key]
		multimesh.instance_count = points.size()
		for index in points.size():
			multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, points[index]))
			multimesh.set_instance_custom_data(index, Color(20.0 * height / float(VISIBLE_HEIGHTS[key.x]), 0.0, 0.0, 0.0))
		var batch := MultiMeshInstance3D.new()
		batch.name = "%s_%d_%d" % ["grass" if key.x < 3 else "flowers", key.x % 3 + 1, key.y]
		batch.multimesh = multimesh
		batch.extra_cull_margin = 0.3
		_generated.add_child(batch)
	_bake_root_map(roots)
	_apply_lighting()
	_apply_wind()
	dressing_rebuilt.emit()

func _bake_root_map(roots: PackedVector2Array) -> void:
	if roots.is_empty():
		return
	var rect: Rect2 = get_parent().call("get_world_rect")
	var image := Image.create(512, 512, false, Image.FORMAT_R8)
	image.fill(Color.BLACK)
	var radius := Vector2.ONE * 0.3 / rect.size * 512.0
	for point in roots:
		var center := (point - rect.position) / rect.size * 512.0
		for y in range(maxi(0, floori(center.y - radius.y)), mini(512, ceili(center.y + radius.y))):
			for x in range(maxi(0, floori(center.x - radius.x)), mini(512, ceili(center.x + radius.x))):
				var distance := ((Vector2(x + 0.5, y + 0.5) - center) / radius).length_squared()
				if distance < 1.0:
					var shade := (1.0 - distance) * (1.0 - distance)
					image.set_pixel(x, y, Color(maxf(image.get_pixel(x, y).r, shade), 0.0, 0.0))
	_root_map = ImageTexture.create_from_image(image)

func _apply_lighting() -> void:
	if not is_inside_tree():
		return
	for material in _materials:
		material.set_shader_parameter("lighting_enabled", lighting_enabled)
		material.set_shader_parameter("stable_shadows", stable_shadows)
		material.set_shader_parameter("normal_strength", normal_strength)
		material.set_shader_parameter("root_occlusion", root_occlusion)
		material.set_shader_parameter("backlight_strength", backlight_strength)
	var homestead := get_parent()
	if not homestead.has_method("get_ground_material"):
		return
	var ground := homestead.call("get_ground_material") as ShaderMaterial
	if not ground:
		return
	var rect: Rect2 = homestead.call("get_world_rect")
	ground.set_shader_parameter("grass_lighting_enabled", lighting_enabled)
	ground.set_shader_parameter("grass_relief", ground_relief)
	ground.set_shader_parameter("grass_wet_response", ground_wet_response)
	ground.set_shader_parameter("grass_sheen", ground_sheen)
	ground.set_shader_parameter("grass_root_occlusion", root_occlusion if _root_map else 0.0)
	ground.set_shader_parameter("grass_root_bounds", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	RenderingServer.material_set_param(ground.get_rid(), "grass_root_map", _root_map.get_rid() if _root_map else RID())

func _cluster_centers(random: RandomNumberGenerator, homestead: Node3D, category: int) -> Array[Vector2]:
	var centers: Array[Vector2] = []
	if category == 1:
		for point: Vector2 in FLOWER_CENTERS:
			if float(homestead.call("clearance", point)) > 0.7:
				centers.append(point)
	var random_count := 24 if category == 0 else 2
	var target := centers.size() + random_count
	for attempt in random_count * 12:
		if centers.size() >= target:
			break
		var point := Vector2(random.randf_range(-28.0, 28.0), random.randf_range(-24.0, 24.0))
		if float(homestead.call("clearance", point)) > 1.5:
			centers.append(point)
	return centers

func _candidate(random: RandomNumberGenerator, centers: Array[Vector2], category: int) -> Vector2:
	if centers.is_empty() or random.randf() < (0.22 if category == 0 else 0.08):
		return Vector2(random.randf_range(-30.0, 30.0), random.randf_range(-26.0, 26.0))
	var center := centers[random.randi_range(0, centers.size() - 1)]
	var radius := 3.0 if category == 0 else 1.5
	return center + Vector2(random.randfn(0.0, radius), random.randfn(0.0, radius * 0.65))

func _has_space(point: Vector2, occupied: Dictionary) -> bool:
	var cell := Vector2i(floori(point.x / SPACING), floori(point.y / SPACING))
	for y in range(-1, 2):
		for x in range(-1, 2):
			for other: Vector2 in occupied.get(cell + Vector2i(x, y), []):
				if point.distance_squared_to(other) < SPACING * SPACING:
					return false
	return true

func _variant(random: RandomNumberGenerator, category: int, point: Vector2, centers: Array[Vector2]) -> int:
	var roll := random.randf()
	if category == 0:
		return 0 if roll < 0.55 else (1 if roll < 0.86 else 2)
	# 每片花丛以一种颜色为主，白花为底，粉紫只在少量独立簇中出现。
	var nearest := 0
	var distance := INF
	for index in centers.size():
		var candidate := point.distance_squared_to(centers[index])
		if candidate < distance:
			distance = candidate
			nearest = index
	if roll > 0.86:
		return 3
	return 5 if nearest % 5 == 2 else (4 if nearest % 5 == 4 else 3)

func _apply_wind() -> void:
	if is_inside_tree():
		var weather := get_parent().get_parent().get_node_or_null("MapEffects/Weather")
		if weather and weather.dressing == self:
			weather._refresh_vegetation()
			return
	for material in _materials:
		material.set_shader_parameter("wind_direction", wind_direction.normalized())
		material.set_shader_parameter("wind_strength", wind_strength if wind_enabled else 0.0)
		material.set_shader_parameter("wind_speed", wind_speed)
		material.set_shader_parameter("gust_strength", gust_strength)
		material.set_shader_parameter("wind_time", _wind_time)
