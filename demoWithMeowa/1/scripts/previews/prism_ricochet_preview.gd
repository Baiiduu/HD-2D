extends Node3D

## 独立视觉场地；加载正式地表和实际相机，不保存布局或人物数据。
@export_range(1, 8, 1) var preview_level := 4
@onready var world: Node3D = $CurrentWorld
@onready var wave: WavePrototype = $CurrentWorld/WavePrototype
@onready var attack: PrismRicochetAutoAttack = $CurrentWorld/WavePrototype/PrismRicochetAutoAttack

func _enter_tree() -> void:
	$CurrentWorld/LoadoutUI.save_enabled = false
	load("res://scripts/previews/prop_preview_stage.gd").prepare($CurrentWorld)
	$CurrentWorld/WavePrototype/RunGrowth.enabled = false
	$CurrentWorld/WavePrototype/FanAutoAttack.enabled = false
	$CurrentWorld/WavePrototype/LightPierceAutoAttack.enabled = false

func _ready() -> void:
	while not wave._path_ready: await get_tree().physics_frame
	var player: Player = world.get_node("Player")
	player.global_position = wave._path.ground_position(Vector3(-4, 0, 42)) + Vector3.UP * 0.03
	player.reset_physics_interpolation()
	wave.set_physics_process(false)
	wave.phase = WavePrototype.Phase.BATTLE
	world.get_node("LoadoutUI").hide()
	wave.get_node("WaveHUD").hide()
	wave.get_node("RunGrowth/ExperienceHUD").hide()
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	camera.snap_to_target.call_deferred()
	for point in [Vector3(-1.5, 0, 42), Vector3(0.35, 0, 40.1), Vector3(-4.5, 0, 41)]:
		var slime: WaveEnemy = load("res://scenes/enemies/slime.tscn").instantiate()
		slime.wave_mode = true
		slime.spawn_delay = 0.0
		slime.health = 100000.0
		slime.collision_layer = 2
		slime.terrain = wave.terrain
		slime.target = player
		slime.wave_target = player
		slime.camera = camera
		slime.navigation = wave._path
		slime.combat_active = wave.combat_active
		world.add_child(slime)
		slime.global_position = wave._path.ground_position(point)
		slime.set_physics_process(false)
		wave.enemies.append(slime)
	attack.apply_skill_level(preview_level)
	var args := OS.get_cmdline_user_args()
	if "--capture-prism" in args:
		_capture(args[args.find("--capture-prism") + 1])

func _capture(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var player: Player = world.get_node("Player")
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	player.set_physics_process(false)
	attack.audio_enabled = false
	AudioServer.set_bus_mute(0, true)
	for frame in 90: await get_tree().process_frame
	camera.snap_to_target()
	print("Prism camera: FOV=", camera.fov, " distance=", camera.distance, " pitch=", camera.pitch_degrees, " DOF enabled=", camera.dof_enabled)
	var bounces := [0]
	attack.wall_bounced.connect(func(_point, _normal): bounces[0] += 1)
	for level in [1, 4, 8]:
		attack.cancel_current()
		attack.apply_skill_level(level)
		attack._cooldown = 0.0
		# 正面静态图保持相同取景，只改变技能等级。
		for frame in 27: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(directory.path_join("level-%d.png" % level))
	attack.cancel_current()
	attack._cooldown = 0.0
	DirAccess.make_dir_recursive_absolute(directory.path_join("frames"))
	for frame in 192:
		await get_tree().process_frame
		if frame % 2 == 0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(directory.path_join("frames/%04d.png" % (frame / 2)))
	print("Prism preview wall reflections: ", bounces[0])
	get_tree().quit()
