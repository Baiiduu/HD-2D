class_name CoreFeedbackAudio
extends Node3D

const COLLISION_SURFACE := preload("res://scripts/core/collision_surface.gd")

@export_group("核心音效连接")
@export var player: Player
@export var session: WavePrototype
@export var sounds: CoreSoundBank
@export var kill_audio_rules: KillAudioRules
@export var enabled := true:
	set(value):
		enabled = value
		if not is_node_ready(): return
		_ui.enabled = value
		if is_instance_valid(_kills): _kills.enabled = value
		for index in _choice_banks.size():
			_choice_banks[index].confirm = sounds.clips_for(&"growth_apply")[0] if value else _original_confirms[index]
		if not value:
			_stop_charge()
			_stop_flight()
			if is_instance_valid(_kills): _kills.clear()
			if is_instance_valid(_audio): _audio.stop_source(self)
		_refresh_processing()
@export_group("音量与反馈")
@export_range(-30.0, 6.0, 0.5) var action_volume_db := -7.0
@export_range(-12.0, 12.0, 0.5) var bounce_gain_db := 3.0
@export_range(-30.0, 6.0, 0.5) var enemy_volume_db := -14.0
@export_range(-12.0, 12.0, 0.5) var death_impact_gain_db := 4.0
@export_range(-30.0, 6.0, 0.5) var feedback_volume_db := -10.0
@export_range(0.1, 0.5, 0.05) var low_health_ratio := 0.25
@export_range(0.03, 0.3, 0.01) var pickup_interval := 0.10
@export_group("碰撞材质反馈")
## 材质标记与音库事件分开；新增材质只需在此配置现有音库事件。
@export var bounce_surface_cues: Dictionary[StringName, StringName] = {
	&"stone": &"bounce_stone", &"wood": &"bounce_wood", &"metal": &"bounce_metal"}
## 未标记、特殊边界和未配置材质沿用本体反弹声，不推测建筑类型。
@export var default_bounce_cue: StringName = &"bounce_stone"
@export_group("统一命中反馈")
## 各地图明确启用；只消费实际普攻／弹射攻击命中，致死确认优先。
@export var common_hit_enabled := false
## 默认只随机主音；开启后另加一条更轻的现有怪物材质声。
@export var hit_material_layer_enabled := false
@export_range(-24.0, -3.0, 0.5) var hit_material_gain_db := -10.0
@export_group("蓄力渐强反馈")
## 仅控制旧起手和能量循环；聚力风及满蓄确认独立保留。
@export var charge_energy_audio_enabled := true:
	set(value):
		charge_energy_audio_enabled = value
		if not is_node_ready() or value: return
		_stop_charge(true)
		if is_instance_valid(_audio): _audio.stop_cue(self, &"core:charge_start")
@export var charge_progress_audio_enabled := false
@export_range(-30.0, 6.0, 0.5) var charge_start_gain_db := -10.0
@export_range(-30.0, 6.0, 0.5) var charge_full_gain_db := -1.0
@export_range(0.5, 2.0, 0.01) var charge_start_pitch := 0.85
@export_range(0.5, 2.0, 0.01) var charge_full_pitch := 1.15
@export_range(-12.0, 6.0, 0.5) var charge_ready_gain_db := 1.0
@export_group("蓄力聚力风")
@export var charge_wind_audio_enabled := false:
	set(value):
		charge_wind_audio_enabled = value
		if not is_node_ready(): return
		if not value: _stop_charge_wind()
		_refresh_processing()
