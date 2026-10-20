class_name PrismRicochetAutoAttack
extends Node3D

signal shot_started(direction: Vector3)
signal hit_landed(enemy: WaveEnemy, damage: float)
signal wall_bounced(point: Vector3, normal: Vector3)

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
@export_group("弹丸基础数值")
@export var damage := 14.0
@export var attack_range := 10.0
@export var attack_interval := 1.1
@export var flight_speed := 12.0
@export var hit_radius := 0.1
@export var flight_height := 0.45
@export var height_tolerance := 0.55
@export_group("公共声音")
@export var audio_enabled := true
@export var hit_sounds: Array[AudioStream] = []
@export var bounce_sounds: Array[AudioStream] = []
## 命中与反弹共用一个接触音色时，避免同次怪物接触叠加两条完整声音。
@export var enemy_bounce_sound_enabled := true
@export var audio_pitch_range := Vector2(1.15, 1.22)
@export var audio_manager: GameAudio

var skill_level := 0
var _cooldown := 0.0
var _shots: Array[Dictionary] = []
var _effects: Array[PrismRicochetEffect] = []
var _idle_effects: Array[PrismRicochetEffect] = []
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
	if level == 0:
		cancel_current()
		_cooldown = 0.0
	if is_node_ready(): _refresh_processing()
	return true

func get_attack_stats(level := -1, modifiers: RunCombatModifiers = null) -> Dictionary:
	if level < 0: level = skill_level
	var data := skill_definition.level_data(level) if skill_definition else null
	var values: Dictionary = data.parameters if data else {}
	if not modifiers and session: modifiers = session.combat_modifiers
	var reach := modifiers.range_multiplier() if modifiers and modifiers.growth_rules else 1.0
	return {"damage": damage * values.get("damage_multiplier", 1.0) * (modifiers.damage_multiplier() if modifiers else 1.0),
		"distance": attack_range * values.get("distance_multiplier", 1.0) * reach,
		"interval": maxf(0.15, attack_interval * values.get("interval_multiplier", 1.0) * (modifiers.interval_multiplier() if modifiers else 1.0)),
		"speed": flight_speed * values.get("speed_multiplier", 1.0),
		"radius": hit_radius * values.get("width_multiplier", 1.0) * reach,
		"bounces": int(values.get("bounces", 2.0)), "count": int(values.get("projectiles", 1.0)),
		"spread": deg_to_rad(values.get("spread_degrees", 24.0)), "visual": values.get("visual_multiplier", 1.0) * reach, "growth_scale": reach}

func get_combat_stats(modifiers: RunCombatModifiers = null) -> Dictionary:
	if not enabled or skill_level <= 0: return {}
	var stats := get_attack_stats(skill_level, modifiers)
	var result := {"name": "棱光弹射", "damage": stats.damage, "interval": stats.interval}
	if session and session.growth_rules: result.range = stats.distance
	return result

func describe_skill_upgrade(from_level: int, to_level: int) -> String:
	var before := get_attack_stats(from_level)
	var after := get_attack_stats(to_level)
	var detail := skill_definition.level_data(to_level).description
	if from_level == 0:
		return "命中怪物、墙体或镜印时反射\n伤害 %s\n每次 %d 枚 · 共用弹射 %d 次\n飞行距离 %.1f 米" % [str(snappedf(after.damage, 0.1)), after.count, after.bounces, after.distance]
	return "伤害 %s → %s · 弹射 %d → %d 次\n齐射 %d → %d 枚 · 飞行 %.1f → %.1f 米\n%s" % [str(snappedf(before.damage, 0.1)), str(snappedf(after.damage, 0.1)), before.bounces, after.bounces, before.count, after.count, before.distance, after.distance, detail]

func _active() -> bool:
	return enabled and skill_level > 0 and session._path_ready and session.combat_active()

func _refresh_processing() -> void:
	set_physics_process(enabled and skill_level > 0 and session.phase == WavePrototype.Phase.BATTLE)

func _phase_changed(_phase: int) -> void:
	cancel_current()
	_cooldown = 0.0
	_refresh_processing()

func _physics_process(delta: float) -> void:
	if not _active(): return
	_cooldown = maxf(0.0, _cooldown - delta)
	for shot in _shots.duplicate():
		if not _active(): return
		_advance_shot(shot, delta)
	if _cooldown <= 0.0: fire()

