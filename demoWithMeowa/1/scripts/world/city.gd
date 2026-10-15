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
	player.bounds = WORLD_RECT.grow(-0.5)
	var effects := $MapEffects as MapEffects
	effects.apply_camera_defaults = false
	var camera := effects.get_map_camera()
	camera.target = player
	camera.fov = 28.0
	camera.distance = 28.0
	camera.pitch_degrees = 32.0
	camera.focus_height = 0.9
	camera.dof_mode = 0
	camera.dof_amount = 0.065
	camera.dof_near_margin = 3.0
	camera.dof_far_margin = 4.0
	camera.dof_near_transition = 2.5
	camera.dof_far_transition = 6.0
	camera.set_world_rect(WORLD_RECT)
	camera.snap_to_target()
