@tool
extends Node3D

signal dressing_rebuilt

## 在子节点指定的区域内随机撒布，按素材和空间分块批量显示。
const ASSETS := "res://assets/meowa/dressing/assets.json"
const CHUNK_SIZE := 8.0
const CATEGORY_NAMES := ["grass", "flowers", "pebbles"]
const WEIGHTS := {"grass": [18.0, 6.0, 1.0, 1.0, 3.0, 1.0], "flowers": [9.0, 8.0, 7.0, 0.4, 0.4, 0.4], "pebbles": [4.0, 4.0, 4.0, 3.0, 2.0, 1.0]}
const LOW_GRASS_WEIGHTS := [24.0, 8.0, 0.6, 0.6, 1.0, 0.3]
const WIND_SHADER := preload("res://shaders/vegetation_wind.gdshader")

@export_group("地图连接")
## 指定要铺设的台地；留空沿用同层名为 Ground 的地形。
@export var terrain: Terrain:
	set(value):
		terrain = value
		_queue_rebuild()

@export_group("编辑器预览")
## 不运行游戏也显示铺设；此开关只影响编辑器。
@export var editor_preview_enabled := true:
	set(value):
		editor_preview_enabled = value
		_queue_rebuild()
## 外部修改脚本后，也可用此按钮重建当前编辑视图。
@export_tool_button("刷新预览", "Reload") var refresh_preview = _refresh_editor_preview

@export_group("草地光影")
## 关闭后恢复原有贴片受光、草地粗糙度和根部表现；不改变分布。
@export var lighting_enabled := true:
	set(value): lighting_enabled = value; _queue_lighting()
## 投影时使用每丛固定朝向的简化轮廓，避免 Q/E 带着草影转动；关闭恢复贴片投影。
@export var stable_shadows := true:
	set(value): stable_shadows = value; _queue_lighting()
## 草丛固定在世界中的受光起伏；0 为朝上的统一法线，仍与相机旋转解耦。
@export_range(0.0, 1.0, 0.05) var normal_strength := 0.35:
	set(value): normal_strength = value; _queue_lighting()
## 草根和其脚下地面的柔和遮蔽；0 关闭。不是额外的动态投影。
@export_range(0.0, 0.8, 0.05) var root_occlusion := 0.3:
	set(value): root_occlusion = value; _queue_lighting()
## 叶尖接收真实光源的背光程度；不使用自发光。
@export_range(0.0, 0.5, 0.01) var backlight_strength := 0.12:
	set(value): backlight_strength = value; _queue_lighting()
## 独立法线补充叶片和花瓣的受光细节；世界朝向不随镜头转动。
@export var leaf_normals_enabled := false:
	set(value): leaf_normals_enabled = value; _queue_lighting()
@export_range(0.0, 1.0, 0.05) var leaf_normal_strength := 0.55:
	set(value): leaf_normal_strength = value; _queue_lighting()
## 草地现有纹理的细微受光凹凸；0 恢复平面，不影响道路、石板和水。
@export_range(0.0, 0.02, 0.001) var ground_relief := 0.008:
	set(value): ground_relief = value; _queue_lighting()
## 草地对美术总控及天气湿润的响应；反光比石板更粗糙，0 保持干草地。
@export_range(0.0, 0.5, 0.01) var ground_wet_response := 0.2:
	set(value): ground_wet_response = value; _queue_lighting()
## 湿草地中零散反光区域的覆盖量；0 关闭，不让整片草地变成镜面。
@export_range(0.0, 0.6, 0.01) var ground_sheen := 0.35:
	set(value): ground_sheen = value; _queue_lighting()

@export_group("花草色阶")
## 叶片、枯草和花瓣各选五档底色；原图、透明轮廓、受光与风摆保留。
@export var color_ramps_enabled := false:
	set(value): color_ramps_enabled = value; _queue_lighting()
