extends Node3D

## 按当前正式地图和相机查看 Meowa 素材；不接入战斗伤害、成长或存档。
@export_range(1.0, 5.0, 0.1, "suffix:s") var replay_interval := 2.2
@export_range(2.0, 12.0, 0.1, "suffix:m") var preview_distance := 7.5
@export var preview_origin := Vector3(-1.6, 0.03, 44.8)
@export var preview_direction := Vector3(1.0, 0.0, -0.5)

var world: Node3D
@onready var effect: LightPierceEffect = $LightPierceEffect
var targets: Array[Vector3] = []
var _hit_distances: Array[float] = []
var _hit_index := 0
var _clock := 0.0
var _prepared := false

func _ready() -> void:
	world = load("res://scenes/world/world.tscn").instantiate()
	world.name = "CurrentWorld"
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	world.get_node("WavePrototype/FanAutoAttack").enabled = false
	world.get_node("Farming").enabled = false
	add_child(world)
	var wave := world.get_node("WavePrototype")
	wave.show_ui = false
	wave.set_process(false)
	wave.set_physics_process(false)
	wave.set_process_unhandled_input(false)
	wave.set_process_unhandled_key_input(false)
	world.get_node("WavePrototype/WaveHUD").hide()
	var player: Player = world.get_node("Player")
	player.set_physics_process(false)
	player.global_position = preview_origin
	player.reset_physics_interpolation()
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	camera.reset_horizontal_rotation()
	camera.snap_to_target()
	var direction := preview_direction.normalized()
	for distance in [2.8, 4.55, 6.3]:
		var position_on_ground: Vector3 = preview_origin + direction * distance
		var slime: WaveEnemy = load("res://scenes/enemies/slime.tscn").instantiate()
		slime.terrain = world.get_node("Homestead")
		slime.target = player
		slime.camera = camera
		slime.patrol_radius = 0.0
		slime.detect_distance = 0.5
		slime.position = position_on_ground
		world.add_child(slime)
		slime.set_physics_process(false)
		targets.append(position_on_ground)
		_hit_distances.append(distance - 0.75)
	await get_tree().create_timer(2.0).timeout
	_prepared = true
	replay()

func replay() -> void:
	if not is_instance_valid(effect): return
	_clock = 0.0
	_hit_index = 0
	var direction := preview_direction.normalized()
	effect.launch(preview_origin + direction * 0.75, direction, preview_distance)

func _process(delta: float) -> void:
	if not _prepared: return
	_clock += delta
	while _hit_index < targets.size() and effect.travelled >= _hit_distances[_hit_index]:
		effect.show_hit(targets[_hit_index])
		_hit_index += 1
	if _clock >= replay_interval: replay()
