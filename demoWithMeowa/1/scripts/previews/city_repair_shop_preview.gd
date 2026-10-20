extends Node3D
## 维修铺 UV 与贴图验收，沿用正式镜头标尺。

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
	focus.global_position = $Samples/CityRepairShop.global_position + Vector3.UP * 0.85
	camera.distance = 12.0
	camera.snap_to_target()
	$ReviewUI/Panel/Margin/Rows/CurrentView.text = "近看修理铺与天窗 · 12m，仅用于检查结构"
