@tool
class_name SpawnVisualSample
extends Node

const ORIGINAL = preload("res://data/visual/spawn_original.tres")
# 保留用户实际审阅的原始灯光；历史参数资源仍原样保存。
const ORIGINAL_RENDER = preload("res://data/visual/spawn_original_render.tres")
const DAY = preload("res://data/visual/spawn_lumina_day.tres")
const RAIN = preload("res://data/visual/spawn_lumina_rain.tres")
const NIGHT = preload("res://data/visual/spawn_lumina_night.tres")
const PIXEL_SAMPLE_PATH := "res://assets/meowa/pixel_sample/"
const SMOOTH_GRASS_PATH := "res://assets/ground/grass_smooth_v1/"
const STYLE_NAMES := ["原始光影", "Lumina 黄金时段", "Lumina 细雨", "Lumina 夜晚"]
# 新增总控项的旧版基线；切 Style 或关闭样板时不能遗留上一种样板的后处理。
const FOG_POST_DEFAULTS := {"fog_curve": 1.0, "bloom_threshold": 1.0, "bloom_floor": 0.04,
	"vignette_radius": 0.85, "shadow_lift": Vector3(0.012, 0.020, 0.035)}
signal style_changed(index: int, title: String)

@export_group("画面风格")
## 只切光影、材质受光与天气；相机、布局、花草分布、像素材质开关独立保留。
@export_enum("原始光影", "Lumina 黄金时段", "Lumina 细雨", "Lumina 夜晚") var style := 1:
	set(value): style = clampi(value, 0, 3); _queue_apply()
## 直接更改 Weather 的晴雨开关时，光照预设随之调整；原始画面不联动。
@export var follow_weather := true
@export_tool_button("应用视觉与天气", "Reload") var apply_button = apply_style
@export_subgroup("游戏内切换")
@export var runtime_switch_enabled := true
## R 单次按下切换下一种风格；输入文字、管理界面和升级选择期间不接管按键。
@export var style_key: Key = KEY_R

@export_group("原始光影增强")
## 只增强原始 Style 的主光、暗面补光和阴影交界；关闭恢复之前实际审阅的光影。
@export var original_light_refinement_enabled := true:
	set(value): original_light_refinement_enabled = value; _queue_apply()
## 保留原暖光方向与局部光斑布局；强度、补光色、阴影柔化和曝光等长期参数在此配置。
@export var original_light_preset: SpawnVisualPreset = preload("res://data/visual/spawn_original_refined.tres"):
	set(value): original_light_preset = value; _queue_apply()

@export_group("统一像素美术")
## 独立切换草地、卵石路、墙面和屋瓦，不随 Style 改变。
@export var pixel_art_enabled := true:
	set(value): pixel_art_enabled = value; _queue_pixel_apply()
## 64 像素纹理每块覆盖 1.6 米，约 40 像素/米，与现有人物接近。
@export_range(0.8, 3.2, 0.05, "suffix:m") var pixel_building_texture_meters := 1.6:
	set(value): pixel_building_texture_meters = value; _queue_pixel_apply()
## 降低瓦缝和亮边的对比，保留屋瓦主体颜色；1 表示原贴图对比。
@export_range(0.0, 1.2, 0.05) var pixel_roof_contrast := 0.65:
	set(value): pixel_roof_contrast = value; _queue_pixel_apply()
## 1 保留原卵石细节；降低只弱化孤立小暗点，连续石缝和大暗面保留。关闭色阶仍可使用，不改变凹凸。
@export_range(0.0, 1.0, 0.05) var pixel_stone_detail_strength := 0.65:
	set(value): pixel_stone_detail_strength = value; _queue_color_apply()

@export_group("草地与花草样板")
## 关闭恢复加载时的草花密度、分簇与颜色；R 切光影不重设这一组参数。
@export var vegetation_sample_enabled := true:
	set(value): vegetation_sample_enabled = value; _queue_vegetation_apply()
## 只覆盖草花参数；实际微调也可在 GroundDressing 中操作。
@export var vegetation_preset: SpawnVisualPreset = preload("res://data/visual/spawn_vegetation_lumina.tres")
## 草地底纹选档前的对比；1 保留原细节，降低减弱碎色点，原图凹凸保留。
@export_range(0.0, 1.0, 0.02) var pixel_grass_contrast := 0.70:
	set(value): pixel_grass_contrast = value; _queue_color_apply()
