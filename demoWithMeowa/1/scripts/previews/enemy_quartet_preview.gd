extends Node3D

## 正式场景的原镜头、地表和光影；只安排一组注册怪物用于观察招式。
@onready var world: Node3D = $CurrentWorld
@onready var wave: WavePrototype = $CurrentWorld/WavePrototype
var _pot: PotBroodEnemy
var _clock := 0.0
var _origin := Vector3.ZERO
var _capturing := false

func _enter_tree() -> void:
	$CurrentWorld/LoadoutUI.save_enabled = false
	$CurrentWorld/WavePrototype/RunGrowth.enabled = false

func _ready() -> void:
	set_process(false)
	while not wave._path_ready: await get_tree().physics_frame
	wave.set_physics_process(false)
	wave.player.set_physics_process(false)
	world.get_node("LoadoutUI").hide()
	wave.get_node("WaveHUD").hide()
	wave.get_node("RunGrowth/ExperienceHUD").hide()
	_origin = wave._path.ground_position(Vector3(-5, 0, 42))
	wave.player.global_position = _origin + Vector3.UP * 0.03
	if not wave._prepare_run(): return
	wave._begin_wave()
	wave._spawn_queue.clear()
	var placements := {
		"leaf_charger": Vector3(-3, 0, -1.8), "lantern_spitter": Vector3(3.6, 0, -1.8),
		"pot_brood": Vector3(2.1, 0, 1.3), "bell_frog": Vector3(-1.7, 0, 0.2),
		"slime": Vector3(-3.0, 0, 1.6)}
	for id in placements:
		var data: WaveEnemyDefinition = load("res://data/enemies/%s.tres" % ("wave_slime" if id == "slime" else id))
		if wave._spawn_enemy(data, _origin + placements[id], PackedStringArray(), 0.0):
			var enemy := wave.enemies[-1]
			enemy.set_physics_process(false)
			if enemy is SlimeEnemy:
				enemy._look = (wave.player.global_position - enemy.global_position).normalized()
			if enemy is PotBroodEnemy: _pot = enemy
	wave.player.reset_physics_interpolation()
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	camera.snap_to_target.call_deferred()
	for frame in 90: await get_tree().process_frame
	camera.snap_to_target()
	print("Quartet camera: fov=", camera.fov, " distance=", camera.distance, " pitch=", camera.pitch_degrees, " DOF=", camera.dof_enabled, " registered=", wave.enemies.size())
	var args := OS.get_cmdline_user_args()
	if "--capture-quartet" in args:
		_capturing = true
		_capture(args[args.find("--capture-quartet") + 1])
	else:
		wave.player.set_physics_process(true)
		_start_motion()
		set_process(true)

func _start_motion() -> void:
	wave.set_physics_process(true)
	for enemy in wave.enemies: enemy.set_physics_process(true)

func _process(delta: float) -> void:
	_clock += delta
	if _clock > 2.2 and is_instance_valid(_pot) and not _pot.dead: _pot.take_damage(9999.0)

func _capture(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory.path_join("frames"))
	AudioServer.set_bus_mute(0, true)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(directory.path_join("start.png"))
	_start_motion()
	for frame in 360:
		await get_tree().process_frame
		_process(1.0 / 60.0)
		if frame % 3 == 0:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(directory.path_join("frames/%04d.png" % (frame / 3)))
	print("Quartet preview: kills=", wave.kills, " pending=", wave._pending, " registered=", wave.enemies.size(), " phase=", wave.phase)
	wave._finish("Preview end", WavePrototype.Outcome.RETREAT)
	for audio in world.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	(world.get_node("MapEffects/GameAudio") as GameAudio).stop_all()
	await get_tree().create_timer(0.1).timeout
	get_tree().quit()
