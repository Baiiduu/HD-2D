class_name CoreFeedbackAudio
extends Node3D

@export_group("核心音效连接")
@export var player: Player
@export var session: WavePrototype
@export var sounds: CoreSoundBank
@export var enabled := true:
	set(value):
		enabled = value
		if not is_node_ready(): return
		_ui.enabled = value
		for index in _choice_banks.size():
			_choice_banks[index].confirm = sounds.clips_for(&"growth_apply")[0] if value else _original_confirms[index]
		if not value:
			_stop_charge()
			_stop_flight()
			if is_instance_valid(_audio): _audio.stop_source(self)
		_refresh_processing()
@export_group("音量与反馈")
@export_range(-30.0, 6.0, 0.5) var action_volume_db := -7.0
@export_range(-12.0, 12.0, 0.5) var bounce_gain_db := 3.0
@export_range(-30.0, 6.0, 0.5) var enemy_volume_db := -14.0
@export_range(-30.0, 6.0, 0.5) var feedback_volume_db := -10.0
@export_range(0.1, 0.5, 0.05) var low_health_ratio := 0.25
@export_range(0.03, 0.3, 0.01) var pickup_interval := 0.10
@export_group("弹射飞行动能气流")
@export var flight_audio_enabled := true:
	set(value):
		flight_audio_enabled = value
		if not is_node_ready(): return
		if not value: _stop_flight()
		_refresh_processing()
## 相对于核心动作音量，参考速度时达到此增益。
@export_range(-30.0, 12.0, 0.5) var flight_gain_db := -5.0
## 接近零速时相对于参考速度额外降低的音量。
@export_range(-30.0, 0.0, 0.5) var flight_low_speed_gain_db := -12.0
@export_range(0.1, 60.0, 0.1, "suffix:m/s") var flight_reference_speed := 12.0
@export_range(0.0, 1.0, 0.01, "suffix:s") var flight_volume_smoothing := 0.10
@export_range(0.0, 2.0, 0.01, "suffix:s") var flight_fade_out_seconds := 0.22

@onready var _ui: UIAudio = $UIAudio
var _audio: GameAudio
var _body: PlayerRicochet
var _ready_chime := false
var _loop_clips: Array[AudioStream] = []
var _flight_clips: Array[AudioStream] = []
var _flight_level := 0.0
var _flight_fade_rate := 0.0
var _flight_retry := 0.0
var _health := 0.0
var _health_max := 0.0
var _low_warned := false
var _last_pickup := -10000
var _last_horde := -10000
var _ui_last: Dictionary = {}
var _choice_banks: Array[UISoundBank] = []
var _original_confirms: Array[AudioStream] = []

func _ready() -> void:
	set_physics_process(false)
	_bind.call_deferred()

func _bind() -> void:
	if not is_instance_valid(player) or not is_instance_valid(session) or not sounds: return
	_audio = get_tree().get_first_node_in_group(&"game_audio") as GameAudio
	_body = player.body_ricochet
	if _body:
		_body.state_changed.connect(_body_state)
		_body.launched.connect(_launched)
		_body.surface_bounced.connect(_bounced)
		_body.enemy_pushed.connect(_pushed)
		_body.finished.connect(_flight_finished)
	_loop_clips = _prepare_loop(&"charge_loop")
	_flight_clips = _prepare_loop(&"flight_loop")
	_health = player.current_health
	_health_max = player.max_health
	player.vitals_changed.connect(_vitals)
	session.phase_changed.connect(_phase_changed)
	session.enemy_spawned.connect(_enemy_spawned)
	session.batch_spawned.connect(_batch_spawned)
	session.wave_cleared.connect(func(_number: int): _play_ui(&"wave_clear"))
	var growth := session.get_node_or_null("RunGrowth") as RunGrowth
	if growth:
		growth.experience_collected.connect(_experience)
		growth.state.levels_gained.connect(func(_count: int): _play_ui(&"level_up"))
		_bind_choices(growth.choice_ui)
	var skills := session.get_node_or_null("RunSkills") as RunSkills
	if skills: _bind_choices(skills.initial_choice)
	for enemy in session.enemies: _enemy_spawned(enemy)
	_ui.enabled = enabled

func _prepare_loop(cue: StringName) -> Array[AudioStream]:
	var result: Array[AudioStream] = []
	var clips := sounds.clips_for(cue)
	if clips.is_empty() or not clips[0] is AudioStreamWAV: return result
	var clip := clips[0].duplicate() as AudioStreamWAV
	clip.set_meta(&"mix_source_path", clips[0].resource_path)
	clip.loop_mode = AudioStreamWAV.LOOP_FORWARD
	clip.loop_begin = 0
	clip.loop_end = roundi(clip.get_length() * clip.mix_rate)
	result.append(clip)
	return result