@export_range(-24.0, 12.0, 0.5) var charge_wind_gain_db := 3.0
@export_range(-18.0, 0.0, 0.5) var charge_wind_energy_duck_db := -8.0
@export_range(0.0, 0.3, 0.01, "suffix:s") var charge_wind_fade_out_seconds := 0.08
@export_group("弹射发射释放")
@export var launch_release_audio_enabled := false
@export_range(-12.0, 6.0, 0.5) var launch_full_gain_db := 2.0
@export_range(0.0, 0.4, 0.01, "suffix:s") var launch_wind_entry_seconds := 0.14
@export_range(-18.0, 0.0, 0.5) var launch_wind_start_gain_db := -9.0
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
var _charge_retry := 0.0
var _loop_clips: Array[AudioStream] = []
var _charge_wind_clips: Array[AudioStream] = []
var _charge_wind_level := 0.0
var _charge_wind_retry := 0.0
var _flight_clips: Array[AudioStream] = []
var _flight_level := 0.0
var _flight_fade_rate := 0.0
var _flight_retry := 0.0
var _flight_entry_age := 0.0
var _health := 0.0
var _health_max := 0.0
var _low_warned := false
var _last_pickup := -10000
var _last_horde := -10000
var _ui_last: Dictionary = {}
var _choice_banks: Array[UISoundBank] = []
var _original_confirms: Array[AudioStream] = []
var _kills: KillFeedbackAudio

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
	_charge_wind_clips = _prepare_loop(&"charge_wind")
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
	if session.skill_draft: _bind_choices(session.skill_draft.initial_choice)
	for enemy in session.enemies: _enemy_spawned(enemy)
	_ui.enabled = enabled
	_prepare_kills()

func _prepare_kills() -> void:
	if not kill_audio_rules:
		if is_instance_valid(_kills):
			_kills.rules = null
			_kills.clear()
		return
	if not is_instance_valid(_audio): return
	if not _kills:
		_kills = KillFeedbackAudio.new()
		_kills.name = "KillFeedback"
		_kills.audio = _audio
		_kills.bank = sounds
		_kills.session = session
		_kills.rules = kill_audio_rules
		add_child(_kills)
	_kills.rules = kill_audio_rules
	_kills.volume_db = enemy_volume_db + death_impact_gain_db
	_kills.enabled = enabled

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

func _play_world(cue: StringName, point: Vector3, kind := GameAudio.Kind.ATTACK, gain := 0.0, priority := -1, pitch := 1.0, merge_group: StringName = &"") -> bool:
	if not enabled or not sounds or not is_instance_valid(_audio): return false
	var clips := sounds.clips_for(cue)
	if clips.is_empty(): return false
	var event := {"source":self, "cue":StringName("core:" + cue), "clips":clips, "kind":kind,
		"position":point, "volume_db":action_volume_db + gain, "pitch":pitch}
	if priority >= 0: event.priority = priority
	if merge_group != &"": event.merge_group = merge_group
	return _audio.request(event) != null

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
	_stop_charge(true)
	_refresh_processing()
	if not enabled or state != PlayerRicochet.State.CHARGING: return
	_ready_chime = false
	if charge_energy_audio_enabled:
		_play_world(&"charge_start", player.global_position, GameAudio.Kind.ATTACK, -2.0, 50)
		_request_charge_loop(0.0)
	_update_charge_wind(0.0)

func _charge_ready() -> void:
	if not enabled or _ready_chime: return
	_ready_chime = true
	_play_world(&"charge_ready", player.global_position, GameAudio.Kind.ATTACK, charge_ready_gain_db if charge_progress_audio_enabled else -2.0, 55)

func _charge_volume(fraction: float) -> float:
	var wind_duck := charge_wind_energy_duck_db if charge_wind_audio_enabled and not _charge_wind_clips.is_empty() else 0.0
	return action_volume_db + wind_duck + (lerpf(charge_start_gain_db, charge_full_gain_db, clampf(fraction, 0.0, 1.0)) if charge_progress_audio_enabled else -3.0)

func _charge_pitch(fraction: float) -> float:
	return lerpf(charge_start_pitch, charge_full_pitch, clampf(fraction, 0.0, 1.0)) if charge_progress_audio_enabled else 1.0

func _request_charge_loop(fraction: float) -> void:
	if charge_energy_audio_enabled and is_instance_valid(_audio) and not _loop_clips.is_empty():
		_charge_retry = 0.20
		_audio.request({"source":player, "cue":&"core:charge_loop", "clips":_loop_clips, "kind":GameAudio.Kind.ATTACK,
			"position":player.global_position, "volume_db":_charge_volume(fraction), "pitch":_charge_pitch(fraction), "priority":20, "follow_source":true})

func _update_charge_audio(delta: float) -> void:
	if not charge_energy_audio_enabled or not charge_progress_audio_enabled or not is_instance_valid(_audio): return
	_charge_retry = maxf(0.0, _charge_retry - delta)
	if _audio.set_cue_volume(player, &"core:charge_loop", _charge_volume(_body.charge_fraction)):
		_audio.set_cue_pitch(player, &"core:charge_loop", _charge_pitch(_body.charge_fraction))
	elif _charge_retry <= 0.0:
		_request_charge_loop(_body.charge_fraction)