@export_tool_button("应用草地与花草样板", "Reload") var vegetation_apply_button = apply_vegetation_sample

@export_group("平滑草地底面")
## 独立使用干净底色、浅法线和干湿 ORM；不改变草花铺设与草根接触阴影。
@export var smooth_grass_enabled := false:
	set(value): smooth_grass_enabled = value; _queue_pixel_apply()

@export_group("草地深浅变化")
## 世界坐标固定的深浅斑块，独立于光影 Style、草地受光和像素材质开关。
@export var grass_variation_enabled := true:
	set(value): grass_variation_enabled = value; _queue_grass_variation_apply()
## 0 不叠加色块，保留贴图；默认 0.16 对应原样板约 0.84～1.04 的明暗倍率。
@export_range(0.0, 0.5, 0.01) var grass_variation_strength := 0.16:
	set(value): grass_variation_strength = value; _queue_grass_variation_apply()
## 噪声格的世界尺寸，米；越大斑块越大，不改变草地贴图或地形格尺寸。
@export_range(0.5, 20.0, 0.1, "suffix:m") var grass_variation_size := 1.0 / 0.38:
	set(value): grass_variation_size = value; _queue_grass_variation_apply()
## 直接更新编辑器中的地面材质，不套用 Style、不重建地图或花草。
@export_tool_button("刷新草地斑块预览", "Reload") var grass_variation_preview_button = apply_grass_variation

@export_group("统一材质色阶")
## 将这组新材质的底色映射到各自五档色阶，真实灯光与天气继续生效。
@export var color_ramps_enabled := true:
	set(value): color_ramps_enabled = value; _queue_color_apply()
## 四条色阶从暗到亮排列；修改资源中的颜色会立即更新当前样板。
@export var color_palette: PixelColorPalette = preload("res://data/visual/spawn_pixel_palette.tres"):
	set(value):
		if color_palette and color_palette.changed.is_connected(_queue_color_apply):
			color_palette.changed.disconnect(_queue_color_apply)
		color_palette = value
		if color_palette: color_palette.changed.connect(_queue_color_apply)
		_queue_color_apply()

@export_group("边缘衔接与独立法线")
## 路边窄草缘、台地草沿的颜色和接缝受光；不改变道路或碰撞。
@export var edge_blending_enabled := true:
	set(value): edge_blending_enabled = value; _queue_surface_apply()
@export_range(0.025, 0.3, 0.025, "suffix:m") var path_edge_width := 0.125:
	set(value): path_edge_width = value; _queue_surface_apply()
@export_range(0.0, 0.8, 0.05) var path_edge_strength := 0.4:
	set(value): path_edge_strength = value; _queue_surface_apply()
## 使用对应法线数据；关闭恢复之前从颜色亮度估算的凹凸。
@export var surface_normals_enabled := true:
	set(value): surface_normals_enabled = value; _queue_surface_apply()
@export_range(0.0, 1.5, 0.05) var surface_normal_strength := 0.8:
	set(value): surface_normal_strength = value; _queue_surface_apply()
## 人物使用逐帧、与原图同尺寸的法线，不改姿态、轮廓或颜色。
@export var character_normals_enabled := true:
	set(value): character_normals_enabled = value; _queue_surface_apply()
@export_range(0.0, 1.0, 0.05) var character_normal_strength := 0.4:
	set(value): character_normal_strength = value; _queue_surface_apply()
@export_tool_button("刷新边缘与法线", "Reload") var surface_apply_button = apply_surface_details

@export_group("明暗层次样板")
## 只切草地、花草色阶及主光和半球补光；保留镜头、布局、法线、分布与独立深浅参数。
@export var value_sample_enabled := true:
	set(value): value_sample_enabled = value; _queue_apply()
## 原版和样板色板、三种光影配置；资源直接由参数总览索引，不另外维护颜色副本。
@export var value_sample_profile: ValueLightingProfile = preload("res://data/visual/spawn_value_sample.tres"):
	set(value): value_sample_profile = value; _value_sample_applied = null; _queue_apply()
@export_tool_button("应用明暗层次样板", "Reload") var value_apply_button = apply_value_sample