func fire() -> bool:
	if not _active() or _cooldown > 0.0: return false
	var stats := get_attack_stats()
	var origin := session._path.ground_position(session.player.global_position)
	var target: WaveEnemy
	var nearest: float = stats.distance * stats.distance
	for enemy in session.enemies:
		if not is_instance_valid(enemy) or enemy.dead or enemy.spawn_delay > 0.0: continue
		if absf(enemy.global_position.y - origin.y) > height_tolerance: continue
		var distance := TerrainPath.horizontal_distance(origin, enemy.global_position)
		if distance * distance <= nearest:
			target = enemy
			nearest = distance * distance
	if not target: return false
	stats.damage *= session.attack_snapshot().speed_damage_multiplier
	var direction := target.global_position - origin
	direction.y = 0.0
	direction = direction.normalized() if not direction.is_zero_approx() else Vector3.FORWARD
	for index in stats.count:
		var angle: float = 0.0 if stats.count == 1 else stats.spread * (float(index) / (stats.count - 1) - 0.5)
		launch(origin, direction.rotated(Vector3.UP, angle), stats)
	_cooldown = stats.interval
	shot_started.emit(direction)
	return true

## 出手时锁定数值、平面与方向；闪避保留已发射弹丸和自动攻击冷却。
func prepare_feedback() -> void:
	if not effect_scene or not _effects.is_empty(): return
	var effect := effect_scene.instantiate() as PrismRicochetEffect
	add_child(effect)
	_effects.append(effect)
	effect.finished.connect(_release_effect.bind(effect))
	effect.prepare_feedback()
	_release_effect(effect)

func launch(origin: Vector3, direction: Vector3, stats: Dictionary) -> void:
	var effect: PrismRicochetEffect
	if not _idle_effects.is_empty(): effect = _idle_effects.pop_back()
	else:
		effect = effect_scene.instantiate() as PrismRicochetEffect
		add_child(effect)
		_effects.append(effect)
		effect.finished.connect(_release_effect.bind(effect))
	var position_on_path := origin + Vector3.UP * flight_height
	effect.launch(position_on_path, direction, stats.visual)
	_shots.append({"position": position_on_path, "direction": direction, "stats": stats.duplicate(),
		"plane": origin.y, "tolerance": height_tolerance, "generation": session._generation,
		"travelled": 0.0, "bounces": 0, "hits": {}, "effect": effect})

func _eligible(enemy: WaveEnemy, shot: Dictionary) -> bool:
	return enemy in session.enemies and not enemy.dead and enemy.spawn_delay <= 0.0 and not shot.hits.has(enemy.get_instance_id()) and absf(enemy.global_position.y - shot.plane) <= shot.tolerance