## 花瓣各保留自身颜色，所有绿色叶片共用叶色；修改资源立即刷新材质。
@export var color_palette: FoliageColorPalette:
	set(value):
		if color_palette and color_palette.changed.is_connected(_queue_lighting):
			color_palette.changed.disconnect(_queue_lighting)
		color_palette = value
		if color_palette: color_palette.changed.connect(_queue_lighting)
		_queue_lighting()
## 色阶选档前的细节对比；1 沿用原色对比，降低减弱碎亮点和内部暗线。
@export_range(0.0, 1.0, 0.02) var detail_contrast := 1.0:
	set(value): detail_contrast = value; _queue_lighting()

@export_group("铺设密度")
## 每平方米的草丛数量；0 隐藏草。
@export_range(0.0, 10.0, 0.01) var grass_density := 0.28:
	set(value):
		grass_density = clampf(value, 0.0, 10.0)
		_queue_rebuild()
## 每平方米的花簇数量；0 隐藏花。
@export_range(0.0, 10.0, 0.01) var flower_density := 0.10:
	set(value):
		flower_density = clampf(value, 0.0, 10.0)
		_queue_rebuild()
## 当前主场景设为 0；需要石子时再增加。
@export_range(0.0, 10.0, 0.01) var pebble_density := 0.0:
	set(value):
		pebble_density = clampf(value, 0.0, 10.0)
		_queue_rebuild()

@export_group("随机分布")
## 不铺设花草的矩形，坐标为地形本地 X/Z（米）；用于建筑用地与入口。
@export var excluded_areas: Array[Rect2] = []:
	set(value):
		excluded_areas = value
		_queue_rebuild()
## 修改此整数，重新随机位置和变种。
@export var scatter_seed := 10102026:
	set(value):
		scatter_seed = value
		_queue_rebuild()
## 落点的最小距离（米）；可用空间不足时会少生成一些。
@export_range(0.1, 2.0, 0.01) var minimum_spacing := 0.28:
	set(value):
		minimum_spacing = clampf(value, 0.1, 2.0)
		_queue_rebuild()

@export_group("成簇地编（样板）")
## 关闭完整恢复原随机分布、资源比例与大小；开启后低草打底，花集中在局部簇中。
@export var clustered_distribution := false:
	set(value): clustered_distribution = value; _queue_rebuild()
## 草花斑块的空间尺度（米）；固定跟随 scatter_seed，不随镜头或时间移动。
@export_range(1.0, 12.0, 0.1) var cluster_size := 4.8:
	set(value): cluster_size = clampf(value, 1.0, 12.0); _queue_rebuild()
## 0 为均匀位置，1 为明显疏密；各类总数量仍受原密度和可用空间约束。
@export_range(0.0, 1.0, 0.05) var cluster_strength := 0.85:
	set(value): cluster_strength = clampf(value, 0.0, 1.0); _queue_rebuild()
## 花簇进入斑块的阈值；提高后花色集中，高花只在簇心出现。
@export_range(0.3, 0.8, 0.01) var flower_patch_threshold := 0.64:
	set(value): flower_patch_threshold = clampf(value, 0.3, 0.8); _queue_rebuild()
## 同一斑块优先使用同类花色；0 沿用随机混色，1 为单一主花色。只在成簇模式生效。
@export_range(0.0, 1.0, 0.05) var flower_color_grouping := 0.0:
	set(value): flower_color_grouping = clampf(value, 0.0, 1.0); _queue_rebuild()
## 簇心较饱满、簇边较低；0 保留原尺寸和资源权重。落点与数量保持。
@export_range(0.0, 1.0, 0.05) var layered_growth_strength := 0.0:
	set(value): layered_growth_strength = value; _queue_rebuild()
## 同一簇内的固定尺寸变化；只改变实例比例，0 保留等大植株。
@export_range(0.0, 0.3, 0.02) var scale_variation := 0.0:
	set(value): scale_variation = value; _queue_rebuild()
