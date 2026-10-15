extends Node3D

const PREVIEW_STAGE := preload("res://scripts/previews/prop_preview_stage.gd")

## 实例化当前正式世界；只在本预览内增加一个可走近观察的树池。
@onready var world: Node3D = $CurrentWorld
@onready var planter: TreePlanter = $CurrentWorld/TreePlanterSample/TreePlanter

func _enter_tree() -> void:
	# Disable persistence before the instanced world's children run _ready().
	$CurrentWorld/LoadoutUI.save_enabled = false
	PREVIEW_STAGE.prepare($CurrentWorld)
	$CurrentWorld/WavePrototype/RunGrowth.enabled = false
	$CurrentWorld/WavePrototype/FanAutoAttack.enabled = false
	$CurrentWorld/WavePrototype.process_mode = Node.PROCESS_MODE_DISABLED

func _ready() -> void:
	var player: Player = world.get_node("Player")
	planter.snap_to_ground()
	var point := planter.global_position + Vector3(-2.1, 0.25, 2.6)
	var terrain: Terrain = world.get_node("Homestead")
	var cell := terrain.data.world_to_cell(terrain.to_local(point))
	point.y = terrain.global_position.y + terrain.data.get_level(cell) * terrain.data.layer_height + 0.25
	player.global_position = point
	player.reset_physics_interpolation()
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	camera.snap_to_target.call_deferred()
	world.get_node("WavePrototype/WaveHUD").hide()
	var args := OS.get_cmdline_user_args()
	if "--capture-planter" in args:
		_capture(args[args.find("--capture-planter") + 1])

func _capture(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	var player: Player = world.get_node("Player")
	for frame in 90: await get_tree().process_frame
	player.set_physics_process(false)
	camera.set_process(false)
	print("Tree planter camera: FOV=", camera.fov, " distance=", camera.distance,
		" pitch=", camera.pitch_degrees, " focus=", camera.focus_height, " DOF=", camera.dof_amount)
	for item in [["front", 0.0], ["angle", 45.0], ["side", 90.0], ["back", 180.0]]:
		camera.yaw_degrees = item[1]
		camera.snap_to_target()
		await _save_frame(directory.path_join(item[0] + ".png"))
	var visual: SpawnVisualSample = world.get_node("VisualSample")
	visual.style = 3
	for frame in 30: await get_tree().process_frame
	camera.yaw_degrees = 0.0
	camera.snap_to_target()
	await _save_frame(directory.path_join("night.png"))
	visual.style = 2
	for frame in 90: await get_tree().process_frame
	await _save_frame(directory.path_join("rain.png"))
	print("Tree planter captures saved: ", directory)
	get_tree().quit()

func _save_frame(path: String) -> void:
	for frame in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
