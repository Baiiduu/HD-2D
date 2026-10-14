@tool
class_name MapEffects
extends Node3D

## 独立地图的通用画面与音频。默认值来自当前视觉预览，不包含地图布局。
@export_group("地图连接")
## 留空时连接同一地图的 World/Ground 或 Ground；也可手动指定其他 Terrain。
@export var terrain: Terrain
## 非格子地形的材质来源，例如小院地表；提供地面、水面材质和水域节点。
@export var surface_source: Node3D
## 留空时连接同一地图的 Player。
@export var player: Node3D
## 留空时连接 World/GroundDressing 或 GroundDressing。
@export var dressing: Node3D
## 可指定地图已有的跟随相机；否则优先使用地图根节点的 Camera3D，再使用内置相机。
@export var map_camera: FollowCamera
## 开启时地图已有相机也使用预览的距离、俯角、旋转和景深基准；关闭后保留它自己的设置。
@export var apply_camera_defaults := true
@export_tool_button("连接地图节点", "Reload") var refresh_connections = connect_map

var _bound_data: TerrainData

func _enter_tree() -> void:
	connect_map()

func _ready() -> void:
	connect_map()
	_apply_effects.call_deferred()

func connect_map() -> void:
	if not is_inside_tree() or not get_parent():
		return
	var root := get_parent() as Node3D
	if not root or not has_node("ArtDirection"):
		return
	if not is_instance_valid(terrain):
		terrain = root.get_node_or_null("World/Ground") as Terrain
		if not terrain:
			terrain = root.get_node_or_null("Ground") as Terrain
	if not is_instance_valid(player):
		player = root.get_node_or_null("Player") as Node3D
	if not is_instance_valid(surface_source):
		surface_source = root.get_node_or_null("Homestead") as Node3D
	if not is_instance_valid(dressing):
		dressing = root.get_node_or_null("World/GroundDressing") as Node3D
		if not dressing:
			dressing = root.get_node_or_null("GroundDressing") as Node3D
		if not dressing and surface_source:
			dressing = surface_source.get_node_or_null("Flora") as Node3D
	if not is_instance_valid(map_camera):
		map_camera = root.get_node_or_null("Camera3D") as FollowCamera
	var camera := get_map_camera()
	var default_camera := $Camera3D as FollowCamera
	if camera != default_camera and apply_camera_defaults:
		for property in default_camera.get_script().get_script_property_list():
			if property.usage & PROPERTY_USAGE_EDITOR and property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				if property.name not in ["target", "post_process"]:
					camera.set(property.name, default_camera.get(property.name))
		camera.fov = default_camera.fov
		camera.far = default_camera.far
		camera.attributes = default_camera.attributes.duplicate() if default_camera.attributes else CameraAttributesPractical.new()
	default_camera.current = camera == default_camera
	default_camera.set_process(camera == default_camera)
	camera.current = true
	camera.target = player
	camera.post_process = $PostProcess/Screen
	if player is Player:
		(player as Player).movement_camera = camera
	var art := $ArtDirection as ArtDirection
	art.scene_root = root
	art.terrain = terrain
	art.surface_source = surface_source
	var weather := $Weather
	weather.player = player
	weather.camera = camera
	weather.terrain = terrain
	weather.surface_source = surface_source
	weather.dressing = dressing
	var reflection := $WaterReflection as PlanarWaterReflection
	reflection.terrain = terrain
	reflection.surface_source = surface_source
	reflection.source_camera = camera
	reflection.geometry_root = root
	if surface_source and surface_source.has_signal("surfaces_rebuilt") and not surface_source.is_connected("surfaces_rebuilt", _on_surfaces_rebuilt):
		surface_source.connect("surfaces_rebuilt", _on_surfaces_rebuilt)
	if _bound_data and _bound_data.changed.is_connected(_update_bounds):
		_bound_data.changed.disconnect(_update_bounds)
	_bound_data = terrain.data if terrain else null
	if _bound_data:
		_bound_data.changed.connect(_update_bounds)
	_update_bounds()
	if is_node_ready():
		_apply_effects.call_deferred()

func get_map_camera() -> FollowCamera:
	return map_camera if is_instance_valid(map_camera) else $Camera3D as FollowCamera

func _on_surfaces_rebuilt() -> void:
	if not Engine.is_editor_hint():
		$WaterReflection.rebuild()
	_apply_effects.call_deferred()

func _update_bounds() -> void:
	# FollowCamera / Player are runtime scripts; editor placeholders only store their exports.
	if Engine.is_editor_hint():
		return
	if not terrain or not terrain.data or terrain.data.size.x <= 0 or terrain.data.size.y <= 0:
		return
	var rect := terrain.get_world_rect()
	get_map_camera().set_world_rect(rect)
	if player is Player:
		(player as Player).bounds = rect.grow(-0.3)
	if not Engine.is_editor_hint() and get_map_camera().is_node_ready():
		get_map_camera().snap_to_target()

func _apply_effects() -> void:
	if not is_inside_tree():
		return
	$ArtDirection.apply()
	$Weather._apply()
	if not Engine.is_editor_hint():
		$WaterReflection.initialize()