## 成簇模式的草尺寸倍率；只缩放显示，根部仍贴合原台地。
@export_range(0.4, 1.2, 0.01) var grass_scale := 0.72:
	set(value): grass_scale = clampf(value, 0.4, 1.2); _queue_rebuild()
## 成簇模式的花尺寸倍率；不改动或重采样 Meowa 原图。
@export_range(0.4, 1.2, 0.01) var flower_scale := 0.70:
	set(value): flower_scale = clampf(value, 0.4, 1.2); _queue_rebuild()

@export_group("选择资源")
## 多选允许铺设的草资源；全部取消会隐藏草层。
@export_flags("01 低矮疏草", "02 展开密草", "03 细长草叶", "04 羽叶杂草", "05 阔叶草", "06 金黄枯草") var grass_variants := 63:
	set(value):
		grass_variants = value
		_queue_rebuild()
## 多选允许铺设的花资源；全部取消会隐藏花层。
@export_flags("01 白色矮花", "02 粉色矮花", "03 淡紫矮花", "04 黄色细茎花", "05 蓝色双朵花", "06 红花与花苞") var flower_variants := 63:
	set(value):
		flower_variants = value
		_queue_rebuild()
## 多选允许铺设的石子资源，显示数量还受石子密度控制。
@export_flags("01 暖灰扁石", "02 小圆灰石", "03 细扁灰石", "04 棱角灰石", "05 两颗碎石", "06 三颗碎石") var pebble_variants := 63:
	set(value):
		pebble_variants = value
		_queue_rebuild()

var instance_count := 0
var _generated: Node3D
var _rebuild_queued := false
var _editor_initialized := false
var _terrain: Terrain
var _bound_data: TerrainData
var _bound_palette: TerrainPaintPalette
var _lighting_queued := false
var _root_map: ImageTexture
var _root_bounds := Vector4(0, 0, 1, 1)

func _queue_lighting() -> void:
	if not is_inside_tree() or _lighting_queued:
		return
	_lighting_queued = true
	apply_lighting.call_deferred()

func apply_lighting() -> void:
	_lighting_queued = false
	# 新导出项在已打开的 @tool 实例上可能为 Nil；保留有效的 0 / false。
	var defaults := {"lighting_enabled": true, "stable_shadows": true, "normal_strength": 0.35, "root_occlusion": 0.3,
		"backlight_strength": 0.12, "ground_relief": 0.008, "ground_wet_response": 0.2, "ground_sheen": 0.35}
	for key in defaults:
		if get(key) == null:
			set(key, defaults[key])
	if not is_instance_valid(_terrain):
		_terrain = terrain if is_instance_valid(terrain) else get_parent().get_node_or_null("Ground") as Terrain
	if not _terrain:
		return
	if not _root_map and is_instance_valid(_generated):
		_queue_rebuild()
		return
	if _terrain.top_material:
		var ground := _terrain.top_material
		ground.set_shader_parameter("grass_lighting_enabled", lighting_enabled)
		ground.set_shader_parameter("grass_relief", ground_relief)
		ground.set_shader_parameter("grass_wet_response", ground_wet_response)
		ground.set_shader_parameter("grass_sheen", ground_sheen)
		ground.set_shader_parameter("grass_root_occlusion", root_occlusion if _root_map else 0.0)
		# Keep this generated texture out of saved scene resources, like Terrain's map.
		RenderingServer.material_set_param(ground.get_rid(), "grass_root_map", _root_map.get_rid() if _root_map else RID())
		ground.set_shader_parameter("grass_root_bounds", _root_bounds)
	if not is_instance_valid(_generated):
		return
	var applied: Array[ShaderMaterial] = []
	var ramp := color_palette.palette_texture() if color_ramps_enabled and color_palette else null
	for batch: MultiMeshInstance3D in _generated.find_children("*", "MultiMeshInstance3D", true, false):
		var material := batch.multimesh.mesh.material as ShaderMaterial
		if not material or applied.has(material):
			continue
		applied.append(material)
		material.set_shader_parameter("lighting_enabled", lighting_enabled)
		material.set_shader_parameter("stable_shadows", stable_shadows)
		material.set_shader_parameter("normal_strength", normal_strength)
		material.set_shader_parameter("root_occlusion", root_occlusion)
		material.set_shader_parameter("backlight_strength", backlight_strength)
		material.set_shader_parameter("leaf_normals_enabled", leaf_normals_enabled)
		material.set_shader_parameter("leaf_normal_strength", leaf_normal_strength)
		material.set_shader_parameter("color_ramps_enabled", ramp != null)
		material.set_shader_parameter("color_palette", ramp)
		material.set_shader_parameter("detail_contrast", detail_contrast)

