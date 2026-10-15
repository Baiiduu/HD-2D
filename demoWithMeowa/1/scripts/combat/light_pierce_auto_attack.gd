class_name LightPierceAutoAttack
extends Node3D

## A02：锁定起手方向的直线贯穿；每发独立记录命中，物理扫掠驱动视觉。
signal shot_started(direction: Vector3)
signal hit_landed(enemy: WaveEnemy, damage: float)

@export_group("战斗连接")
@export var session: WavePrototype
@export var skill_definition: CombatSkillDefinition
@export var effect_scene: PackedScene
@export var enabled := true:
	set(value):
		enabled = value
		if is_node_ready():
			if not value: cancel_current()
			_refresh_processing()
@export_group("伤害与发射")
@export_range(1.0, 1000.0, 1.0) var damage := 12.0
## 寻敌与最大飞行距离；不受通用覆盖范围增益影响。
@export_range(1.0, 20.0, 0.1, "suffix:m") var attack_range := 8.0
@export_range(0.15, 5.0, 0.05, "suffix:s") var attack_interval := 1.15
@export_range(1.0, 40.0, 0.5, "suffix:m/s") var flight_speed := 14.0
## 一发最多命中多少只怪物，包含第一只。
@export_range(1, 20, 1) var pierce_targets := 3
## 实际碰撞直径；不包含素材外缘的透明辉光。
@export_range(0.1, 1.0, 0.02, "suffix:m") var hit_width := 0.36
@export_range(0.1, 1.0, 0.05, "suffix:m") var height_tolerance := 0.55
@export_range(0.2, 1.0, 0.05, "suffix:m") var flight_height := 0.45
@export_group("公共命中声音")
@export var audio_enabled := true
@export var hit_sounds: Array[AudioStream] = []
@export_range(-40.0, 6.0, 0.5) var hit_volume_db := -16.0
@export_range(0.0, 0.3, 0.005, "suffix:s") var hit_sound_interval := 0.055
@export var audio_manager: GameAudio

var skill_level := 0
var _cooldown := 0.0
var _hit_audio_clock := 0.0
var _shots: Array[Dictionary] = []
var _effects: Array[LightPierceEffect] = []
var _idle_effects: Array[LightPierceEffect] = []
var _collision := ProjectileCollision.new()

func _ready() -> void:
	session.register_combat_node(self)
	session.phase_changed.connect(_phase_changed)
	_refresh_processing()

func get_skill_definition() -> CombatSkillDefinition:
	return skill_definition

func apply_skill_level(level: int) -> bool:
	if not skill_definition or (level != 0 and not skill_definition.level_data(level)): return false
	skill_level = level
	if level == 0: cancel_current(); _cooldown = 0.0
	if is_node_ready(): _refresh_processing()
	return true

func get_attack_stats(level := -1, modifiers: RunCombatModifiers = null) -> Dictionary:
	if level < 0: level = skill_level
	var data := skill_definition.level_data(level) if skill_definition else null
	var values: Dictionary = data.parameters if data else {}
	if not modifiers and session: modifiers = session.combat_modifiers
	return {"damage": damage * values.get("damage_multiplier", 1.0) * (modifiers.damage_multiplier() if modifiers else 1.0),
		"distance": attack_range * values.get("distance_multiplier", 1.0),
		"interval": maxf(0.15, attack_interval * (modifiers.interval_multiplier() if modifiers else 1.0)),
		"speed": flight_speed * values.get("speed_multiplier", 1.0),
		"targets": maxi(1, pierce_targets + int(values.get("extra_targets", 0.0))),
		"width": hit_width * values.get("width_multiplier", 1.0),
		"visual_width": values.get("visual_width_multiplier", 1.0)}

func get_combat_stats(modifiers: RunCombatModifiers = null) -> Dictionary:
	if not enabled or skill_level <= 0: return {}
	var stats := get_attack_stats(skill_level, modifiers)
	return {"name": "雷光贯穿", "damage": stats.damage, "interval": stats.interval}

