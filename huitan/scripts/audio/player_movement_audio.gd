class_name PlayerMovementAudio
extends Node

const COLLISION_SURFACE := preload("res://scripts/core/collision_surface.gd")

@export_group("人物动作音效")
@export var enabled := true
@export var sounds: MovementSoundBank
## 挂在 Player 下时自动连接；可以手动指定其他人物。
@export var player: Player
@export var audio_bus: StringName = &"Movement"
## 所有动作音效的总增益；负数越小声音越轻。
@export_range(-40.0, 6.0, 0.5) var volume_db := -8.0
@export_group("脚步")
@export_range(-24.0, 6.0, 0.5) var step_volume_db := 0.0
## 8 帧跑步动画的两次脚掌触地；节奏随实际移动速度缩放。
@export var contact_frames := PackedInt32Array([0, 4])
## 防止转向重置跑步动画时重复踏步，秒。
@export_range(0.05, 0.3, 0.01) var minimum_step_interval := 0.12
## 同时采样脚下中心和四周，跨材质边缘时两者按覆盖比例混合，米。
@export_range(0.0, 0.6, 0.01) var footprint_radius := 0.22
## 材质变化的平滑时间常数，秒。越大过渡越缓慢；0 为立即跟随采样。
@export_range(0.0, 1.0, 0.01) var surface_blend_time := 0.18
## 轻微随机音高，避免机械重复；不影响跑步动画。
@export_range(0.0, 0.15, 0.01) var pitch_variation := 0.04
@export_range(0.0, 3.0, 0.1) var volume_variation_db := 0.6
@export_group("跳跃与落地")
@export_range(-24.0, 6.0, 0.5) var jump_volume_db := -4.0
@export_range(-24.0, 6.0, 0.5) var landing_volume_db := 1.5
## 普通跳跃的落地速度基准，米/秒；更大的下落最多增加 3 dB。
@export_range(1.0, 12.0, 0.1) var landing_reference_speed := 5.6
## 落地复用当前材质的触地声并降低音高，保留不同地面的质感。
@export_range(0.7, 1.1, 0.01) var landing_pitch := 0.88
@export_group("闪身")
## 仅在碰撞检查后确实发生瞬移时播放，起手和被墙挡住时不播放。
@export var blink_sound_enabled := true
@export var blink_sound: AudioStream
## 相对于人物动作音效总音量的增益。
@export_range(-24.0, 6.0, 0.5) var blink_volume_db := 2.0
## 音高越高声音越轻快；不改变闪身动作时间。
@export_range(0.5, 2.0, 0.01) var blink_pitch := 1.0
@export_group("地表声音对应")
## 没有 Terrain 或声音标签的碰撞地面使用此类型。
@export_enum("石板", "卵石", "草地", "泥土", "木板", "金属") var fallback_surface := 0
@export_enum("石板", "卵石", "草地", "泥土", "木板", "金属") var city_surface := 1
@export_enum("石板", "卵石", "草地", "泥土", "木板", "金属") var cyber_surface := 5
@export_enum("石板", "卵石", "草地", "泥土", "木板", "金属") var cultivation_surface := 0
@export_enum("石板", "卵石", "草地", "泥土", "木板", "金属") var wild_surface := 2

var _sampler := GroundAudioSampler.new()
var _mix := PackedFloat32Array()
var _voices: Array[AudioStreamPlayer] = []
var _voice_cursor := 0
var _last_clip: Dictionary[int, int] = {}
var _cooldown := 0.0
var _initialized := false

func _ready() -> void:
	if not player:
		player = get_parent() as Player
	if not player:
		set_physics_process(false)
		return
	process_physics_priority = player.process_physics_priority + 1
	_mix = _sampler.one_surface(fallback_surface)
	player.movement_frame_changed.connect(_on_movement_frame)
	player.jumped.connect(_on_jump)
	player.landed.connect(_on_landing)
	player.blink_travelled.connect(_on_blink)
	# 固定小池避免频繁创建节点，也保留前一步的短尾音。
	for index in 12:
		var voice := AudioStreamPlayer.new()
		voice.name = "Voice%d" % index
		add_child(voice)
		_voices.append(voice)

func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if not player.is_on_floor():
		_initialized = false
		return
	var target := _ground_weights()
	var blend := 1.0 if not _initialized or surface_blend_time <= 0.0 else 1.0 - exp(-delta / surface_blend_time)
	for index in _mix.size():
		_mix[index] = lerpf(_mix[index], target[index], blend)
	_initialized = true

