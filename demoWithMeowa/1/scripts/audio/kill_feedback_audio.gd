class_name KillFeedbackAudio
extends Node

## 先确认真实致死，再独立统计附近群杀；只保存值，不持有已死亡怪物。
const SOURCES := [&"basic_sword", &"flight_sword", &"ricochet_storm"]
var rules: KillAudioRules
var audio: GameAudio
var bank: CoreSoundBank
var session: Node
var volume_db := -10.0
var enabled := true
var _groups: Array[Dictionary] = []
var _cooldown := 0.0
var _duck_remaining := 0.0

func _ready() -> void:
	audio.death_presentation.connect(_presentation)
	session.phase_changed.connect(_phase_changed)
	session.run_started.connect(clear)
	set_process(false)

func accepts_source(source: StringName) -> bool:
	return rules != null and rules.enabled and source in SOURCES

func _available() -> bool:
	return enabled and rules != null and rules.enabled and is_instance_valid(audio) and audio.enabled and not session.combat_frozen

func record(event: CombatDamageEvent, enemy_id: StringName) -> bool:
	if not _available() or session.phase != WavePrototype.Phase.BATTLE: return false
	if not event.lethal or event.simulated or not accepts_source(event.source) or not event.world_position.is_finite(): return false
	var cue: StringName = &"kill_slime" if enemy_id in [&"slime", &"mini_slime"] else &"creature_death"
	if bank.clips_for(cue).is_empty(): return false
	var storm := event.source == &"ricochet_storm"
	_play(cue, event.world_position, 35, -2.0 if storm else 0.0, 1.0, &"kill_body")
	var group: Dictionary = {}
	for item in _groups:
		var difference: Vector3 = event.world_position - item.anchor
		difference.y = 0.0
		if difference.length_squared() <= rules.group_radius * rules.group_radius:
			group = item
			break
	if group.is_empty():
		group = {"anchor": event.world_position, "center": event.world_position, "count": 0, "remaining": rules.group_window, "storm": true}
		_groups.append(group)
	group.center = (group.center * group.count + event.world_position) / float(group.count + 1)
	group.count += 1
	group.storm = group.storm and storm
	set_process(true)
	return true

func _play(cue: StringName, point: Vector3, priority: int, gain := 0.0, pitch := 1.0, layer: StringName = &"kill_detail") -> bool:
	return audio.request({"source": self, "cue": StringName("core:" + cue), "clips": bank.clips_for(cue),
		"kind": GameAudio.Kind.DEATH, "priority": priority, "position": point, "merge_group": layer,
		"volume_db": volume_db + rules.gain_for(cue) + gain, "pitch": pitch}) != null

func _accent(group: Dictionary) -> void:
	if group.count < rules.group_threshold or _cooldown > 0.0: return
	var large: bool = group.count >= rules.large_group_threshold
	var gain := (0.5 if large else 0.0) - (2.0 if group.storm else 0.0)
	if not _play(&"kill_group", group.center, 48, gain, 0.88 if large else 1.0, &"kill_accent"): return
	_cooldown = rules.group_cooldown
	_duck_remaining = rules.duck_seconds
	audio.set_kill_duck(rules.music_duck_db, rules.ambience_duck_db)

func _process(delta: float) -> void:
	if not enabled or rules == null or not rules.enabled or not is_instance_valid(audio) or not audio.enabled:
		clear()
		return
	if session.combat_frozen: return
	var step := maxf(0.0, delta)
	_cooldown = maxf(0.0, _cooldown - step)
	if _duck_remaining > 0.0:
		_duck_remaining = maxf(0.0, _duck_remaining - step)
		var fraction := _duck_remaining / maxf(rules.duck_seconds, 0.001)
		audio.set_kill_duck(rules.music_duck_db * fraction, rules.ambience_duck_db * fraction)
	for index in range(_groups.size() - 1, -1, -1):
		var group := _groups[index]
		group.remaining -= step
		if group.remaining <= 0.0:
			_accent(group)
			_groups.remove_at(index)
	if _groups.is_empty() and _duck_remaining <= 0.0 and _cooldown <= 0.0: set_process(false)

func _presentation(stage: StringName, point: Vector3) -> void:
	if not _available() or session.phase != WavePrototype.Phase.BATTLE: return
	match stage:
		&"air": _play(&"kill_air", point, 15, 0.0, 1.0, &"kill_air")
		&"land", &"wall": _play(&"kill_land", point, 12, -3.0 if stage == &"wall" else 0.0, 1.0, &"kill_land")

func _phase_changed(phase: int) -> void:
	if phase == WavePrototype.Phase.REST:
		for group in _groups: _accent(group)
		_groups.clear()
		if _duck_remaining > 0.0 or _cooldown > 0.0: set_process(true)
	elif phase != WavePrototype.Phase.BATTLE: clear()

func clear() -> void:
	_groups.clear()
	_cooldown = 0.0
	_duck_remaining = 0.0
	if is_instance_valid(audio):
		audio.stop_source(self)
		audio.set_kill_duck(0.0, 0.0)
	set_process(false)

func _exit_tree() -> void:
	clear()