@export_group("雾与后处理样板")
## 分别细调四种 Style 的空气透视、泛光与暗部调色；关闭恢复此前的雾和后处理。
@export var fog_post_enabled := true:
	set(value): fog_post_enabled = value; _queue_apply()
## 按原始、黄金、细雨、夜晚排列；只覆盖雾和后处理，长期微调在资源的 Node Values 中保存。
@export var fog_post_presets: Array[SpawnVisualPreset] = [
	preload("res://data/visual/spawn_atmosphere_original.tres"),
	preload("res://data/visual/spawn_atmosphere_day.tres"),
	preload("res://data/visual/spawn_atmosphere_rain.tres"),
	preload("res://data/visual/spawn_atmosphere_night.tres")]:
	set(value): fog_post_presets = value; _queue_apply()
@export_tool_button("应用雾与后处理", "Reload") var fog_post_apply_button = apply_style

var _queued := false
var _isolated := false
var _weather_mode := -1
var _window_lights: Array[OmniLight3D] = []
var _pixel_queued := false
var _color_queued := false
var _vegetation_queued := false
var _vegetation_original: Dictionary = {}
var _grass_center := Color.WHITE
var _grass_center_cached := false
var _grass_variation_queued := false
var _editor_grass_preview_initialized := false
var _pixel_brush_values: Dictionary = {}
var _pixel_building_values: Dictionary = {}
var _surface_queued := false
var _edge_original: Dictionary = {}
var _value_sample_applied: Variant = null

func _apply_value_palettes() -> void:
	if not value_sample_profile or _value_sample_applied == value_sample_enabled: return
	var dressing := get_parent().get_node_or_null("GroundDressing")
	color_palette = value_sample_profile.material_palette if value_sample_enabled else value_sample_profile.original_material_palette
	if dressing:
		dressing.color_palette = value_sample_profile.foliage_palette if value_sample_enabled and vegetation_sample_enabled else value_sample_profile.original_foliage_palette
	_value_sample_applied = value_sample_enabled

func apply_value_sample() -> void:
	_value_sample_applied = null
	apply_style()

func _queue_surface_apply() -> void:
	if not is_inside_tree() or _surface_queued: return
	_surface_queued = true
	apply_surface_details.call_deferred()

func apply_surface_details() -> void:
	_surface_queued = false
	var world := get_parent()
	if not world or not world.has_node("Homestead"): return
	var terrain: Terrain = world.get_node("Homestead")
	var edge_values := {"grass_lip_pixels": 4.0, "grass_edge_variation": 3.0, "grass_transition_height": 0.22,
		"grass_moss_strength": 0.5, "grass_lip_shadow": 0.1, "grass_base_blend_height": 0.22,
		"surface_edge_normal_softening": 0.5}
	if _edge_original.is_empty():
		for key in edge_values: _edge_original[key] = terrain.get(key)
	for key in edge_values: terrain.set(key,edge_values[key] if edge_blending_enabled else _edge_original[key])
	for material in [terrain.top_material,terrain.wall_material]:
		if not material: continue
		material.set_shader_parameter("surface_normals_enabled",surface_normals_enabled)
		material.set_shader_parameter("surface_normal_strength",surface_normal_strength)
		material.set_shader_parameter("path_edge_blending_enabled",edge_blending_enabled)
		material.set_shader_parameter("path_edge_width",path_edge_width)
		material.set_shader_parameter("path_edge_strength",path_edge_strength)
	if terrain.wall_material is ShaderMaterial:
		var wall: ShaderMaterial = terrain.wall_material
		var normal := SurfaceNormalMaps.for_texture(wall.get_shader_parameter("wall_texture"))
		wall.set_shader_parameter("wall_normal_texture",normal)
		wall.set_shader_parameter("wall_normal_enabled",normal != null)
		wall.set_shader_parameter("edge_color_matching_enabled",edge_blending_enabled)
	for path in ["HouseSite/Home","TrainingHut"]:
		var building := world.get_node_or_null(path)
		if building:
			building.set("surface_normals_enabled",surface_normals_enabled)
			building.set("surface_normal_strength",surface_normal_strength)
	var sprite := world.get_node_or_null("Player/Sprite")
	if sprite:
		sprite.set("normal_mapping_enabled",character_normals_enabled)
		sprite.set("normal_mapping_strength",character_normal_strength)

