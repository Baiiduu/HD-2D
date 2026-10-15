class_name EnemyFeedbackPool
extends Node3D

## 波次内共用，闲置对象停止处理；升级冻结和结束清理继承 EnemyAttacks。
var _idle_deaths: Array[EnemyDeathEffect] = []
var _idle_seeds: Array[EnemySeedProjectile] = []
var _audio: GameAudio
static var _users := 0

func _ready() -> void:
	_users += 1
	_audio = get_tree().get_first_node_in_group(&"game_audio") as GameAudio
	set_process(false)
	set_physics_process(false)

func _exit_tree() -> void:
	_users -= 1
	if _users == 0:
		EnemyDeathEffect._quad = null
		EnemySeedProjectile._quad = null
		EnemySeedProjectile._texture = null

func death(sprite: Sprite3D, shards: bool) -> EnemyDeathEffect:
	var effect: EnemyDeathEffect
	if _idle_deaths.is_empty():
		effect = EnemyDeathEffect.new()
		add_child(effect)
		effect.finished.connect(func(): _idle_deaths.append(effect))
	else: effect = _idle_deaths.pop_back()
	var camera := get_viewport().get_camera_3d()
	effect.begin(sprite, shards, camera)
	return effect

func shoot_seed(enemy: WaveEnemy, heading: Vector3, rules: LanternSpitterDefinition) -> EnemySeedProjectile:
	var seed: EnemySeedProjectile
	if _idle_seeds.is_empty():
		seed = EnemySeedProjectile.new()
		add_child(seed)
		seed.finished.connect(func(): _idle_seeds.append(seed))
	else: seed = _idle_seeds.pop_back()
	seed.begin(enemy, heading, rules)
	return seed

func play_sound(clip: AudioStream, cue: StringName, point: Vector3, kind: GameAudio.Kind) -> void:
	if is_instance_valid(_audio):
		_audio.request({"source": self, "cue": cue, "clips": [clip], "kind": kind,
			"position": point, "volume_db": -12.0, "pitch": 1.0})
