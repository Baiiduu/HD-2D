extends Node3D
## 建筑材质验收：复用正式相机，近看只改变此预览的焦点和距离。

@onready var camera: FollowCamera = $Camera3D
@onready var focus: Node3D = $Focus

func _ready() -> void:
	$ReviewUI/Panel/Margin/Rows/Views/GameDistance.pressed.connect(_show_game_distance)
	$ReviewUI/Panel/Margin/Rows/Views/CloseView.pressed.connect(_show_close_view)
	_show_game_distance()

func _show_game_distance() -> void:
	focus.position = Vector3.ZERO
	camera.distance = 30.0
	camera.snap_to_target()
	$ReviewUI/Panel/Margin/Rows/CurrentView.text = "正式地图距离 · FOV 28° / 30m / 俯角 30.627°"

func _show_close_view() -> void:
	focus.global_position = $Samples/CityCafe.global_position + Vector3.UP * 0.85
	camera.distance = 12.0
	camera.snap_to_target()
	$ReviewUI/Panel/Margin/Rows/CurrentView.text = "近看咖啡馆与露台 · 12m，仅用于检查结构"