func _ready() -> void:
	if color_palette and not color_palette.changed.is_connected(_queue_color_apply):
		color_palette.changed.connect(_queue_color_apply)
	var terrain := get_parent().get_node_or_null("Homestead") as Terrain
	if terrain and not terrain.paint_palette_applied.is_connected(_on_palette_applied):
		terrain.paint_palette_applied.connect(_on_palette_applied)
	apply_vegetation_sample.call_deferred()
	apply_pixel_art.call_deferred()
	apply_style.call_deferred()
	apply_surface_details.call_deferred()

func _on_palette_applied() -> void:
	# 画笔可在启动或编辑后延迟刷新；保留当前风格受光，避免覆盖回画笔默认色。
	var terrain := get_parent().get_node_or_null("Homestead") as Terrain
	if terrain: _ensure_smooth_grass_brush(terrain)
	var preset: SpawnVisualPreset = [ORIGINAL, DAY, RAIN, NIGHT][style]
	_palette(_merged_values(ORIGINAL.palette_values, preset.palette_values))
	apply_grass_variation()
	apply_surface_details()

func _queue_grass_variation_apply() -> void:
	if not is_inside_tree() or _grass_variation_queued: return
	_grass_variation_queued = true
	apply_grass_variation.call_deferred()

func apply_grass_variation() -> void:
	_grass_variation_queued = false
	var world := get_parent()
	var terrain := world.get_node_or_null("Homestead") as Terrain if world else null
	if not terrain or not terrain.top_material: return
	# 已打开的 @tool 实例热更新时可能没有重新执行 _ready，新导出项也可能仍为 Nil。
	if Engine.is_editor_hint():
		var defaults := {"grass_variation_enabled": true, "grass_variation_strength": 0.16, "grass_variation_size": 1.0 / 0.38}
		for name in defaults:
			if get(name) == null: set(name, defaults[name])
		_editor_grass_preview_initialized = true
	for material in [terrain.top_material,terrain.wall_material]:
		if not material: continue
		material.set_shader_parameter("grass_variation_enabled", grass_variation_enabled)
		material.set_shader_parameter("grass_variation_strength", grass_variation_strength)
		material.set_shader_parameter("grass_variation_size", grass_variation_size)

func _queue_vegetation_apply() -> void:
	if not is_inside_tree() or _vegetation_queued: return
	_vegetation_queued = true
	apply_vegetation_sample.call_deferred()

func apply_vegetation_sample() -> void:
	_vegetation_queued = false
	var dressing := get_parent().get_node_or_null("GroundDressing")
	if not dressing or not vegetation_preset: return
	var values: Dictionary = vegetation_preset.node_values.get("GroundDressing", {})
	if _vegetation_original.is_empty():
		for key in values: _vegetation_original[key] = dressing.get(key)
	for key in values if vegetation_sample_enabled else _vegetation_original:
		dressing.set(key, values[key] if vegetation_sample_enabled else _vegetation_original[key])
	if value_sample_enabled and vegetation_sample_enabled and value_sample_profile:
		dressing.color_palette = value_sample_profile.foliage_palette
	apply_color_ramps()

func _grass_color_center() -> Color:
	if _grass_center_cached: return _grass_center
	var source: Image = _pixel_texture("grass").get_image().duplicate()
	if source.is_compressed(): source.decompress()
	var sum := Vector3.ZERO
	for y in source.get_height():
		for x in source.get_width():
			var color := source.get_pixel(x, y).srgb_to_linear()
			sum += Vector3(color.r, color.g, color.b)
	sum /= float(source.get_width() * source.get_height())
	_grass_center = Color(sum.x, sum.y, sum.z).linear_to_srgb()
	_grass_center_cached = true
	return _grass_center

func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not runtime_switch_enabled: return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.alt_pressed or event.ctrl_pressed or event.meta_pressed or event.shift_pressed: return
	var code: Key = event.physical_keycode if event.physical_keycode else event.keycode
	if code != style_key: return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return
	for blocker in get_tree().get_nodes_in_group(&"gameplay_input_blockers"):
		# 隐藏结算界面仍有结果状态保护；允许玩家在结算后继续比较画面。
		if blocker is not WavePrototype: return
	style = (style + 1) % STYLE_NAMES.size()
	get_viewport().set_input_as_handled()

