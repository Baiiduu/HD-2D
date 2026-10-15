@tool
class_name CityPlaza
extends Node3D

## 东侧平面广场。只组合 Meowa 原像素切片；真实地面和碰撞仍属于连续 Terrain。
const DATA_PATH := "res://data/world/world_terrain.tres"
const WEATHER_PARAMETERS := [&"wetness", &"weather_wetness", &"rain_amount", &"rain_clock",
	&"rain_density", &"rain_radius", &"rain_strength", &"lumina_relief_enabled",
	&"lumina_tone_strength", &"lumina_matte_floor"]

@export_group("地图连接")
@export var terrain: Terrain
@export var surface_material: ShaderMaterial
## X/Z 尺寸，米。地形重建才改变真实地面；铺装预览即时更新。
@export var area_size := Vector2(38.4, 38.4):
	set(value): area_size = value.max(Vector2(6.4, 6.4)); _queue_refresh()
## 连接路西端的地形 X 坐标，米；广场中心为本节点位置。
@export var connection_start_x := 24.8:
	set(value): connection_start_x = value; _queue_refresh()
@export_range(3.2, 12.8, 1.6, "suffix:m") var connection_width := 6.4:
	set(value): connection_width = value; _queue_refresh()
## 广场周围保持平整的草地缓冲，不增加台地。
@export_range(0.0, 16.0, 1.6, "suffix:m") var flat_margin := 8.0
## 可见外围留地，保持开发镜头与 Q/E 旋转的地面背景。
@export_range(16.0, 40.0, 1.6, "suffix:m") var scenery_margin := 28.0
@export_tool_button("重建东侧广场地面", "Reload") var rebuild_button = rebuild_terrain
@export_tool_button("保存连续地形", "Save") var save_button = save_terrain

@export_group("铺装结构")
## 约 100 像素的石板切片覆盖 2.4 米，约 41 像素/米。只调显示尺度，不修改原图。
@export_range(1.2, 4.8, 0.05, "suffix:m") var texture_meters := 2.4:
	set(value): texture_meters = value; _queue_refresh()
## 深色分区带的间距，米；每个大区约八块小石板。
@export_range(3.2, 12.8, 0.1, "suffix:m") var division_spacing := 6.4:
	set(value): division_spacing = value; _queue_refresh()
@export_range(0.2, 1.0, 0.025, "suffix:m") var division_width := 0.5:
	set(value): division_width = value; _queue_refresh()
@export_range(0.025, 0.15, 0.025, "suffix:m") var trim_width := 0.05:
	set(value): trim_width = value; _queue_refresh()
@export_range(2.4, 6.4, 0.1, "suffix:m") var octagon_size := 4.0:
	set(value): octagon_size = value; _queue_refresh()
## 固定且稀疏的磨损与暗菱形位置，不随光影或天气变化。
@export_range(0.0, 0.5, 0.01) var wear_density := 0.07:
	set(value): wear_density = value; _queue_refresh()
@export_range(0.0, 0.3, 0.01) var inlay_density := 0.025:
	set(value): inlay_density = value; _queue_refresh()
@export var ornament_seed := 13102026:
	set(value): ornament_seed = value; _queue_refresh()

@export_group("材质受光")
## 浅凹凸仅改变受光，地面仍平整；法线从同尺寸切片准备。
@export_range(0.0, 1.5, 0.05) var normal_strength := 0.6:
	set(value): normal_strength = value; _queue_refresh()
@export_range(0.3, 1.0, 0.01) var roughness := 0.78:
	set(value): roughness = value; _queue_refresh()
@export_range(0.0, 1.0, 0.01) var wet_response := 0.8:
	set(value): wet_response = value; _queue_refresh()

var _material: ShaderMaterial
var _surface: MeshInstance3D
var _connection: MeshInstance3D
var _queued := false
var _weather_values := {}
var _map_texture: Texture2D

func _ready() -> void:
	_refresh()

func _process(_delta: float) -> void:
	if not _material or not terrain or not terrain.data: return
	if terrain._map_texture != _map_texture:
		_map_texture = terrain._map_texture
		_material.set_shader_parameter("terrain_map", _map_texture)
		_material.set_shader_parameter("map_origin", terrain.data.origin)
		_material.set_shader_parameter("cell_size", terrain.data.cell_size)
	if not terrain.top_material: return
	for parameter in WEATHER_PARAMETERS:
		var value: Variant = terrain.top_material.get_shader_parameter(parameter)
		if value != null and _weather_values.get(parameter) != value:
			_material.set_shader_parameter(parameter, value)
			_weather_values[parameter] = value

