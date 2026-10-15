extends Node3D

const PREVIEW_STAGE := preload("res://scripts/previews/prop_preview_stage.gd")

@onready var world: Node3D = $CurrentWorld
@onready var samples: Node3D = $CurrentWorld/LandmarkSamples

func _enter_tree() -> void:
	$CurrentWorld/LoadoutUI.save_enabled = false
	PREVIEW_STAGE.prepare($CurrentWorld)
	$CurrentWorld/WavePrototype/RunGrowth.enabled = false
	$CurrentWorld/WavePrototype/FanAutoAttack.enabled = false
	$CurrentWorld/WavePrototype.process_mode = Node.PROCESS_MODE_DISABLED

func _ready() -> void:
	for path in ["ArmillaryMonument", "StreetlampLeft", "StreetlampRight", "TreePlanter"]:
		samples.get_node(path).snap_to_ground()
	var player: Player = world.get_node("Player")
	player.global_position = samples.get_node("ArmillaryMonument").global_position + Vector3(-2.9, 0.25, 4.1)
	player.reset_physics_interpolation()
	(world.get_node("MapEffects/Camera3D") as FollowCamera).snap_to_target.call_deferred()
	world.get_node("WavePrototype/WaveHUD").hide()
	var args := OS.get_cmdline_user_args()
	if "--capture-landmarks" in args:
		_capture(args[args.find("--capture-landmarks") + 1])

func _capture(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	for frame in 90: await get_tree().process_frame
	world.get_node("Player").set_physics_process(false)
	camera.set_process(false)
	print("Landmarks camera: FOV=", camera.fov, " distance=", camera.distance,
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
	print("Plaza landmarks captures saved: ", directory)
	get_tree().quit()

func _save_frame(path: String) -> void:
	for frame in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