func _visual_property(path: String, property: String) -> bool:
	if path in ["MapEffects/ArtDirection", "Player/Sprite"]: return true
	if path == "MapEffects/Weather": return property in ["weather_mode", "rain_amount", "rain_intensity"]
	if path == "MapEffects/AtmosphericLight": return property in ["distant_enabled", "light_color", "map_accents_enabled", "surface_energy", "follow_global_direction"]
	if path == "MapEffects/DaylightPreview": return property == "enabled"
	# 投影轮廓和湿草地亮斑独立保留，切光影不重设用户选择。
	if path == "GroundDressing": return property in ["lighting_enabled", "normal_strength", "root_occlusion", "backlight_strength", "ground_relief", "ground_wet_response"]
	if path in ["HouseSite/Home", "TrainingHut"]: return property.begins_with("lumina_") or property.begins_with("window_glow_")
	return false

func _merged_values(base: Dictionary, override: Dictionary) -> Dictionary:
	var values := base.duplicate(true)
	for path in override:
		if not values.has(path): values[path] = {}
		values[path].merge(override[path], true)
	return values

func _queue_apply() -> void:
	if not is_inside_tree() or _queued: return
	_queued = true
	apply_style.call_deferred()

func _queue_pixel_apply() -> void:
	if not is_inside_tree() or _pixel_queued: return
	_pixel_queued = true
	apply_pixel_art.call_deferred()

func _queue_color_apply() -> void:
	if not is_inside_tree() or _color_queued: return
	_color_queued = true
	apply_color_ramps.call_deferred()

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		if not _editor_grass_preview_initialized: apply_grass_variation()
		return
	if style == 0 or not follow_weather or _queued: return
	var weather := get_parent().get_node_or_null("MapEffects/Weather")
	if weather and _weather_mode != weather.weather_mode:
		style = 2 if weather.weather_mode == 1 else 3 if style == 3 else 1

func _nodes(values: Dictionary) -> void:
	for path in values:
		var node := get_parent().get_node_or_null(NodePath(path))
		if not node: continue
		for name in values[path]:
			if not _visual_property(path, name): continue
			var value: Variant = values[path][name]
			var current: Variant = node.get(name)
			if current == value: continue
			if current is Array and current.is_typed() and value is Array:
				current = current.duplicate()
				current.assign(value)
				value = current
			node.set(name, value)

func _materials(values: Dictionary) -> void:
	var terrain: Terrain = get_parent().get_node("Homestead")
	for key in values:
		var material: ShaderMaterial = terrain.top_material if key == "ground" else terrain.wall_material if key == "wall" else get_parent().get_node("MapEffects/PostProcess/Screen").material
		for name in values[key]:
			# 地图坐标和生成纹理由 Terrain / Farming / Weather 维护，不能用快照默认值覆盖 RID 绑定。
			if name in ["map_origin", "cell_size", "terrain_map", "paint_enabled", "path_configured", "path_grid", "path_tiles", "paint_textures", "paint_settings", "farming_map", "farming_enabled", "rain_clock", "grass_root_map", "grass_root_bounds"]: continue
			# 草根及草地受光由 GroundDressing 维护，不再由历史材质快照重复覆盖。
			if key == "ground" and name in ["grass_lighting_enabled", "grass_relief", "grass_root_occlusion", "grass_sheen", "grass_wet_response"]: continue
			material.set_shader_parameter(name, values[key][name])

func _palette(values: Dictionary) -> void:
	var terrain: Terrain = get_parent().get_node("Homestead")
	# Style 只写受光，不修改画笔编号、贴图或铺设规则，不触发花草重建。
	for index in [0, 1]:
		if not values.has(index) or index >= terrain.paint_palette.brushes.size(): continue
		var brush := terrain.paint_palette.brushes[index]
		var prefix := "wild" if brush.target == TerrainPaintBrush.Target.GRASS else "path"
		var settings: Dictionary = values[index]
		terrain.top_material.set_shader_parameter(prefix + "_tint", settings.get("tint", brush.tint))
		terrain.top_material.set_shader_parameter(prefix + "_surface", Vector3(settings.get("roughness", brush.roughness), settings.get("metallic", brush.metallic), settings.get("wet_response", brush.wet_response)))
	_apply_smooth_grass_materials(terrain)
	terrain._apply_grass_transition()