func _bake_root_map(placements: Array[Dictionary]) -> void:
	# 一张固定世界坐标的低分辨率遮蔽图；只在重新撒布时生成。
	var data := _terrain.data
	var start := _terrain.to_global(Vector3((data.origin.x - 0.5) * data.cell_size, 0.0, (data.origin.y - 0.5) * data.cell_size))
	var size := Vector2(data.size) * data.cell_size
	_root_bounds = Vector4(start.x, start.z, size.x, size.y)
	var image := Image.create(512, 512, false, Image.FORMAT_R8)
	image.fill(Color(0, 0, 0))
	for placement in placements:
		if String(placement["asset"]).begins_with("pebbles_"):
			continue
		var radius := Vector2(0.3, 0.3) * _category_scale(String(placement["asset"]).get_slice("_", 0)) * float(placement.get("scale",1.0)) / size * 512.0
		var position := to_global(placement["point"])
		var center := (Vector2(position.x, position.z) - Vector2(start.x, start.z)) / size * 512.0
		for y in range(maxi(0, floori(center.y - radius.y)), mini(512, ceili(center.y + radius.y))):
			for x in range(maxi(0, floori(center.x - radius.x)), mini(512, ceili(center.x + radius.x))):
				var distance_squared := ((Vector2(x + 0.5, y + 0.5) - center) / radius).length_squared()
				if distance_squared < 1.0:
					var shade := (1.0 - distance_squared) * (1.0 - distance_squared)
					image.set_pixel(x, y, Color(maxf(image.get_pixel(x, y).r, shade), 0, 0))
	_root_map = ImageTexture.create_from_image(image)

func _ready() -> void:
	set_process(Engine.is_editor_hint())
	_rebuild()

func _process(_delta: float) -> void:
	# 已打开的场景热加载 @tool 脚本时，Godot 不一定重新调用 _ready。
	if Engine.is_editor_hint() and not _editor_initialized:
		_queue_rebuild()

func _refresh_editor_preview() -> void:
	for child in get_children():
		if child is GroundDressingRegion:
			child.set_notify_transform(true)
			child._refresh()
	_queue_rebuild()

func _bind_region(node: Node) -> void:
	if node is GroundDressingRegion:
		node.set_notify_transform(true)
		if not node.settings_changed.is_connected(_queue_rebuild):
			node.settings_changed.connect(_queue_rebuild)
		if Engine.is_editor_hint() and not node.has_node("AreaOutline"):
			node._refresh()

func _on_region_entered(node: Node) -> void:
	if node is GroundDressingRegion:
		_bind_region(node)
		_queue_rebuild()

func _on_region_exiting(node: Node) -> void:
	if node is GroundDressingRegion:
		_queue_rebuild()

func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()

