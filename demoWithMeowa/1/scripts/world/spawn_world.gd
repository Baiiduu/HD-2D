@tool
extends Node3D

## 正式出生区的摆放连接。台地几何由独立 TerrainData 和既有 Terrain 生成。
@export_group("场景连接与出生")
@export var ground: Terrain
@export var home: Node3D
@export var home_site: Marker3D
## 已接入地图的训练小屋，随所在台地的高度对齐。
@export var training_hut: Node3D
@export var spawn_point: Marker3D
@export var player: CharacterBody3D
@export_tool_button("对齐建筑与出生点", "Reload") var align_sites = _place_nodes
## 出生时脚底高于地面的距离，米；运行后通过物理接地。
@export_range(0.05, 1.0, 0.05) var spawn_lift := 0.25:
	set(value): spawn_lift = value; _place_nodes()

func _ready() -> void:
	if ground and ground.data and not ground.data.changed.is_connected(_place_nodes):
		ground.data.changed.connect(_place_nodes)
	_place_nodes()
	if not Engine.is_editor_hint() and player and spawn_point:
		player.global_position = spawn_point.global_position
		player.reset_physics_interpolation()
		$MapEffects.get_map_camera().snap_to_target.call_deferred()

func _place_nodes() -> void:
	if not is_inside_tree() or not ground or not ground.data:
		return
	if home and home_site:
		var cell := ground.data.world_to_cell(ground.to_local(home_site.global_position))
		home_site.global_position.y = ground.global_position.y + ground.data.get_level(cell) * ground.data.layer_height
		home.global_position = home_site.global_position
	if training_hut:
		var cell := ground.data.world_to_cell(ground.to_local(training_hut.global_position))
		training_hut.global_position.y = ground.global_position.y + ground.data.get_level(cell) * ground.data.layer_height
	if spawn_point:
		var cell := ground.data.world_to_cell(ground.to_local(spawn_point.global_position))
		spawn_point.global_position.y = ground.global_position.y + ground.data.get_level(cell) * ground.data.layer_height + spawn_lift
		if Engine.is_editor_hint() and player:
			player.global_position = spawn_point.global_position
