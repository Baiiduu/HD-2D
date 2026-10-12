@tool
extends Node3D

## 预览低光环境；运行时 N 切换。只影响本预览场景。
@export var low_light := false:
	set(value): low_light = value; _queue_lighting()
## 日间主光强度；夜间预览使用它的 15%。
@export_range(0.0, 3.0, 0.05) var sun_energy := 1.1:
	set(value): sun_energy = value; _queue_lighting()
## 日间环境补光；夜间预览使用它的 30%。
@export_range(0.0, 1.5, 0.05) var ambient_energy := 0.55:
	set(value): ambient_energy = value; _queue_lighting()

func _ready() -> void:
	apply_lighting()
	if Engine.is_editor_hint():
		return
	$Player.bounds = Rect2(-11, -11, 22, 22)
	var args := OS.get_cmdline_user_args()
	if "--capture-home" in args:
		_capture(args[args.find("--capture-home") + 1])

func _queue_lighting() -> void:
	if is_inside_tree():
		apply_lighting.call_deferred()

func apply_lighting() -> void:
	if not has_node("Sun") or not has_node("Environment"):
		return
	var environment: Environment = $Environment.environment
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	$Sun.light_energy = sun_energy * (0.15 if low_light else 1.0)
	$Sun.light_color = Color(0.62,0.72,1.0) if low_light else Color(1.0,0.91,0.78)
	environment.ambient_light_energy = ambient_energy * (0.3 if low_light else 1.0)
	environment.ambient_light_color = Color(0.33,0.42,0.64) if low_light else Color(0.77,0.82,0.91)
	environment.background_color = Color(0.025,0.035,0.055) if low_light else Color(0.16,0.19,0.23)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_N:
		low_light = not low_light

func _capture(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var camera: FollowCamera = $Camera3D
	camera.set_process(false)
	$Player.set_physics_process(false)
	$Player.position.y = 0.02
	for frame in 35:
		await get_tree().process_frame
	for item in [["front",0.0],["angle",35.0],["side",90.0],["back",180.0]]:
		camera.yaw_degrees = item[1]
		camera.snap_to_target()
		await _save_frame(directory.path_join(item[0]+".png"))
	low_light = true
	camera.yaw_degrees = 35.0
	camera.snap_to_target()
	await _save_frame(directory.path_join("night.png"))
	low_light = false
	for frame in 60:
		camera.yaw_degrees = float(frame) * 6.0
		camera.snap_to_target()
		await _save_frame(directory.path_join("turn-%03d.png" % frame))
	print("Home previews saved: " + directory)
	get_tree().quit()

func _save_frame(path: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