func _advance_shot(shot: Dictionary, delta: float) -> void:
	if shot.generation != session._generation or shot not in _shots: return
	var remaining: float = minf(shot.stats.speed * delta, shot.stats.distance - shot.travelled)
	var space := get_world_3d().direct_space_state
	while remaining > 0.00001:
		if not _active() or shot not in _shots or shot.generation != session._generation: return
		var start: Vector3 = shot.position
		var distance := _collision.ground_limit(session._path, start, shot.direction, remaining, shot.plane, shot.tolerance)
		var stopped := distance < remaining - 0.00001
		if stopped and distance <= 0.00001:
			_finish_shot(shot)
			return
		var wall := _collision.wall_contact(space, start, start + shot.direction * distance, shot.stats.radius, [session.player.get_rid()], ProjectileCollision.REFLECTION_MASK)
		if not wall.is_empty(): distance = minf(distance, wall.distance)
		var contact := _collision.first_enemy_contact(space, start, start + shot.direction * distance, shot.stats.radius, _eligible.bind(shot))
		if not contact.is_empty() and (wall.is_empty() or contact.distance < distance - 0.00001):
			var enemy: WaveEnemy = contact.enemy
			var enemy_id := enemy.get_instance_id()
			var incoming: Vector3 = shot.direction
			shot.position = start + incoming * contact.distance
			shot.travelled += contact.distance
			remaining -= contact.distance
			shot.effect.move_to(shot.position, incoming)
			shot.effect.show_contact(contact.point, true)
			var normal: Vector3 = contact.normal
			normal.y = 0.0
			normal = normal.normalized() if not normal.is_zero_approx() else -incoming
			# Commit the reflection before damage callbacks may freeze/end the battle.
			remaining = maxf(0.0, remaining - _reflect_shot(shot, normal))
			shot.hits[enemy_id] = true
			var before := enemy.health
			var hit_position := enemy.global_position
			enemy.take_damage(shot.stats.damage, {"source": &"A03", "direction": incoming})
			if not is_instance_valid(enemy): return
			var dealt := before - enemy.health
			var hit_confirmed := dealt > 0.0 or session.combat_modifiers.damage_disabled
			if hit_confirmed:
				_play_sound(hit_sounds, &"prism_hit", hit_position, GameAudio.Kind.HIT)
				hit_landed.emit(enemy, dealt)
			if not _active() or shot not in _shots or shot.generation != session._generation: return
			if enemy_bounce_sound_enabled or not hit_confirmed:
				_play_sound(bounce_sounds, &"prism_bounce", contact.point, GameAudio.Kind.ATTACK)
			continue
		var end: Vector3 = start + shot.direction * distance
		shot.position = end
		shot.travelled += distance
		remaining -= distance
		shot.effect.move_to(end, shot.direction)
		if wall.is_empty():
			if stopped or shot.travelled >= shot.stats.distance - 0.00001: _finish_shot(shot)
			return
		var normal := ProjectileCollision.reflection_normal(wall.get("collider"), wall.normal, shot.direction)
		normal.y = 0.0
		normal = normal.normalized()
		shot.effect.show_contact(wall.point, true)
		var terrain_contact: bool = wall.get("collider") != null and session.terrain.is_ancestor_of(wall.collider)
		if wall.overlap or terrain_contact:
			_finish_shot(shot)
			return
		remaining = maxf(0.0, remaining - _reflect_shot(shot, normal))
		if shot not in _shots: return
		# 本次接触的宿主只按入射段命中一次，不在镜片内的零距离回程再扣血。
		if wall.get("collider") is ProjectileCollision.MIRROR_SURFACE:
			var source: WaveEnemy = wall.collider.enemy
			if is_instance_valid(source): shot.hits[source.get_instance_id()] = true
		ProjectileCollision.show_reflection(wall.get("collider"))
		_play_sound(bounce_sounds, &"prism_bounce", wall.point, GameAudio.Kind.ATTACK)
		wall_bounced.emit(wall.point, normal)
		if not _active() or shot not in _shots or shot.generation != session._generation: return

func _reflect_shot(shot: Dictionary, normal: Vector3) -> float:
	if normal.is_zero_approx() or shot.direction.dot(normal) >= -0.00001 or shot.bounces >= shot.stats.bounces:
		_finish_shot(shot)
		return 0.0
	shot.direction = shot.direction.bounce(normal).normalized()
	shot.bounces += 1
	shot.hits.clear()
	# Separation is real travelled distance, including for monster contacts.
	var separation := minf(0.003, shot.stats.distance - shot.travelled)
	shot.position += normal * separation
	shot.travelled += separation
	shot.effect.move_to(shot.position, shot.direction)
	if shot.travelled >= shot.stats.distance - 0.00001: _finish_shot(shot)
	return separation

func _finish_shot(shot: Dictionary) -> void:
	shot.effect.end_flight()
	_shots.erase(shot)

func _release_effect(effect: PrismRicochetEffect) -> void:
	if effect not in _idle_effects: _idle_effects.append(effect)

func cancel_current() -> void:
	_shots.clear()
	for effect in _effects:
		effect.stop()
		_release_effect(effect)
	if is_instance_valid(audio_manager): audio_manager.stop_source(self)

func _play_sound(clips: Array[AudioStream], cue: StringName, point: Vector3, kind: GameAudio.Kind) -> void:
	if not audio_enabled or clips.is_empty(): return
	if not is_instance_valid(audio_manager): audio_manager = get_tree().get_first_node_in_group(&"game_audio") as GameAudio
	if audio_manager:
		var event := {"source": self, "cue": cue, "clips": clips, "kind": kind,
			"position": point, "volume_db": -18.0, "pitch": randf_range(audio_pitch_range.x, audio_pitch_range.y)}
		# 单接触音模式独立合并；身体受击声不能吞掉棱晶的材质反馈。
		if not enemy_bounce_sound_enabled: event.merge_group = &"prism_contact"
		audio_manager.request(event)
