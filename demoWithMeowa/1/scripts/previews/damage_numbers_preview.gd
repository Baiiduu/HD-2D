extends Node3D

## 样式预览只重放扣血数字；显式标签不参与正式地图的真实暴击掷骰。
@onready var world: Node3D = $CurrentWorld
@onready var wave: WavePrototype = $CurrentWorld/WavePrototype
var _targets: Array[WaveEnemy] = []
var _clock := 0.0
var _stage := 0

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
	var camera := world.get_node("MapEffects/Camera3D") as FollowCamera
	var right := camera.global_basis.x
	right.y = 0
	right = right.normalized()
	var away := Vector3.UP.cross(right)
	var origin := _choose_origin(right, away)
	wave.player.global_position = origin + Vector3.UP * 0.03
	wave.player.reset_physics_interpolation()
	if not wave._prepare_run(): return
	wave._begin_wave()
	wave._spawn_queue.clear()
	for offset in [-3.0, -1.0, 1.0, 3.0]:
		var point := wave._path.ground_position(origin + right * offset + away * 2.0)
		var data: WaveEnemyDefinition = wave.default_enemy.duplicate()
		data.health = 10000.0
		if wave._spawn_enemy(data, point, PackedStringArray(), 0.0):
			var enemy := wave.enemies[-1]
			enemy.set_physics_process(false)
			_targets.append(enemy)
	camera.snap_to_target.call_deferred()
	for frame in 90: await get_tree().process_frame
	camera.snap_to_target()
	print("Damage preview: targets=", _targets.size(), " FOV=", camera.fov, " distance=", camera.distance, " pitch=", camera.pitch_degrees, " DOF=", camera.dof_enabled)
	set_process(true)
	var args := OS.get_cmdline_user_args()
	if "--capture-damage-numbers" in args: _capture(args[args.find("--capture-damage-numbers") + 1])

func _choose_origin(right: Vector3, away: Vector3) -> Vector3:
	for z in [36, 40, 44, 48, 52, 56]:
		for x in [-12, -9, -5, -3, 1, 3, 7]:
			var origin := wave._path.ground_position(Vector3(x, 0, z))
			if wave._path._point_blocked(origin): continue
			var clear := true
			for offset in [-3.0, -1.0, 1.0, 3.0]:
				if wave._path._point_blocked(origin + right * offset + away * 2.0): clear = false
			if clear: return origin
	return wave._path.ground_position(wave.global_position)

func _process(delta: float) -> void:
	_clock += delta
	if _stage == 0 and _clock >= 0.3:
		var styles: Array[StringName] = [&"normal", &"heavy", &"critical", &"lightning"]
		var amounts := [18.0, 84.0, 168.0, 56.0]
		for index in _targets.size():
			var enemy := _targets[index]
			enemy.health = 10000
			enemy.take_damage(amounts[index], {"source": &"style_preview", "style": styles[index]})
		_stage = 1
	elif _stage in [1, 2] and _clock >= 0.3 + _stage * 0.1:
		if not _targets.is_empty(): _targets[0].take_damage(24 + _stage * 4, {"source": &"style_preview"})
		_stage += 1
	elif _clock > 2.0:
		_clock = 0
		_stage = 0

func _capture(directory: String) -> void:
	DirAccess.make_dir_recursive_absolute(directory.path_join("frames"))
	AudioServer.set_bus_mute(0, true)
	for frame in 120:
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(directory.path_join("frames/%04d.png" % frame))
	print("Damage preview pool: ", (wave.get_node("DamageNumbers") as DamageNumbers).get_pool_stats())
	wave._finish("Preview end", WavePrototype.Outcome.RETREAT)
	for audio in world.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	(world.get_node("MapEffects/GameAudio") as GameAudio).stop_all()
	get_tree().quit()