## 运行时锄地只隐藏对应格的花草及投影，不重新随机整片地编。
func set_farming_mask(texture: ImageTexture, bounds: Vector4) -> void:
	if not is_instance_valid(_generated): return
	for layer in _generated.get_children():
		for instance in layer.get_children():
			if not instance is MultiMeshInstance3D: continue
			var material := instance.multimesh.mesh.material as ShaderMaterial
			if not material: continue
			material.set_shader_parameter("farming_hide_enabled", texture != null)
			material.set_shader_parameter("farming_bounds", bounds)
			RenderingServer.material_set_param(material.get_rid(), "farming_map", texture.get_rid() if texture else RID())

func _rebuild() -> void:
	_rebuild_queued = false
	if not is_inside_tree():
		return
	_editor_initialized = true
	_terrain = terrain if is_instance_valid(terrain) else get_parent().get_node_or_null("Ground") as Terrain
	if _terrain and not _terrain.paint_palette_applied.is_connected(_queue_rebuild):
		_terrain.paint_palette_applied.connect(_queue_rebuild)
	var data := _terrain.data if _terrain else null
	if _bound_data != data:
		if _bound_data and _bound_data.changed.is_connected(_queue_rebuild):
			_bound_data.changed.disconnect(_queue_rebuild)
		_bound_data = data
		if _bound_data:
			_bound_data.changed.connect(_queue_rebuild)
	var palette := _terrain.paint_palette if _terrain else null
	if _bound_palette != palette:
		if _bound_palette and _bound_palette.changed.is_connected(_queue_rebuild):
			_bound_palette.changed.disconnect(_queue_rebuild)
		_bound_palette = palette
		if _bound_palette: _bound_palette.changed.connect(_queue_rebuild)
	if not child_entered_tree.is_connected(_on_region_entered):
		child_entered_tree.connect(_on_region_entered)
	if not child_exiting_tree.is_connected(_on_region_exiting):
		child_exiting_tree.connect(_on_region_exiting)
	for child in get_children():
		_bind_region(child)
	if not is_instance_valid(_generated):
		_generated = get_node_or_null("Layers") as Node3D
	if is_instance_valid(_generated):
		_generated.free()
	_generated = null
	_root_map = null
	instance_count = 0
	if (Engine.is_editor_hint() and not editor_preview_enabled) or not _terrain or not _terrain.data:
		apply_lighting()
		dressing_rebuilt.emit()
		return
	_generated = Node3D.new()
	_generated.name = "Layers"
	add_child(_generated)
	var pack: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ASSETS))
	var assets: Dictionary = {}
	var groups: Dictionary = {}
	for category in CATEGORY_NAMES:
		var layer := Node3D.new()
		layer.name = category
		_generated.add_child(layer)
		groups[category] = layer
	for item: Dictionary in pack["assets"]:
		assets[item["id"]] = item
	var batches: Dictionary = {}
	var materials: Dictionary = {}
	var placements := _placements()
	for placement: Dictionary in placements:
		var asset_id: String = placement["asset"]
		var category := asset_id.get_slice("_", 0)
		var point: Vector3 = placement["point"]
		var chunk := Vector2i(floori(point.x / CHUNK_SIZE), floori(point.z / CHUNK_SIZE))
		var key := "%s_%d_%d" % [asset_id, chunk.x, chunk.y]
		if not batches.has(key):
			batches[key] = {"asset": asset_id, "category": category, "points": [], "scales": []}
		batches[key]["points"].append(point)
		batches[key]["scales"].append(placement.get("scale",1.0))
		instance_count += 1
	for key in batches:
		var batch: Dictionary = batches[key]
		var item: Dictionary = assets[batch["asset"]]
		var mesh := QuadMesh.new()
		var plant_scale := _category_scale(batch["category"])
		mesh.size = Vector2(item["canvas"][0], item["canvas"][1]) * float(item["pixel_size"]) * plant_scale
		if not materials.has(batch["asset"]):
			materials[batch["asset"]] = _material_for(item, batch["category"])
		mesh.material = materials[batch["asset"]]
		if batch["category"] != "pebbles":
			# UV 44/48 处有一排顶点，风摆时落地锚点保持固定。
			mesh.subdivide_depth = 11
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_custom_data = true
		multimesh.mesh = mesh
		var points: Array = batch["points"]
		multimesh.instance_count = points.size()
		var anchor_height: float = (float(item["anchor"][1]) - float(item["canvas"][1]) * 0.5) * float(item["pixel_size"]) * plant_scale
		for index in points.size():
			var growth_scale: float = batch["scales"][index]
			multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * growth_scale), points[index] + Vector3.UP * anchor_height * growth_scale))
			multimesh.set_instance_custom_data(index, Color(anchor_height * growth_scale, 0.0, 0.0, 0.0))
		var instance := MultiMeshInstance3D.new()
		instance.name = key
		instance.multimesh = multimesh
		instance.extra_cull_margin = 0.6
		groups[batch["category"]].add_child(instance)
	_bake_root_map(placements)
	apply_lighting()
	dressing_rebuilt.emit()