func _refresh_processing() -> void:
	set_physics_process(enabled and is_instance_valid(_body) and (
		_body.charging or (_body.flying and flight_audio_enabled) or _flight_level > 0.0 or _charge_wind_level > 0.0))

func _physics_process(delta: float) -> void:
	if not enabled or not is_instance_valid(_body):
		_stop_charge_wind()
		_stop_flight()
		set_physics_process(false)
		return
	if session.combat_frozen: return
	if _body.charging and not _ready_chime and _body.charge_fraction >= 1.0:
		_charge_ready()
	if _body.charging: _update_charge_audio(delta)
	_update_charge_wind(delta)
	_update_flight(delta)
	_refresh_processing()

func _charge_wind_volume(fraction: float) -> float:
	return action_volume_db + charge_wind_gain_db + lerpf(-14.0, 0.0, clampf(fraction, 0.0, 1.0))

func _update_charge_wind(delta: float) -> void:
	var gathering := charge_wind_audio_enabled and _body.charging
	if not gathering and _charge_wind_level <= 0.0: return
	var target := db_to_linear(lerpf(-14.0, 0.0, _body.charge_fraction)) if gathering else 0.0
	var duration := 0.08 if gathering else charge_wind_fade_out_seconds
	_charge_wind_level = move_toward(_charge_wind_level, target, delta / maxf(duration, 0.001))
	if not gathering and (_charge_wind_level <= 0.00001 or duration <= 0.0):
		_stop_charge_wind()
		return
	if not is_instance_valid(_audio) or _charge_wind_clips.is_empty(): return
	var gain := action_volume_db + charge_wind_gain_db + linear_to_db(maxf(_charge_wind_level, 0.0001))
	_charge_wind_retry = maxf(0.0, _charge_wind_retry - delta)
	if _audio.set_cue_volume(player, &"core:charge_wind", gain): return
	if not gathering or _charge_wind_retry > 0.0: return
	_charge_wind_retry = 0.20
	_audio.request({"source":player, "cue":&"core:charge_wind", "clips":_charge_wind_clips, "kind":GameAudio.Kind.ATTACK,
		"position":player.global_position, "volume_db":gain, "priority":24, "follow_source":true})

func _stop_charge_wind() -> void:
	if is_instance_valid(_audio) and is_instance_valid(player): _audio.stop_cue(player, &"core:charge_wind")
	_charge_wind_level = 0.0
	_charge_wind_retry = 0.0

func _flight_speed_level(speed: float) -> float:
	var fraction := clampf(speed / maxf(flight_reference_speed, 0.1), 0.0, 1.0)
	return db_to_linear(lerpf(flight_low_speed_gain_db, 0.0, fraction))

func _update_flight(delta: float) -> void:
	var flying := flight_audio_enabled and _body.flying
	if not flying and _flight_level <= 0.0: return
	if flying:
		_flight_entry_age += delta
		_flight_fade_rate = 0.0
		var weight := 1.0 if flight_volume_smoothing <= 0.0 else 1.0 - exp(-delta / flight_volume_smoothing)
		_flight_level = lerpf(_flight_level, _flight_speed_level(_body.movement_speed), weight)
	else:
		_flight_level = move_toward(_flight_level, 0.0, _flight_fade_rate * delta)
		if _flight_level <= 0.00001:
			_stop_flight()
			return
	if not is_instance_valid(_audio) or _flight_clips.is_empty(): return
	var gain := action_volume_db + flight_gain_db + linear_to_db(maxf(_flight_level, 0.00001))
	if launch_release_audio_enabled and launch_wind_entry_seconds > 0.0:
		gain += launch_wind_start_gain_db * (1.0 - smoothstep(0.0, launch_wind_entry_seconds, _flight_entry_age))
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
	_flight_entry_age = 0.0

func _stop_charge(keep_wind_tail := false) -> void:
	if is_instance_valid(_audio) and is_instance_valid(player): _audio.stop_cue(player, &"core:charge_loop")
	_charge_retry = 0.0
	if not keep_wind_tail: _stop_charge_wind()

