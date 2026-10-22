extends Node3D

const PREVIEW_STAGE := preload("res://scripts/previews/prop_preview_stage.gd")

@onready var world: Node3D = $CurrentWorld
@onready var samples: Node3D = $CurrentWorld/RicochetVariantSamples

func _enter_tree() -> void:
	$CurrentWorld/LoadoutUI.save_enabled = false
	PREVIEW_STAGE.prepare($CurrentWorld)
	$CurrentWorld/WavePrototype/RunGrowth.enabled = false
	$CurrentWorld/WavePrototype/FanAutoAttack.enabled = false
	$CurrentWorld/WavePrototype.process_mode = Node.PROCESS_MODE_DISABLED

func _ready() -> void:
	for prop in samples.get_children(): prop.snap_to_ground()
	var player: Player = world.get_node("Player")
	player.global_position = Vector3(-7, 0.25, 40.4)
	player.reset_physics_interpolation()
	(world.get_node("MapEffects/Camera3D") as FollowCamera).snap_to_target.call_deferred()
	world.get_node("WavePrototype/WaveHUD").hide()
	var args := OS.get_cmdline_user_args()
	if "--capture-ricochet-variants" in args:
		_capture(args[args.find("--capture-ricochet-variants") + 1])

func _capture(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	var player: Player = world.get_node("Player")
	for frame in 90: await get_tree().process_frame
	player.set_physics_process(false)
	camera.set_process(false)
	print("Ricochet variants camera: FOV=", camera.fov, " distance=", camera.distance,
		" pitch=", camera.pitch_degrees, " focus=", camera.focus_height, " DOF=", camera.dof_amount)
	var viewpoints := [["passage", Vector3(-7, 0, 40.4)], ["angles", Vector3(7.5, 0, 40.4)],
		["pocket", Vector3(-7, 0, 55)], ["curves", Vector3(7.5, 0, 55.2)]]
	for item in viewpoints:
		player.global_position = item[1]
		player.reset_physics_interpolation()
		# 跟随目标通过插值取位置，换组后先等物理缓存更新，再绑定镜头。
		for frame in 3: await get_tree().physics_frame
		for view in [["front", 0.0], ["angle", 45.0]]:
			camera.yaw_degrees = view[1]
			camera.snap_to_target()
			await _save_frame(directory.path_join(item[0] + "-" + view[0] + ".png"))
	for angle: float in [90.0, 180.0]:
		camera.yaw_degrees = angle
		camera.snap_to_target()
		await _save_frame(directory.path_join("curves-" + str(int(angle)) + ".png"))
	var visual: SpawnVisualSample = world.get_node("VisualSample")
	for style_index in [3, 2]:
		visual.style = style_index
		for frame in 90: await get_tree().process_frame
		camera.yaw_degrees = 0.0
		camera.snap_to_target()
		await _save_frame(directory.path_join("curves-" + ("night" if style_index == 3 else "rain") + ".png"))
	print("Ricochet variant captures saved: ", directory)
	get_tree().quit()

func _save_frame(path: String) -> void:
	for frame in 12: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