func _material_for(item: Dictionary, category: String) -> Material:
	if category != "pebbles":
		var vegetation := ShaderMaterial.new()
		vegetation.shader = WIND_SHADER
		vegetation.set_shader_parameter("sprite_texture", load(item["texture"]))
		var normal := SurfaceNormalMaps.for_texture(load(item["texture"]))
		vegetation.set_shader_parameter("leaf_normal_texture", normal)
		vegetation.set_shader_parameter("leaf_normal_available", normal != null)
		vegetation.set_shader_parameter("root_uv", float(item["anchor"][1]) / float(item["canvas"][1]))
		vegetation.set_shader_parameter("visible_height_uv", float(item["visible_size"][1]) / float(item["canvas"][1]))
		vegetation.set_shader_parameter("flexibility", 0.055 if category == "grass" else 0.035)
		var variant := int(String(item["id"]).get_slice("_", 1))
		vegetation.set_shader_parameter("plant_palette_row", variant + 1 if category == "flowers" else 1 if variant == 6 else 0)
		return vegetation
	var stone := StandardMaterial3D.new()
	stone.albedo_texture = load(item["texture"])
	stone.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	stone.alpha_scissor_threshold = 0.5
	stone.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	stone.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	stone.cull_mode = BaseMaterial3D.CULL_DISABLED
	stone.roughness = 1.0
	return stone