func _bind_choices(choices: GrowthChoiceUI) -> void:
	choices.cards_turned.connect(func(): _play_ui(&"card_reveal", -4.0))
	choices.cards_redrawn.connect(func(): _play_ui(&"reroll", -2.0))
	# 成长成功沿用 UI 确认事件，替换该界面的音源，避免同时叠两段成功提示。
	var clips := sounds.clips_for(&"growth_apply")
	if choices._audio.sounds and not clips.is_empty():
		var bank := choices._audio.sounds.duplicate() as UISoundBank
		_choice_banks.append(bank)
		_original_confirms.append(bank.confirm)
		if enabled: bank.confirm = clips[0]
		choices._audio.sounds = bank

func _exit_tree() -> void:
	_stop_charge()
	_stop_flight()
	if is_instance_valid(_audio): _audio.stop_source(self)

func _play_world(cue: StringName, point: Vector3, kind := GameAudio.Kind.ATTACK, gain := 0.0, priority := -1, pitch := 1.0) -> void:
	if not enabled or not sounds or not is_instance_valid(_audio): return
	var clips := sounds.clips_for(cue)
	if clips.is_empty(): return
	var event := {"source":self, "cue":StringName("core:" + cue), "clips":clips, "kind":kind,
		"position":point, "volume_db":action_volume_db + gain, "pitch":pitch}
	if priority >= 0: event.priority = priority
	_audio.request(event)

func _play_ui(cue: StringName, gain := 0.0, pitch := 1.0) -> void:
	if not enabled or not sounds: return
	var clips := sounds.clips_for(cue)
	if clips.is_empty(): return
	var index := randi_range(0, clips.size() - 1)
	if clips.size() > 1 and index == _ui_last.get(cue, -1): index = (index + 1) % clips.size()
	_ui_last[cue] = index
	_ui.volume_db = feedback_volume_db
	_ui.play_clip(cue, clips[index], gain, pitch)

func _body_state(state: PlayerRicochet.State) -> void:
	_stop_charge()
	_ready_chime = false
	_refresh_processing()
	if not enabled or state != PlayerRicochet.State.CHARGING: return
	_play_world(&"charge_start", player.global_position, GameAudio.Kind.ATTACK, -2.0, 50)
	if is_instance_valid(_audio) and not _loop_clips.is_empty():
		_audio.request({"source":player, "cue":&"core:charge_loop", "clips":_loop_clips, "kind":GameAudio.Kind.ATTACK,
			"position":player.global_position, "volume_db":action_volume_db - 3.0, "priority":20, "follow_source":true})

func _refresh_processing() -> void:
	set_physics_process(enabled and is_instance_valid(_body) and (
		_body.charging or (_body.flying and flight_audio_enabled) or _flight_level > 0.0))

func _physics_process(delta: float) -> void:
	if not enabled or not is_instance_valid(_body):
		_stop_flight()
		set_physics_process(false)
		return
	if session.combat_frozen: return
	if _body.charging and not _ready_chime and _body.charge_fraction >= 1.0:
		_ready_chime = true
		_play_world(&"charge_ready", player.global_position, GameAudio.Kind.ATTACK, -2.0, 55)
	_update_flight(delta)
	_refresh_processing()

func _flight_speed_level(speed: float) -> float:
	var fraction := clampf(speed / maxf(flight_reference_speed, 0.1), 0.0, 1.0)
	return db_to_linear(lerpf(flight_low_speed_gain_db, 0.0, fraction))

func _update_flight(delta: float) -> void:
	var flying := flight_audio_enabled and _body.flying
	if not flying and _flight_level <= 0.0: return
	if flying:
		_flight_fade_rate = 0.0
		var weight := 1.0 if flight_volume_smoothing <= 0.0 else 1.0 - exp(-delta / flight_volume_smoothing)
		_flight_level = lerpf(_flight_level, _flight_speed_level(_body.flight_speed), weight)
	else:
		_flight_level = move_toward(_flight_level, 0.0, _flight_fade_rate * delta)
		if _flight_level <= 0.00001:
			_stop_flight()
			return
	if not is_instance_valid(_audio) or _flight_clips.is_empty(): return
	var gain := action_volume_db + flight_gain_db + linear_to_db(maxf(_flight_level, 0.00001))
	_flight_retry = maxf(0.0, _flight_retry - delta)
	if _audio.set_cue_volume(player, &"core:flight_loop", gain): return
	# 被更重要的声音抢占后低频重试；已经结束的飞行不重新创建尾音。
	if not flying or _flight_retry > 0.0: return
	_flight_retry = 0.20
	_audio.request({"source":player, "cue":&"core:flight_loop", "clips":_flight_clips, "kind":GameAudio.Kind.ATTACK,
		"position":player.global_position, "volume_db":gain, "priority":25, "follow_source":true})

func _fade_flight() -> void:
	if flight_fade_out_seconds <= 0.0 or _flight_level <= 0.00001:
		_stop_flight()
	elif _flight_fade_rate <= 0.0:
		_flight_fade_rate = _flight_level / flight_fade_out_seconds
	_refresh_processing()

func _stop_flight() -> void:
	if is_instance_valid(_audio) and is_instance_valid(player): _audio.stop_cue(player, &"core:flight_loop")
	_flight_level = 0.0
	_flight_fade_rate = 0.0
	_flight_retry = 0.0