func _isolate_palette(terrain: Terrain) -> void:
	if _isolated: return
	# 调色与贴图覆盖只影响此地图实例，不写回画笔源文件或种植存档。
	terrain.paint_palette = terrain.paint_palette.duplicate(true)
	# 编辑器已保存新贴图时，旧材质基线仍来自原画笔；只恢复已知样板覆盖，不改固定编号。
	var source: TerrainPaintPalette = load("res://data/world/spawn_paint_palette.tres")
	for index in mini(terrain.paint_palette.brushes.size(), source.brushes.size()):
		var brush := terrain.paint_palette.brushes[index]
		if brush.texture and (brush.texture.resource_path.begins_with(PIXEL_SAMPLE_PATH) or brush.texture.resource_path.begins_with(SMOOTH_GRASS_PATH)):
			var restore_normal := brush.target == TerrainPaintBrush.Target.GRASS and brush.texture.resource_path.begins_with(SMOOTH_GRASS_PATH)
			for property in ["texture", "mode", "atlas_grid", "atlas_tile", "corner_tiles"]:
				brush.set(property, source.brushes[index].get(property))
			if restore_normal:
				brush.normal_texture = source.brushes[index].normal_texture
				brush.normal_strength = source.brushes[index].normal_strength
	for building in [get_parent().get_node_or_null("HouseSite/Home"), get_parent().get_node_or_null("TrainingHut")]:
		if not is_instance_valid(building): continue
		for property in ["plaster_texture_override", "roof_texture_override"]:
			var texture: Texture2D = building.get(property)
			if texture and texture.resource_path.begins_with(PIXEL_SAMPLE_PATH): building.set(property, null)
	_isolated = true

func _restore_pixel_materials() -> void:
	for brush in _pixel_brush_values:
		for name in _pixel_brush_values[brush]: brush.set(name, _pixel_brush_values[brush][name])
	_pixel_brush_values.clear()
	for building in _pixel_building_values:
		for name in _pixel_building_values[building]: building.set(name, _pixel_building_values[building][name])
	_pixel_building_values.clear()

func _pixel_texture(filename: String) -> Texture2D:
	var path := PIXEL_SAMPLE_PATH + filename + ".png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

func _smooth_grass_texture(filename: String) -> Texture2D:
	var path := SMOOTH_GRASS_PATH + filename + ".png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

func _override_pixel_brush(brush: TerrainPaintBrush, texture: Texture2D, mode: TerrainPaintBrush.Mode) -> void:
	if not texture: return
	if not _pixel_brush_values.has(brush):
		_pixel_brush_values[brush] = {
			"texture": brush.texture, "normal_texture": brush.normal_texture,
			"normal_strength": brush.normal_strength, "mode": brush.mode, "tint": brush.tint,
			"atlas_grid": brush.atlas_grid, "atlas_tile": brush.atlas_tile,
			"corner_tiles": brush.corner_tiles.duplicate()
		}
	brush.texture = texture
	brush.mode = mode
	brush.tint = Color.WHITE
	brush.atlas_grid = Vector2i(4, 4) if mode == TerrainPaintBrush.Mode.CORNER_ATLAS else Vector2i.ONE
	brush.atlas_tile = Vector2i.ZERO
	if mode == TerrainPaintBrush.Mode.CORNER_ATLAS:
		brush.corner_tiles = PackedVector2Array(TerrainPaintBrush.MEOWA_TILES)

func _ensure_smooth_grass_brush(terrain: Terrain) -> void:
	if not smooth_grass_enabled or not terrain.paint_palette: return
	_isolate_palette(terrain)
	var albedo := _smooth_grass_texture("grass_albedo")
	var normal := _smooth_grass_texture("grass_normal_gl")
	if not albedo or not normal or albedo.get_size() != normal.get_size(): return
	for brush in terrain.paint_palette.brushes:
		if not brush or brush.target != TerrainPaintBrush.Target.GRASS: continue
		# Resource setters queue a palette refresh. Only write changes so its callback settles.
		if brush.texture != albedo or brush.mode != TerrainPaintBrush.Mode.TEXTURE or brush.tint != Color.WHITE:
			_override_pixel_brush(brush, albedo, TerrainPaintBrush.Mode.TEXTURE)
		elif not _pixel_brush_values.has(brush):
			# Preserve explicit normals even when the albedo already matches the new sample.
			_override_pixel_brush(brush, albedo, TerrainPaintBrush.Mode.TEXTURE)
		if brush.normal_texture != normal: brush.normal_texture = normal
		if brush.normal_strength != 1.0: brush.normal_strength = 1.0