func _placements() -> Array[Dictionary]:
	var patch_noise: FastNoiseLite
	if clustered_distribution:
		patch_noise = FastNoiseLite.new()
		patch_noise.seed = scatter_seed
		patch_noise.frequency = 1.0 / cluster_size
		patch_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		patch_noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	var densities := {"grass": grass_density, "flowers": flower_density, "pebbles": pebble_density}
	var masks := {"grass": grass_variants, "flowers": flower_variants, "pebbles": pebble_variants}
	var choices: Dictionary = {}
	for category in masks:
		choices[category] = []
		for variant in 6:
			if int(masks[category]) & (1 << variant):
				choices[category].append(variant)
	var result: Array[Dictionary] = []
	var occupied: Dictionary = {}
	for region in get_children():
		if not region is GroundDressingRegion:
			continue
		if not region.enabled:
			continue
		var surface := _region_surface(region)
		if surface.is_empty():
			continue
		var area: float = surface.back()["cumulative"]
		var region_masks := {"grass": region.grass_variants, "flowers": region.flower_variants, "pebbles": region.pebble_variants}
		for category_index in CATEGORY_NAMES.size():
			var category: String = CATEGORY_NAMES[category_index]
			var allowed: Array = choices[category].filter(func(variant: int) -> bool: return (int(region_masks[category]) & (1 << variant)) != 0)
			if (int(region.categories) & (1 << category_index)) == 0 or allowed.is_empty():
				continue
			var random := RandomNumberGenerator.new()
			random.seed = scatter_seed + String(region.name).hash() + category_index * 997
			var variant_random := RandomNumberGenerator.new()
			variant_random.seed = random.seed + 7919
			var target := roundi(area * float(densities[category]) * region.density_multiplier)
			var placed := 0
			for attempt in target * 24:
				if placed >= target:
					break
				var triangle := _pick_triangle(surface, random.randf_range(0.0, area))
				var u := random.randf()
				var v := random.randf()
				if u + v > 1.0:
					u = 1.0 - u
					v = 1.0 - v
				var position_2d: Vector2 = triangle["a"] + (triangle["b"] - triangle["a"]) * u + (triangle["c"] - triangle["a"]) * v
				var patch := 0.0
				if clustered_distribution and category != "pebbles":
					patch = clampf(patch_noise.get_noise_2d(position_2d.x, position_2d.y) * 1.5 + 0.5, 0.0, 1.0)
					var acceptance := smoothstep(flower_patch_threshold, minf(1.0, flower_patch_threshold + 0.18), patch) if category == "flowers" else lerpf(0.1, 1.0, smoothstep(0.35, 0.7, patch))
					if random.randf() > lerpf(1.0, acceptance, cluster_strength):
						continue
				var local_allowed := allowed
				if clustered_distribution and category == "flowers" and patch < flower_patch_threshold + 0.08:
					local_allowed = allowed.filter(func(variant: int) -> bool: return variant < 3)
					if local_allowed.is_empty(): continue
				if not _claim_point(position_2d, occupied):
					continue
				var point := to_local(_terrain.to_global(Vector3(position_2d.x, float(triangle["level"]) * _terrain.data.layer_height, position_2d.y)))
				var weights: Array = LOW_GRASS_WEIGHTS if clustered_distribution and category == "grass" else WEIGHTS[category]
				var growth := smoothstep(0.32,0.82,patch)
				if clustered_distribution and category == "grass" and layered_growth_strength > 0.0:
					weights = weights.duplicate()
					for index in weights.size(): weights[index] = lerpf(weights[index],WEIGHTS[category][index],growth * layered_growth_strength)
				var variant := _pick_variant(local_allowed, weights, variant_random)
				if clustered_distribution and category == "flowers" and flower_color_grouping > 0.0:
					var flower_cell := Vector2i((position_2d / cluster_size).floor())
					var flower_random := RandomNumberGenerator.new()
					flower_random.seed = scatter_seed + ("flower_%d_%d" % [flower_cell.x, flower_cell.y]).hash()
					if variant_random.randf() < flower_color_grouping:
						variant = _pick_variant(local_allowed, weights, flower_random)
				var growth_scale := 1.0
				if clustered_distribution and category != "pebbles":
					var variation := sin(position_2d.dot(Vector2(17.3,43.7))) * scale_variation
					growth_scale = lerpf(1.0,lerpf(0.72,1.2,growth),layered_growth_strength) * (1.0+variation)
				result.append({"asset": "%s_%02d" % [category, variant + 1], "point": point, "scale": growth_scale})
				placed += 1
	return result

func _category_scale(category: String) -> float:
	if not clustered_distribution:
		return 1.0
	return grass_scale if category == "grass" else (flower_scale if category == "flowers" else 1.0)

func _paintable_cell(cell: Vector2i, level: int) -> bool:
	var data := _terrain.data
	if not data.has_cell(cell) or data.get_level(cell) != level or data.get_biome(cell) != TerrainData.Biome.WILD:
		return false
	for flag in [1, 2, 4, 8, 16]:
		if data.has_overlay(cell, flag):
			return false
	var local := cell-data.origin
	var paint := data.paint_at_index(local.y*data.size.x+local.x)
	if paint != 0:
		var brush := _terrain.paint_palette.brush_for_id(paint) if _terrain.paint_palette else null
		return brush != null and brush.is_grass
	return true