func _center() -> Vector2:
	var point := terrain.to_local(global_position) if terrain and is_inside_tree() else position
	return Vector2(point.x, point.z)

func get_core_rect() -> Rect2:
	return Rect2(_center() - area_size * 0.5, area_size)

func get_connection_rect() -> Rect2:
	var core := get_core_rect()
	return Rect2(connection_start_x, core.get_center().y - connection_width * 0.5,
		maxf(0.0, core.position.x - connection_start_x), connection_width)

func get_flat_rect() -> Rect2:
	return get_core_rect().grow(flat_margin)

## 显式生成：保留已有数据，只平整广场和连接路；加载场景不重写用户绘制。
func make_terrain(source: TerrainData) -> TerrainData:
	var result := source.duplicate(true) as TerrainData
	var bounds := source.get_world_rect().merge(get_core_rect().grow(scenery_margin))
	var first := Vector2i((bounds.position / result.cell_size + Vector2.ONE * 0.5).floor())
	var last := Vector2i((bounds.end / result.cell_size - Vector2.ONE * 0.5).ceil())
	result.resize(first, last - first + Vector2i.ONE)
	var core := get_core_rect()
	var connection := get_connection_rect()
	var flat := get_flat_rect()
	for z in result.size.y:
		for x in result.size.x:
			var cell := result.origin + Vector2i(x, z)
			var index := z * result.size.x + x
			var point := Vector2(cell) * result.cell_size
			if not source.has_cell(cell): result.biomes[index] = TerrainData.Biome.WILD
			if flat.has_point(point) or connection.has_point(point):
				result.heights[index] = TerrainData.HEIGHT_OFFSET
				result.overlays[index] &= ~(TerrainData.OVERLAY_RAMP | TerrainData.OVERLAY_WATER | TerrainData.OVERLAY_BRIDGE)
			if core.has_point(point) or connection.has_point(point):
				result.biomes[index] = TerrainData.Biome.CITY
				result.overlays[index] = 0
				result.paints[index] = 0
	return result

func rebuild_terrain() -> void:
	if not terrain or not terrain.data: return
	terrain.data = make_terrain(terrain.data)
	_refresh()
	var effects := get_parent().get_node_or_null("MapEffects")
	if effects: effects.connect_map()

func save_terrain() -> void:
	if not Engine.is_editor_hint() or not terrain or not terrain.data: return
	var uid := ResourceLoader.get_resource_uid(DATA_PATH)
	var error := ResourceSaver.save(terrain.data, DATA_PATH, ResourceSaver.FLAG_CHANGE_PATH)
	if error == OK and uid != ResourceUID.INVALID_ID: error = ResourceSaver.set_uid(DATA_PATH, uid)
	if error != OK: push_error("广场地形保存失败：" + error_string(error))

func _queue_refresh() -> void:
	if not is_inside_tree() or _queued: return
	_queued = true
	_refresh.call_deferred()

func _plane(label: String, rect: Rect2, node: MeshInstance3D) -> MeshInstance3D:
	if not node:
		node = MeshInstance3D.new()
		node.name = label
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
	var mesh := PlaneMesh.new()
	mesh.size = rect.size.max(Vector2(0.001, 0.001))
	node.mesh = mesh
	node.material_override = _material
	var center := rect.get_center() - _center()
	node.position = Vector3(center.x, 0.006, center.y)
	node.visible = rect.has_area()
	return node

func _refresh() -> void:
	_queued = false
	if not is_inside_tree() or not surface_material: return
	_material = surface_material.duplicate() as ShaderMaterial
	_weather_values.clear()
	_map_texture = null
	_material.set_shader_parameter("plaza_center", _center())
	_material.set_shader_parameter("plaza_half_size", area_size * 0.5)
	for parameter in [&"texture_meters", &"division_spacing", &"division_width", &"trim_width", &"octagon_size",
		&"wear_density", &"inlay_density", &"ornament_seed", &"normal_strength", &"roughness", &"wet_response"]:
		_material.set_shader_parameter(parameter, get(parameter))
	_surface = _plane("Paving", get_core_rect(), _surface)
	_connection = _plane("Connection", get_connection_rect(), _connection)
	_process(0.0)