func _apply_smooth_grass_materials(terrain: Terrain) -> void:
	var albedo := _smooth_grass_texture("grass_albedo") if smooth_grass_enabled else null
	var normal := _smooth_grass_texture("grass_normal_gl") if smooth_grass_enabled else null
	var dry := _smooth_grass_texture("grass_orm_dry") if smooth_grass_enabled else null
	var wet := _smooth_grass_texture("grass_orm_wet") if smooth_grass_enabled else null
	var enabled := smooth_grass_enabled and albedo != null and normal != null and dry != null and wet != null
	for material in [terrain.top_material, terrain.wall_material]:
		if not material: continue
		if material.get_shader_parameter("smooth_grass_enabled") != enabled:
			material.set_shader_parameter("smooth_grass_enabled", enabled)
		if not enabled: continue
		if material.get_shader_parameter("smooth_grass_orm_dry") != dry:
			material.set_shader_parameter("smooth_grass_orm_dry", dry)
		if material.get_shader_parameter("smooth_grass_orm_wet") != wet:
			material.set_shader_parameter("smooth_grass_orm_wet", wet)
		if material.get_shader_parameter("wild_tint") != Color.WHITE:
			material.set_shader_parameter("wild_tint", Color.WHITE)

func _apply_pixel_materials(terrain: Terrain) -> void:
	if not pixel_art_enabled and not smooth_grass_enabled: return
	var grass := _pixel_texture("grass")
	var path := _pixel_texture("path")
	var cobble := _pixel_texture("cobble")
	var original_path: Texture2D
	for brush in terrain.paint_palette.brushes:
		if brush.target == TerrainPaintBrush.Target.PATH: original_path = brush.texture
	for brush in terrain.paint_palette.brushes:
		if brush.target == TerrainPaintBrush.Target.GRASS:
			if pixel_art_enabled and not smooth_grass_enabled:
				_override_pixel_brush(brush, grass, TerrainPaintBrush.Mode.TEXTURE)
		elif pixel_art_enabled and brush.target == TerrainPaintBrush.Target.PATH:
			_override_pixel_brush(brush, path, TerrainPaintBrush.Mode.CORNER_ATLAS)
		elif pixel_art_enabled and original_path and brush.texture == original_path and brush.mode == TerrainPaintBrush.Mode.ATLAS_TILE:
			_override_pixel_brush(brush, cobble, TerrainPaintBrush.Mode.TEXTURE)
	_ensure_smooth_grass_brush(terrain)
	if not pixel_art_enabled: return
	var plaster := _pixel_texture("plaster")
	var roof := _pixel_texture("roof")
	if not plaster and not roof: return
	var ramp := color_palette.palette_texture() if color_ramps_enabled and color_palette else null
	for building in [get_parent().get_node_or_null("HouseSite/Home"), get_parent().get_node_or_null("TrainingHut")]:
		if not is_instance_valid(building): continue
		_pixel_building_values[building] = {
			"plaster_texture_override": building.get("plaster_texture_override"),
			"roof_texture_override": building.get("roof_texture_override"),
			"override_texture_meters": building.get("override_texture_meters"),
			"override_relief_sample_pixels": building.get("override_relief_sample_pixels"),
			"override_roof_contrast": building.get("override_roof_contrast"),
			"override_palette_texture": building.get("override_palette_texture")
		}
		if plaster: building.set("plaster_texture_override", plaster)
		if roof: building.set("roof_texture_override", roof)
		building.set("override_texture_meters", pixel_building_texture_meters)
		building.set("override_relief_sample_pixels", 1.0)
		building.set("override_roof_contrast", pixel_roof_contrast)
		building.set("override_palette_texture", ramp)

func _apply_color_ramps(terrain: Terrain) -> void:
	var enabled := pixel_art_enabled and color_ramps_enabled and color_palette != null
	var ramp := color_palette.palette_texture() if enabled else null
	for material in [terrain.top_material, terrain.wall_material]:
		material.set_shader_parameter("pixel_palette_enabled", enabled and ramp != null)
		material.set_shader_parameter("pixel_palette_texture", ramp)
		material.set_shader_parameter("pixel_stone_detail_strength", pixel_stone_detail_strength if pixel_art_enabled else 1.0)
		material.set_shader_parameter("pixel_grass_contrast", pixel_grass_contrast if pixel_art_enabled and vegetation_sample_enabled and not smooth_grass_enabled else 1.0)
		material.set_shader_parameter("pixel_grass_center", _grass_color_center())
	_apply_smooth_grass_materials(terrain)
	apply_grass_variation()

