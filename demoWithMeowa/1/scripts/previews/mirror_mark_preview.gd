extends Node3D

## 使用正式地图的障碍、灯光和实际镜头，只加入可反复观察的战斗靶。
@export_range(1, 4, 1) var preview_level := 1
@onready var world: Node3D = $CurrentWorld
@onready var wave: WavePrototype = $CurrentWorld/WavePrototype
@onready var attack: MirrorMarkAutoAttack = $CurrentWorld/WavePrototype/MirrorMarkAutoAttack
var _origin := Vector3.ZERO
var _reset_clock := 0.0
var _capturing := false

func _enter_tree() -> void:
	$CurrentWorld/LoadoutUI.save_enabled = false
	$CurrentWorld/WavePrototype/RunGrowth.enabled = false
	$CurrentWorld/WavePrototype/FanAutoAttack.enabled = false
	$CurrentWorld/WavePrototype/LightPierceAutoAttack.enabled = false
	$CurrentWorld/WavePrototype/PrismRicochetAutoAttack.enabled = false

func _ready() -> void:
	set_process(false)
	while not wave._path_ready: await get_tree().physics_frame
	var player: Player = world.get_node("Player")
	wave.set_physics_process(false)
	wave.phase = WavePrototype.Phase.BATTLE
	_origin = _find_clear_sample()
	player.global_position = _origin + Vector3.UP * 0.03
	player.reset_physics_interpolation()
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	camera.snap_to_target.call_deferred()
	world.get_node("LoadoutUI").hide()
	wave.get_node("WaveHUD").hide()
	wave.get_node("RunGrowth/ExperienceHUD").hide()
	_spawn_samples()
	attack.apply_skill_level(preview_level)
	var args := OS.get_cmdline_user_args()
	if "--capture-mirror" in args:
		_capturing = true
		_capture(args[args.find("--capture-mirror") + 1])
	else: set_process(true)

func _find_clear_sample() -> Vector3:
	var collision := ProjectileCollision.new()
	var space := get_world_3d().direct_space_state
	for z in [42, 40, 38, 36, 34, 32]:
		for x in [-5, -7, -3, 1, 3, -9]:
			var point := wave._path.ground_position(Vector3(x, 0, z))
			var points := [point, point + Vector3(2, 0, 0), point + Vector3(2, 0, -1.8), point + Vector3(4, 0, -1.8)]
			var clear := true
			for index in points.size():
				if wave._path._point_blocked(points[index]):
					clear = false
					break
				if index > 0 and not collision.wall_contact(space, points[index - 1] + Vector3.UP * 0.45, points[index] + Vector3.UP * 0.45, 0.1, [wave.player.get_rid()]).is_empty():
					clear = false
					break
			if clear: return point
	return wave._path.ground_position(wave.global_position)

func _spawn_samples() -> void:
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	for offset in [Vector3(2, 0, 0), Vector3(2, 0, -1.8), Vector3(4, 0, -1.8)]:
		var slime: WaveEnemy = load("res://scenes/enemies/slime.tscn").instantiate()
		slime.wave_mode = true
		slime.spawn_delay = 0.0
		slime.health = 20.0
		slime.collision_layer = 2
		slime.terrain = wave.terrain
		slime.target = wave.player
		slime.wave_target = wave.player
		slime.camera = camera
		slime.navigation = wave._path
		slime.combat_active = wave.combat_active
		world.add_child(slime)
		slime.global_position = wave._path.ground_position(_origin + offset)
		slime.set_physics_process(false)
		slime.defeated.connect(func(enemy): wave.enemies.erase(enemy))
		wave.enemies.append(slime)

func _process(delta: float) -> void:
	if _capturing or not wave.enemies.is_empty(): return
	_reset_clock += delta
	if _reset_clock >= 1.0:
		_reset_clock = 0.0
		_spawn_samples()

func _capture(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory.path_join("frames"))
	var player: Player = wave.player
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	player.set_physics_process(false)
	attack.set_physics_process(false)
	attack.audio_enabled = false
	AudioServer.set_bus_mute(0, true)
	for frame in 90: await get_tree().process_frame
	camera.snap_to_target()
	var reflections := [0]
	attack.mirror_reflected.connect(func(_enemy, _point, _normal): reflections[0] += 1)
	print("Mirror camera: FOV=", camera.fov, " distance=", camera.distance, " pitch=", camera.pitch_degrees, " DOF=", camera.dof_enabled, " actual player pixel=", attack._player_pixel_size(), " sample=", _origin)
	attack._cooldown = 0.0
	attack.set_physics_process(true)
	for frame in 240:
		await get_tree().process_frame
		if frame % 2 == 0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(directory.path_join("frames/%04d.png" % (frame / 2)))
	print("Mirror preview: reflections=", reflections[0], " remaining monsters=", wave.enemies.size(), " marks=", attack._marks.size())
	get_tree().quit()