func _stop_charge() -> void:
	if is_instance_valid(_audio) and is_instance_valid(player): _audio.stop_cue(player, &"core:charge_loop")

func _launched(_heading: Vector3, _speed: float, _charge: float) -> void:
	_play_world(&"launch", player.global_position, GameAudio.Kind.ATTACK, 0.0, 60)
	if not enabled or not flight_audio_enabled: return
	_flight_retry = 0.0
	_update_flight(0.0)
	_refresh_processing()

func _bounced(collision: KinematicCollision3D) -> void:
	var node := collision.get_collider() as Node
	var cue := &"bounce_stone"
	while node:
		if node.has_meta("movement_surface"):
			var surface := int(node.get_meta("movement_surface"))
			cue = &"bounce_wood" if surface == 4 else (&"bounce_metal" if surface == 5 else &"bounce_stone")
			break
		if node is TownDetailProp:
			var detail := (node as TownDetailProp).detail_kind
			if detail in [0, 1, 2, 6, 7]: cue = &"bounce_wood"
			elif detail == 5: cue = &"bounce_metal"
			break
		if node is RicochetProp:
			match (node as RicochetProp).kind:
				RicochetProp.Kind.IRON_FENCE: cue = &"bounce_metal"
				RicochetProp.Kind.CRATE_STACK, RicochetProp.Kind.BARREL_CLUSTER: cue = &"bounce_wood"
			break
		node = node.get_parent()
	_play_world(cue, collision.get_position(), GameAudio.Kind.ATTACK, bounce_gain_db, 60, 1.0 + minf(3, _body.bounce_count - 1) * 0.025)

func _pushed(enemy: WaveEnemy, _heading: Vector3) -> void:
	_play_world(&"push_stun", enemy.global_position, GameAudio.Kind.ATTACK, -3.0, 50)

func _flight_finished(reason: StringName) -> void:
	_stop_charge()
	_fade_flight()
	if reason != &"cancelled": _play_world(&"flight_end", player.global_position, GameAudio.Kind.ATTACK, -5.0)

func _vitals() -> void:
	var health := player.current_health
	var damaged := health < _health and is_equal_approx(player.max_health, _health_max)
	_health = health
	_health_max = player.max_health
	if health > _health_max * (low_health_ratio + 0.1): _low_warned = false
	if not damaged or session.phase != WavePrototype.Phase.BATTLE or health <= 0.0: return
	_play_world(&"player_hurt", player.global_position, GameAudio.Kind.HURT, 1.0)
	if not _low_warned and health <= _health_max * low_health_ratio:
		_low_warned = true
		_play_ui(&"low_health", -2.0)

func _phase_changed(phase: WavePrototype.Phase) -> void:
	_stop_charge()
	if phase != WavePrototype.Phase.REST: _stop_flight()
	_refresh_processing()
	if phase == WavePrototype.Phase.BATTLE: _play_ui(&"wave_start", -3.0)
	elif phase == WavePrototype.Phase.RESULT and player.current_health <= 0.0: _play_ui(&"defeat")
	elif phase == WavePrototype.Phase.READY:
		_low_warned = false
		_last_horde = -10000
		_last_pickup = -10000

func _experience(amount: int) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_pickup < pickup_interval * 1000.0: return
	_last_pickup = now
	_play_ui(&"experience", -5.0, 1.0 + minf(amount, 15) * 0.008)

func _batch_spawned(count: int, _point: Vector3) -> void:
	var now := Time.get_ticks_msec()
	if count < 4 or now - _last_horde < 1500: return
	_last_horde = now
	_play_ui(&"horde_arrival", -4.0)

func _enemy_spawned(enemy: WaveEnemy) -> void:
	enemy.damaged.connect(_enemy_damaged.bind(enemy))
	enemy.defeated.connect(_enemy_defeated)
	if enemy.definition and enemy.definition.enemy_id == &"mini_slime":
		_play_world(&"split_spawn", enemy.global_position, GameAudio.Kind.DEATH, enemy_volume_db - action_volume_db)

func _enemy_damaged(event: CombatDamageEvent, enemy: WaveEnemy) -> void:
	# 雷潮已经按片播放完整电声，避免每个受击者再叠身体命中。
	if event.source == &"ricochet_storm": return
	var hard := enemy.definition is PotBroodDefinition
	_play_world(&"enemy_hit_hard" if hard else &"enemy_hit_soft", event.world_position, GameAudio.Kind.HIT, enemy_volume_db - action_volume_db)

func _enemy_defeated(enemy: WaveEnemy) -> void:
	# 壶兽保留独立碎裂声；分裂音在幼体实际创建时播放。
	if enemy.definition is PotBroodDefinition: return
	var slime := enemy.definition and enemy.definition.enemy_id in [&"slime", &"mini_slime"]
	_play_world(&"slime_death" if slime else &"creature_death", enemy.global_position, GameAudio.Kind.DEATH, enemy_volume_db - action_volume_db)