func apply_color_ramps() -> void:
	_color_queued = false
	var world := get_parent()
	if not world or not world.has_node("Homestead"): return
	var terrain: Terrain = world.get_node("Homestead")
	_apply_color_ramps(terrain)
	var enabled := pixel_art_enabled and color_ramps_enabled and color_palette != null
	var ramp := color_palette.palette_texture() if enabled else null
	for building in [world.get_node_or_null("HouseSite/Home"), world.get_node_or_null("TrainingHut")]:
		if not is_instance_valid(building): continue
		building.set("override_palette_texture", ramp)

func apply_pixel_art() -> void:
	_pixel_queued = false
	if not is_inside_tree(): return
	var world := get_parent()
	if not world or not world.has_node("Homestead"): return
	var terrain: Terrain = world.get_node("Homestead")
	_isolate_palette(terrain)
	_restore_pixel_materials()
	_apply_pixel_materials(terrain)
	_apply_color_ramps(terrain)
	terrain._apply_paint_palette()
	terrain.refresh_surface()
	apply_style()

func apply_style() -> void:
	_queued = false
	if not is_inside_tree(): return
	var world := get_parent()
	if not world or not world.has_node("MapEffects") or not world.has_node("Homestead"): return
	var terrain: Terrain = world.get_node("Homestead")
	_isolate_palette(terrain)
	var preset: SpawnVisualPreset = [ORIGINAL, DAY, RAIN, NIGHT][clampi(style, 0, 3)]
	_nodes({"MapEffects/ArtDirection": FOG_POST_DEFAULTS})
	_nodes(_merged_values(ORIGINAL.node_values, preset.node_values))
	if style == 0: _nodes(ORIGINAL_RENDER.node_values)
	if style == 0 and original_light_refinement_enabled and original_light_preset:
		_nodes(original_light_preset.node_values)
	if value_sample_enabled and value_sample_profile and style < value_sample_profile.lighting_presets.size():
		var value_preset := value_sample_profile.lighting_presets[style]
		if value_preset: _nodes(value_preset.node_values)
	if fog_post_enabled and style < fog_post_presets.size() and fog_post_presets[style]:
		_nodes(fog_post_presets[style].node_values)
	_apply_value_palettes()
	_materials(_merged_values(ORIGINAL.shader_values, preset.shader_values))
	world.get_node("MapEffects/PostProcess/Screen").material.set_shader_parameter("lumina_grade_enabled", style > 0)
	for material in [terrain.top_material, terrain.wall_material]: material.set_shader_parameter("lumina_relief_enabled", style > 0)
	_weather_mode = world.get_node("MapEffects/Weather").weather_mode
	world.get_node("MapEffects/ArtDirection").apply()
	world.get_node("MapEffects/Weather")._apply()
	_apply_color_ramps(terrain)
	_palette(_merged_values(ORIGINAL.palette_values, preset.palette_values))
	_update_window_lights()
	apply_surface_details()
	style_changed.emit(style, STYLE_NAMES[style])

func _update_window_lights() -> void:
	var home := get_parent().get_node_or_null("HouseSite/Home") as Node3D
	if not home: return
	if _window_lights.is_empty():
		for index in 2:
			var lamp := OmniLight3D.new()
			lamp.name = "SampleWindowLight%d" % index
			lamp.omni_range = 5.0
			lamp.omni_attenuation = 1.4
			lamp.light_color = Color(1.0, 0.66, 0.3)
			lamp.shadow_enabled = true
			lamp.light_size = 0.15
			add_child(lamp)
			_window_lights.append(lamp)
	for index in 2:
		var lamp := _window_lights[index]
		lamp.visible = style > 0
		lamp.light_energy = 0.15 if style == 1 else 0.55 if style == 2 else 1.3
		lamp.global_position = home.to_global(Vector3(-1.8 if index == 0 else 1.8, 1.8, 2.65))