func describe_skill_upgrade(from_level: int, to_level: int) -> String:
	var after := get_attack_stats(to_level)
	if from_level == 0:
		return "直线贯穿 %d 只敌人\n伤害 %s\n射程 %.1f 米\n自动锁敌，墙体阻挡" % [after.targets, str(snappedf(after.damage, 0.1)), after.distance]
	var before := get_attack_stats(from_level)
	var lines := PackedStringArray(["伤害 %s → %s" % [str(snappedf(before.damage, 0.1)), str(snappedf(after.damage, 0.1))]])
	if before.targets != after.targets: lines.append("贯穿 %d → %d 只" % [before.targets, after.targets])
	if before.distance != after.distance: lines.append("射程 %.1f → %.1f 米" % [before.distance, after.distance])
	if before.speed != after.speed: lines.append("飞速 %.1f → %.1f 米/秒" % [before.speed, after.speed])
	if before.width != after.width: lines.append("宽度 %.2f → %.2f 米" % [before.width, after.width])
	lines.append(skill_definition.level_data(to_level).description)
	return "\n".join(lines)

func _refresh_processing() -> void:
	set_physics_process(enabled and skill_level > 0 and session.phase == WavePrototype.Phase.BATTLE)

func _phase_changed(_phase: int) -> void:
	cancel_current()
	_cooldown = 0.0
	_refresh_processing()

func _active() -> bool:
	return enabled and skill_level > 0 and session._path_ready and session.combat_active()

func _physics_process(delta: float) -> void:
	if session.combat_frozen: return
	if not _active():
		if not _shots.is_empty(): cancel_current()
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	_hit_audio_clock = maxf(0.0, _hit_audio_clock - delta)
	for shot in _shots.duplicate():
		if not _active(): return
		_advance_shot(shot, delta)
	if _cooldown <= 0.0: fire()

func nearest_target(origin: Vector3, stats: Dictionary) -> WaveEnemy:
	var candidates: Array[WaveEnemy] = []
	for enemy: WaveEnemy in session.enemies:
		if not is_instance_valid(enemy) or enemy.dead or enemy.spawn_delay > 0.0: continue
		if TerrainPath.horizontal_distance(origin, enemy.global_position) > stats.distance: continue
		if absf(origin.y - enemy.global_position.y) > height_tolerance: continue
		candidates.append(enemy)
	candidates.sort_custom(func(a: WaveEnemy, b: WaveEnemy): return origin.distance_squared_to(a.global_position) < origin.distance_squared_to(b.global_position))
	# 先完成资格与距离筛选；只对最近的候选查地形与实时挡墙。
	for enemy in candidates:
		var offset := enemy.global_position - origin
		offset.y = 0.0
		var distance := offset.length()
		var heading := offset.normalized() if distance > 0.001 else Vector3.FORWARD
		if _segment_limit(origin, heading, 0.0, distance, stats.width, flight_height) >= distance - 0.01: return enemy
	return null

func fire() -> bool:
	if not _active() or _cooldown > 0.0: return false
	var stats := get_attack_stats()
	var origin := session._path.ground_position(session.player.global_position)
	var target := nearest_target(origin, stats)
	if not target: return false
	var direction := target.global_position - origin
	direction.y = 0.0
	direction = direction.normalized() if not direction.is_zero_approx() else Vector3.FORWARD
	var effect := _acquire_effect()
	effect.flight_speed = stats.speed
	effect.flight_height = flight_height
	effect.head_width = effect.get_meta(&"head_width") * stats.visual_width
	effect.trail_width = effect.get_meta(&"trail_width") * stats.visual_width
	effect.impact_width = effect.get_meta(&"impact_width") * stats.visual_width
	effect.launch(origin, direction, stats.distance, true)
	_shots.append({"effect": effect, "origin": origin, "direction": direction, "stats": stats,
		"height": flight_height, "tolerance": height_tolerance, "generation": session._generation,
		"travelled": 0.0, "hits": {}, "hit_count": 0})
	_cooldown = stats.interval
	shot_started.emit(direction)
	return true

func _acquire_effect() -> LightPierceEffect:
	if not _idle_effects.is_empty(): return _idle_effects.pop_back()
	var effect := effect_scene.instantiate() as LightPierceEffect
	add_child(effect)
	_effects.append(effect)
	for key in [&"head_width", &"trail_width", &"impact_width"]: effect.set_meta(key, effect.get(key))
	effect.finished.connect(_release_effect.bind(effect))
	return effect

