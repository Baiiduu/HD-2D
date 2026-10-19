class_name EnemyFeedbackPool
extends Node3D
signal presentations_finished
const MELEE_CONTACT := preload("res://scripts/enemies/enemy_melee_contact.gd")

## 波次内共用，闲置对象停止处理；升级冻结和结束清理继承 EnemyAttacks。
var _idle_deaths: Array[EnemyDeathEffect] = []
var _idle_seeds: Array[EnemySeedProjectile] = []
var _idle_contacts: Array[MeshInstance3D] = []
var _audio: GameAudio
static var _users := 0
var _burst_count := 0
var _burst_position := Vector3.ZERO
var _burst_window := 0.0
var _burst_cooldown := 0.0
var preserve_on_clear := false
var _retiring := false
var _remaining_presentations := 0
var _prewarm_visuals: PlayerActionVisuals
var _prewarm_deaths := 0
var _prewarm_contacts := 0

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

func death(sprite: Sprite3D, shards: bool, visuals: PlayerActionVisuals = null, hit: Dictionary = {}) -> EnemyDeathEffect:
	if visuals and visuals.combat_readability_enabled: preserve_on_clear = true
	var effect := _take_death()
	var camera := get_viewport().get_camera_3d()
	effect.begin(sprite, shards, camera, visuals, hit)
	if visuals and visuals.melee_death_cluster_enabled: _register_burst(sprite, visuals, camera)
	return effect

## 仅供真实致死事件同帧取景；不把上一次死亡或集中爆点误当作最后一击。
func death_subject_at(point: Vector3) -> MeshInstance3D:
	var subject: MeshInstance3D
	var nearest := INF
	for effect in get_children():
		if not effect is EnemyDeathEffect or not effect.is_processing() or effect._burst_only or effect._age > 0.00001: continue
		var offset: Vector3 = effect._position - point
		var distance := Vector2(offset.x, offset.z).length_squared()
		if distance <= 0.01 and distance <= nearest:
			nearest = distance
			subject = effect.get_focus_subject()
	return subject

func _take_death() -> EnemyDeathEffect:
	if _idle_deaths.is_empty():
		return _new_death()
	return _idle_deaths.pop_back()

func _new_death() -> EnemyDeathEffect:
	var effect := EnemyDeathEffect.new()
	add_child(effect)
	effect.finished.connect(func(): _idle_deaths.append(effect))
	effect.presentation_event.connect(_death_presentation)
	return effect

func _new_contact() -> MeshInstance3D:
	var effect := MELEE_CONTACT.new()
	add_child(effect)
	effect.finished.connect(func(): _idle_contacts.append(effect))
	return effect

## 只在准备／休整时调用；每帧最多创建两个完整反馈对象。
func start_prewarm(visuals: PlayerActionVisuals, deaths: int, contacts: int) -> void:
	_prewarm_visuals = visuals
	_prewarm_deaths = maxi(0, deaths - _idle_deaths.size())
	_prewarm_contacts = maxi(0, contacts - _idle_contacts.size())
	if not prewarm_ready(): set_process(true)

func prewarm_ready() -> bool:
	return _prewarm_deaths == 0 and _prewarm_contacts == 0

func finish_prewarm() -> void:
	# 提前开战可使用已完成的储备，剩余部分仍按原规则按需创建。
	_prewarm_deaths = 0
	_prewarm_contacts = 0
	_prewarm_visuals = null
	if _burst_window <= 0.0 and _burst_cooldown <= 0.0: set_process(false)

func melee_contact(point: Vector3, pixel: float, heading: Vector3, visuals: PlayerActionVisuals) -> MeshInstance3D:
	preserve_on_clear = true
	var frames := visuals.combat_contact_frames
	if not frames or not frames.has_animation(&"bounce") or frames.get_frame_count(&"bounce") == 0: return null
	var effect: MeshInstance3D
	if _idle_contacts.is_empty():
		effect = _new_contact()
	else: effect = _idle_contacts.pop_back()
	effect.begin(point, pixel, heading, visuals, get_viewport().get_camera_3d())
	return effect

## 清波只保留没有伤害的快照；退出和重试仍由场景立即销毁整个池。
func retire_presentations() -> void:
	finish_prewarm()
	_retiring = true
	set_process(false)
	for child in get_children():
		if child is EnemySeedProjectile:
			child.stop()
			child.queue_free()
		elif (child is EnemyDeathEffect or child.get_script() == MELEE_CONTACT) and child.is_processing():
			_remaining_presentations += 1
			child.connect(&"finished", _retired_finished, CONNECT_ONE_SHOT)
	_idle_seeds.clear()
	if _remaining_presentations == 0:
		presentations_finished.emit()
		queue_free()

func _retired_finished() -> void:
	_remaining_presentations -= 1
	if _remaining_presentations <= 0:
		presentations_finished.emit()
		queue_free()

func _death_presentation(stage: StringName, point: Vector3) -> void:
	if not _retiring and is_instance_valid(_audio): _audio.death_presentation.emit(stage, point)

func _register_burst(sprite: Sprite3D, visuals: PlayerActionVisuals, camera: Camera3D) -> void:
	if _burst_cooldown > 0.0: return
	var point := sprite.global_position
	if _burst_window <= 0.0 or _burst_position.distance_squared_to(point) > 2.2 * 2.2:
		_burst_count = 0
		_burst_window = 0.12
		_burst_position = point
	_burst_position = (_burst_position * _burst_count + point) / (_burst_count + 1)
	_burst_count += 1
	set_process(true)
	if _burst_count < 3: return
	var burst := _take_death()
	burst.begin_burst(_burst_position, sprite.pixel_size * sprite.global_basis.x.length(), camera, visuals)
	_burst_window = 0.0
	_burst_count = 0
	_burst_cooldown = 0.22

func _process(delta: float) -> void:
	for index in 2:
		if _prewarm_deaths > 0:
			var effect := _new_death()
			effect.prepare(_prewarm_visuals)
			_idle_deaths.append(effect)
			_prewarm_deaths -= 1
		elif _prewarm_contacts > 0:
			var contact := _new_contact()
			contact.prepare(_prewarm_visuals)
			_idle_contacts.append(contact)
			_prewarm_contacts -= 1
	if prewarm_ready(): _prewarm_visuals = null
	_burst_window = maxf(0.0, _burst_window - delta)
	_burst_cooldown = maxf(0.0, _burst_cooldown - delta)
	if prewarm_ready() and _burst_window <= 0.0 and _burst_cooldown <= 0.0:
		_burst_count = 0
		set_process(false)

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