func _region_surface(region: GroundDressingRegion) -> Array[Dictionary]:
	var polygon := PackedVector2Array()
	var half := region.area_size * 0.5
	for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		var point := _terrain.to_local(region.to_global(Vector3(corner.x, 0, corner.y)))
		polygon.append(Vector2(point.x, point.z))
	var surface: Array[Dictionary] = []
	var cumulative := 0.0
	var data := _terrain.data
	# 只扫描与区域包围盒可能相交的格子，保留原有 Z/X 顺序与随机分布。
	# 多留一圈边界，覆盖旋转区域和格边浮点误差；精确裁切仍由下方完成。
	var minimum := polygon[0]
	var maximum := polygon[0]
	for point in polygon:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	var first := Vector2i(floori(minimum.x / data.cell_size - 0.5), floori(minimum.y / data.cell_size - 0.5)).max(data.origin)
	var end_cell := Vector2i(ceili(maximum.x / data.cell_size + 0.5) + 1, ceili(maximum.y / data.cell_size + 0.5) + 1).min(data.origin + data.size)
	for z in range(first.y, end_cell.y):
		for x in range(first.x, end_cell.x):
			var cell := Vector2i(x, z)
			var level := data.get_level(cell)
			if not _paintable_cell(cell, level):
				continue
			var start := (Vector2(cell) - Vector2(0.5, 0.5)) * data.cell_size
			var end := start + Vector2.ONE * data.cell_size
			# 道路、水面和台地边缘留出轮廓宽度。
			if not _paintable_cell(cell + Vector2i.LEFT, level): start.x += 0.45
			if not _paintable_cell(cell + Vector2i.RIGHT, level): end.x -= 0.45
			if not _paintable_cell(cell + Vector2i.UP, level): start.y += 0.45
			if not _paintable_cell(cell + Vector2i.DOWN, level): end.y -= 0.45
			var clipped := Geometry2D.intersect_polygons(polygon, PackedVector2Array([start, Vector2(end.x, start.y), end, Vector2(start.x, end.y)]))
			for shape: PackedVector2Array in clipped:
				for index in range(1, shape.size() - 1):
					var area := absf((shape[index] - shape[0]).cross(shape[index + 1] - shape[0])) * 0.5
					if area < 0.0001:
						continue
					cumulative += area
					surface.append({"a": shape[0], "b": shape[index], "c": shape[index + 1], "level": level, "cumulative": cumulative})
	return surface

func _pick_triangle(surface: Array[Dictionary], value: float) -> Dictionary:
	var low := 0
	var high := surface.size() - 1
	while low < high:
		var middle := (low + high) >> 1
		if float(surface[middle]["cumulative"]) < value:
			low = middle + 1
		else:
			high = middle
	return surface[low]

func _pick_variant(choices: Array, weights: Array, random: RandomNumberGenerator) -> int:
	var total := 0.0
	for variant: int in choices:
		total += float(weights[variant])
	var value := random.randf() * total
	for variant: int in choices:
		value -= float(weights[variant])
		if value <= 0.0:
			return variant
	return choices.back()

func _claim_point(point: Vector2, occupied: Dictionary) -> bool:
	if excluded_areas:
		for area: Rect2 in excluded_areas:
			if area.has_point(point):
				return false
	for reserved in [Vector2(0, 1.4), Vector2(4.7, 8.5), Vector2(6.9, 8.5)]:
		if point.distance_squared_to(reserved) < 0.95 * 0.95:
			return false
	var bucket := Vector2i(floori(point.x / minimum_spacing), floori(point.y / minimum_spacing))
	for z in range(-1, 2):
		for x in range(-1, 2):
			for other: Vector2 in occupied.get(bucket + Vector2i(x, z), []):
				if point.distance_squared_to(other) < minimum_spacing * minimum_spacing:
					return false
	if not occupied.has(bucket):
		occupied[bucket] = []
	occupied[bucket].append(point)
	return true
