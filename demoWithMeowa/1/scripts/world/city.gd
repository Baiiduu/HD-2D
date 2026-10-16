@tool
extends Node3D
## 独立城市布局样板；布局数据及布局图对应 data/city_layout.json。

const WORLD_RECT := Rect2(-18, -18, 36, 36)

func get_world_rect() -> Rect2:
	return WORLD_RECT

func _ready() -> void:
	# 光影预览在编辑器中需要地图边界；玩家及跟随相机仅在运行时初始化。
	if Engine.is_editor_hint():
		return
	var player := $Player as Player
	player.global_position = $SpawnPoint.global_position
	player.reset_physics_interpolation()
	player.bounds = WORLD_RECT.grow(-0.5)
	var effects := $MapEffects as MapEffects
	effects.apply_camera_defaults = false
	var camera := effects.get_map_camera()
	camera.target = player
	camera.set_world_rect(WORLD_RECT)
	camera.snap_to_target()
	# Keep the authored activity bounds on the translated combat terrain.
	effects._update_boundary_collision(player.bounds, 0.0)