func _ground_weights() -> PackedFloat32Array:
	# 一次垂直查询确认实际承重面：站在屋前台阶时不读取台阶下面的草地。
	var point := player.global_position
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.15, point + Vector3.DOWN * 0.35, player.collision_mask, [player.get_rid()])
	var hit := player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() and player.is_on_floor():
		# 台地边缘由胶囊侧下方承重，垂直射线可能落空；改取真实脚下碰撞点。
		for slide in player.get_slide_collision_count():
			var collision := player.get_slide_collision(slide)
			for contact in collision.get_collision_count():
				if collision.get_normal(contact).dot(player.up_direction) >= cos(player.floor_max_angle):
					hit = {"collider": collision.get_collider(contact), "shape": collision.get_collider_shape_index(contact), "position": collision.get_position(contact)}
					break
			if not hit.is_empty():
				break
	if hit.is_empty():
		return _mix if _initialized else _sampler.one_surface(fallback_surface)
	var node := hit.collider as Node
	var surface := COLLISION_SURFACE.resolve(node, hit.shape)
	var movement_surface := COLLISION_SURFACE.movement_index(surface)
	if movement_surface >= 0:
		return _sampler.one_surface(movement_surface)
	while node:
		if node is Terrain and (node as Terrain).data:
			return _sampler.sample(node as Terrain, hit.position, footprint_radius,
				PackedInt32Array([city_surface, cyber_surface, cultivation_surface, wild_surface]))
		node = node.get_parent()
	return _sampler.one_surface(fallback_surface)

func _on_movement_frame(animation: StringName, frame: int) -> void:
	if enabled and animation.begins_with("run") and frame in contact_frames and player.is_on_floor() and player._movement_speed > 0.05 and _cooldown <= 0.0:
		_play_ground(step_volume_db, 1.0)
		_cooldown = maxf(minimum_step_interval, 0.24 * Player.ANIMATION_REFERENCE_SPEED / player._movement_speed)

func _on_jump() -> void:
	if not enabled or not sounds:
		return
	var pitch := randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	_play(_pick(sounds.jump, -1), jump_volume_db, pitch)
	_play_ground(step_volume_db - 7.0, 1.0)
	_cooldown = minimum_step_interval

func _on_landing(impact_speed: float) -> void:
	if not enabled:
		return
	# 空中跨越材质后，落地读取新承重面；不延续起跳前的材质。
	_mix = _ground_weights()
	_initialized = true
	var strength := clampf(impact_speed / maxf(landing_reference_speed, 0.1), 0.35, 1.4)
	_play_ground(landing_volume_db + linear_to_db(strength), landing_pitch)
	_cooldown = maxf(minimum_step_interval, player.landing_time)

func _on_blink(_start: Vector3, _destination: Vector3) -> void:
	if enabled and blink_sound_enabled:
		_play(blink_sound, blink_volume_db, blink_pitch)

func _play_ground(gain_db: float, base_pitch: float) -> void:
	if not sounds:
		return
	var pitch := base_pitch * randf_range(1.0 - pitch_variation, 1.0 + pitch_variation)
	var variation := randf_range(-volume_variation_db, volume_variation_db)
	var total := 0.0
	for index in _mix.size():
		if _mix[index] >= 0.01 and not sounds.clips(index).is_empty():
			total += _mix[index]
	for index in _mix.size():
		if _mix[index] >= 0.01 and not sounds.clips(index).is_empty():
			# 非相关短音效采用等功率混合，避免边缘声音突然变轻或叠加过响。
			var gain := sqrt(_mix[index] / total)
			_play(_pick(sounds.clips(index), index), gain_db + variation + linear_to_db(gain), pitch)

func _pick(clips: Array[AudioStream], key: int) -> AudioStream:
	if clips.is_empty():
		return null
	var index := randi_range(0, clips.size() - 1)
	if clips.size() > 1 and index == _last_clip.get(key, -1):
		index = (index + 1) % clips.size()
	_last_clip[key] = index
	return clips[index]

func _play(stream: AudioStream, gain_db: float, pitch: float) -> void:
	if not stream or _voices.is_empty():
		return
	var voice := _voices[_voice_cursor]
	_voice_cursor = (_voice_cursor + 1) % _voices.size()
	voice.stream = stream
	voice.bus = audio_bus
	voice.volume_db = volume_db + gain_db
	voice.pitch_scale = pitch
	voice.play()