func _launched(_heading: Vector3, _speed: float, _charge: float) -> void:
	# 刚满即松手可能先于反馈节点采样；与满蓄镜头一样保留这个真实边沿。
	if charge_progress_audio_enabled and _charge >= 1.0: _charge_ready()
	var gain := launch_full_gain_db * clampf(_charge, 0.0, 1.0) if launch_release_audio_enabled else 0.0
	if launch_release_audio_enabled and is_instance_valid(_audio):
		# 刚满即松手仍记录满蓄边沿，但让提示尾音退到发射主音之后。
		_audio.set_cue_volume(self, &"core:charge_ready", action_volume_db + charge_ready_gain_db - 9.0)
	_play_world(&"launch", player.global_position, GameAudio.Kind.ATTACK, gain, 70 if launch_release_audio_enabled else 60)
	if not enabled or not flight_audio_enabled: return
	_flight_retry = 0.0
	_flight_entry_age = 0.0
	_update_flight(0.0)
	_refresh_processing()

func _bounced(collision: KinematicCollision3D) -> void:
	var surface := COLLISION_SURFACE.resolve(collision.get_collider(), collision.get_collider_shape_index())
	var cue: StringName = bounce_surface_cues.get(surface, default_bounce_cue)
	_play_world(cue, collision.get_position(), GameAudio.Kind.ATTACK, bounce_gain_db, 60, 1.0 + minf(3, _body.bounce_count - 1) * 0.025)

func _pushed(enemy: WaveEnemy, _heading: Vector3) -> void:
	_play_world(&"push_stun", enemy.global_position, GameAudio.Kind.ATTACK, -3.0, 50)

func _flight_finished(reason: StringName) -> void:
	_stop_charge(reason == &"cancelled")
	_fade_flight()
	if reason != &"cancelled": _play_world(&"flight_end", player.global_position, GameAudio.Kind.ATTACK, -5.0)

func _vitals() -> void:
	var health := player.current_health
	if health <= 0.0 and is_instance_valid(_kills): _kills.clear()
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
	if enabled and event.lethal and not event.simulated and not enemy.definition is PotBroodDefinition:
		_prepare_kills()
		if _kills and _kills.record(event, enemy.definition.enemy_id if enemy.definition else &""): return
	# 雷潮已经按片播放完整电声，避免每个受击者再叠身体命中。
	if event.source == &"ricochet_storm": return
	# 单刀声音已由出手统一负责；不按命中目标数量或声音是否结束补播。
	if event.source in [&"basic_sword", &"flight_sword"] and is_instance_valid(player) and player.sword and player.sword.rules.single_sound_per_swing: return
	var hard := enemy.definition is PotBroodDefinition
	var material: StringName = &"enemy_hit_hard" if hard else &"enemy_hit_soft"
	var gain := enemy_volume_db - action_volume_db
	if common_hit_enabled and event.source in [&"basic_sword", &"flight_sword"]:
		# 公共池负责随机不连重、局部合并和优先级；主音没播放时不漏出孤立叠加层。
		var played := _play_world(&"enemy_hit_common", event.world_position, GameAudio.Kind.HIT, gain)
		if played and hit_material_layer_enabled:
			_play_world(material, event.world_position, GameAudio.Kind.HIT, gain + hit_material_gain_db, 8, 1.0, &"hit_material")
		return
	_play_world(material, event.world_position, GameAudio.Kind.HIT, gain)

func _enemy_defeated(enemy: WaveEnemy) -> void:
	# 壶兽保留独立碎裂声；分裂音在幼体实际创建时播放。
	if enemy.definition is PotBroodDefinition: return
	# 新链路已在真实 lethal 事件中即时确认，早于清波／分裂回调。
	if _kills and enabled and enemy.dead and _kills.accepts_source(enemy.fatal_hit_context.get("source", &"")): return
	var slime := enemy.definition and enemy.definition.enemy_id in [&"slime", &"mini_slime"]
	var impact: bool = player.action_visuals != null and player.action_visuals.melee_death_enabled and enemy.fatal_hit_context.get("source", &"") in [&"basic_sword", &"flight_sword", &"ricochet_storm"]
	_play_world(&"slime_death" if slime else &"creature_death", enemy.global_position, GameAudio.Kind.DEATH, enemy_volume_db - action_volume_db + (death_impact_gain_db if impact else 0.0), 35 if impact else -1)