func _release_effect(effect: LightPierceEffect) -> void:
	if effect not in _idle_effects: _idle_effects.append(effect)

func cancel_current() -> void:
	_shots.clear()
	for effect in _effects:
		effect.stop()
		_release_effect(effect)
	_hit_audio_clock = 0.0
	if is_instance_valid(audio_manager): audio_manager.stop_source(self)

## 沿原发射平面逐段检查；跳跃或闪避不拖动已经发射的弹道。
func _segment_limit(origin: Vector3, direction: Vector3, first: float, last: float, width: float, height: float, tolerance := -1.0) -> float:
	if tolerance < 0.0: tolerance = height_tolerance
	var start := origin + direction * first
	var distance := _collision.ground_limit(session._path, start, direction, last - first, origin.y, tolerance)
	var wall := _collision.wall_contact(get_world_3d().direct_space_state, start + Vector3.UP * height,
		start + direction * distance + Vector3.UP * height, width * 0.5, [session.player.get_rid()])
	return first + (minf(distance, wall.distance) if not wall.is_empty() else distance)

## 连续扫掠与弹射武器共用查询器；命中资格与本发记录由技能自行维护。
func _contacts(shot: Dictionary, end: float) -> Array[Dictionary]:
	var start: Vector3 = shot.origin + shot.direction * shot.travelled + Vector3.UP * shot.height
	var finish: Vector3 = shot.origin + shot.direction * end + Vector3.UP * shot.height
	var contacts := _collision.enemy_contacts(get_world_3d().direct_space_state, start, finish, shot.stats.width * 0.5,
		func(enemy: WaveEnemy): return (enemy in session.enemies and not enemy.dead and enemy.spawn_delay <= 0.0
			and not shot.hits.has(enemy.get_instance_id()) and absf(enemy.global_position.y - shot.origin.y) <= shot.tolerance))
	for contact in contacts: contact.distance += shot.travelled
	return contacts

func _advance_shot(shot: Dictionary, delta: float) -> void:
	if shot.generation != session._generation:
		cancel_current()
		return
	if not _active(): return
	var requested: float = minf(shot.stats.distance, shot.travelled + shot.stats.speed * delta)
	var end := _segment_limit(shot.origin, shot.direction, shot.travelled, requested, shot.stats.width, shot.height, shot.tolerance)
	var finished: bool = end < requested - 0.0001 or requested >= shot.stats.distance
	for contact in _contacts(shot, end):
		if not _active() or shot.generation != session._generation or shot not in _shots: return
		var enemy: WaveEnemy = contact.enemy
		if not is_instance_valid(enemy) or enemy.dead: continue
		shot.hits[enemy.get_instance_id()] = true
		var before := enemy.health
		shot.effect.show_hit(session._path.ground_position(enemy.global_position))
		enemy.take_damage(shot.stats.damage)
		var dealt := before - enemy.health
		if dealt <= 0.0: continue
		shot.hit_count += 1
		if _active(): _play_hit_audio(enemy.global_position)
		hit_landed.emit(enemy, dealt)
		if shot.generation != session._generation or shot not in _shots: return
		if shot.hit_count >= shot.stats.targets:
			end = contact.distance
			finished = true
			break
		if not _active():
			end = contact.distance
			break
	shot.travelled = end
	shot.effect.advance_flight(end, finished)
	if finished: _shots.erase(shot)

func _play_hit_audio(position: Vector3) -> void:
	if not audio_enabled or hit_sounds.is_empty() or _hit_audio_clock > 0.0: return
	if not is_instance_valid(audio_manager): audio_manager = get_tree().get_first_node_in_group(&"game_audio") as GameAudio
	if audio_manager and audio_manager.request({"source": self, "cue": &"pierce_hit", "clips": hit_sounds,
		"kind": GameAudio.Kind.HIT, "position": position, "volume_db": hit_volume_db,
		"pitch": randf_range(1.065, 1.135)}) != null:
		_hit_audio_clock = hit_sound_interval
