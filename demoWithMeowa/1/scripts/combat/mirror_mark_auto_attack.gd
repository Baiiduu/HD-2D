class_name MirrorMarkAutoAttack
extends PrismRicochetAutoAttack

signal mirror_reflected(enemy: WaveEnemy, point: Vector3, normal: Vector3)

@export_group("反射镜印")
@export var mark_scene: PackedScene
@export_range(0.5, 12.0, 0.5, "suffix:s") var mark_duration := 4.0
@export_range(1, 12, 1) var reflection_limit := 2
## 读取人物实际 Sprite 缩放后的像素密度；关闭后使用各特效场景的 pixel_size。
@export var match_player_pixel_density := true

var _marks: Dictionary[int, Dictionary] = {}
var _mark_effects: Array[MirrorMarkEffect] = []
var _idle_marks: Array[MirrorMarkEffect] = []

func get_attack_stats(level := -1, modifiers: RunCombatModifiers = null) -> Dictionary:
	var stats := super.get_attack_stats(level, modifiers)
	if level < 0: level = skill_level
	var data := skill_definition.level_data(level) if skill_definition else null
	var values: Dictionary = data.parameters if data else {}
	stats.bounces = int(values.get("reflections", reflection_limit))
	stats.mark_duration = mark_duration * values.get("mark_duration_multiplier", 1.0)
	return stats

func get_combat_stats(modifiers: RunCombatModifiers = null) -> Dictionary:
	if not enabled or skill_level <= 0: return {}
	var stats := get_attack_stats(skill_level, modifiers)
	var result := {"name": "反射镜印", "damage": stats.damage, "interval": stats.interval}
	if session and session.growth_rules: result.range = stats.distance
	return result

func describe_skill_upgrade(from_level: int, to_level: int) -> String:
	var after := get_attack_stats(to_level)
	if from_level == 0:
		return CARD_TEXT.compose("镜梭命中贴印并反弹\n人物与弹丸可借镜反射", PackedStringArray([
			"伤害 %s · 齐射 %d 枚" % [CARD_TEXT.number(after.damage, 1), after.count],
			"每枚反射 %d 次" % after.bounces,
			"镜印持续 %s 秒" % CARD_TEXT.number(after.mark_duration, 1),
			"释放间隔 %s 秒" % CARD_TEXT.number(after.interval)]))
	var before := get_attack_stats(from_level)
	return CARD_TEXT.skill("", false, before, after, [
		["damage", "伤害", 1, ""], ["count", "齐射", 0, " 枚"], ["bounces", "每枚反射", 0, " 次"],
		["mark_duration", "镜印持续", 1, " 秒"], ["interval", "间隔", 2, " 秒"], ["distance", "飞行距离", 1, " 米"]])

func _physics_process(delta: float) -> void:
	if not _active(): return
	_tick_marks(delta)
	super._physics_process(delta)

func launch(point: Vector3, direction: Vector3, stats: Dictionary) -> void:
	super.launch(point, direction, stats)
	var effect: MirrorProjectileEffect = _shots[-1].effect
	if not effect.has_meta(&"base_pixel_size"): effect.set_meta(&"base_pixel_size", effect.pixel_size)
	effect.pixel_size = (_player_pixel_size() if match_player_pixel_density else float(effect.get_meta(&"base_pixel_size"))) * float(stats.get("growth_scale", 1.0))
	effect.motion_speed = stats.speed
	effect._update_head(get_viewport().get_camera_3d())

func _player_pixel_size() -> float:
	var sprite := session.player.sprite
	return sprite.pixel_size * sprite.global_basis.x.length()

func _tick_marks(delta: float) -> void:
	for id in _marks.keys():
		var mark := _marks[id]
		mark.remaining -= delta
		if not is_instance_valid(mark.enemy) or mark.enemy.dead or mark.remaining <= 0.0:
			mark.effect.shatter(mark.effect._sprite.global_position)
			_marks.erase(id)

## 首次命中选定镜面朝向，之后只跟随位置、不重新瞄准。
## 无侧向目标时固定折向侧面；后续命中仍严格使用入射方向与保存的法线。
func _new_normal(enemy: WaveEnemy, point: Vector3, shot: Dictionary) -> Vector3:
	var desired: Vector3 = shot.direction.rotated(Vector3.UP, PI * 0.5)
	var nearest: float = pow(shot.stats.distance - shot.travelled, 2)
	for candidate in session.enemies:
		if not is_instance_valid(candidate) or candidate == enemy: continue
		# 遍历的对象已经属于本局，避免对每个候选再线性扫描一次 enemies。
		if candidate.dead or candidate.spawn_delay > 0.0 or shot.hits.has(candidate.get_instance_id()) or absf(candidate.global_position.y - shot.plane) > shot.tolerance: continue
		var offset := candidate.global_position - point
		offset.y = 0.0
		var distance := offset.length_squared()
		if distance < 0.00001 or distance >= nearest: continue
		var direction := offset.normalized()
		if direction.dot(shot.direction) > 0.94: continue
		nearest = distance
		desired = direction
	return (desired - shot.direction).normalized()

func prepare_feedback() -> void:
	super.prepare_feedback()
	if not mark_scene or not _mark_effects.is_empty(): return
	var effect := _acquire_mark()
	effect.prepare_feedback()
	_release_mark(effect)

func _acquire_mark() -> MirrorMarkEffect:
	var effect: MirrorMarkEffect
	if not _idle_marks.is_empty(): effect = _idle_marks.pop_back()
	else:
		effect = mark_scene.instantiate()
		add_child(effect)
		_mark_effects.append(effect)
		effect.finished.connect(_release_mark.bind(effect))
	if match_player_pixel_density: effect.pixel_size = _player_pixel_size()
	return effect

func _release_mark(effect: MirrorMarkEffect) -> void:
	if effect not in _idle_marks: _idle_marks.append(effect)

func _hit_mirror(enemy: WaveEnemy, shot: Dictionary) -> void:
	var id := enemy.get_instance_id()
	var surface_normal: Vector3 = _marks[id].normal if _marks.has(id) else _new_normal(enemy, shot.position, shot)
	var point := enemy.global_position
	shot.hits[id] = true
	var before := enemy.health
	enemy.take_damage(shot.stats.damage, {"source": &"mirror_mark", "direction": shot.direction})
	var dealt := before - enemy.health
	# 回调可能结束本局；不把旧局镜印带进下一局。
	if shot not in _shots or shot.generation != session._generation: return
	if dealt <= 0.0 and not session.combat_modifiers.damage_disabled: return
	var mark: Dictionary
	if _marks.has(id):
		mark = _marks[id]
		mark.remaining = shot.stats.mark_duration
		mark.effect.glint()
	else:
		var effect := _acquire_mark()
		effect.attach(enemy, surface_normal)
		mark = {"enemy": enemy, "normal": surface_normal, "remaining": shot.stats.mark_duration, "effect": effect}
		_marks[id] = mark
	if enemy.dead:
		mark.effect.shatter(point + Vector3.UP * mark.effect.attachment_height)
		_marks.erase(id)
	_play_sound(hit_sounds, &"mirror_hit", point, GameAudio.Kind.HIT)
	# 致死命中也保留缓存的法线完成最后反射，不依赖仍然存活的碰撞体。
	if shot.bounces < shot.stats.bounces:
		shot.direction = shot.direction.bounce(surface_normal).normalized()
		shot.bounces += 1
		mirror_reflected.emit(enemy, shot.position, surface_normal)
		_play_sound(bounce_sounds, &"mirror_reflect", point, GameAudio.Kind.ATTACK)
	else: _finish_shot(shot)
	hit_landed.emit(enemy, dealt)

func _advance_shot(shot: Dictionary, delta: float) -> void:
	if shot.generation != session._generation or shot not in _shots: return
	var remaining: float = minf(shot.stats.speed * delta, shot.stats.distance - shot.travelled)
	var space := get_world_3d().direct_space_state
	while remaining > 0.00001:
		if not _active() or shot not in _shots: return
		var start: Vector3 = shot.position
		var distance := _collision.ground_limit(session._path, start, shot.direction, remaining, shot.plane, shot.tolerance)
		var stopped := distance < remaining - 0.00001
		var wall := _collision.wall_contact(space, start, start + shot.direction * distance, shot.stats.radius, [session.player.get_rid()])
		if not wall.is_empty(): distance = minf(distance, wall.distance)
		var contacts := _collision.enemy_contacts(space, start, start + shot.direction * distance, shot.stats.radius, _eligible.bind(shot))
		var hit: Dictionary = contacts[0] if not contacts.is_empty() else {}
		var enemy_first: bool = not hit.is_empty() and (wall.is_empty() or hit.distance < distance - 0.00001)
		if enemy_first: distance = hit.distance
		shot.position = start + shot.direction * distance
		shot.travelled += distance
		remaining -= distance
		shot.effect.move_to(shot.position, shot.direction)
		if enemy_first:
			_hit_mirror(hit.enemy, shot)
			# 每弹全程保留 hits，怪物镜印和墙面都不能清空去重记录。
			if shot not in _shots: return
			if shot.travelled >= shot.stats.distance - 0.00001: _finish_shot(shot)
			continue
		if wall.is_empty():
			if stopped or shot.travelled >= shot.stats.distance - 0.00001: _finish_shot(shot)
			return
		var normal: Vector3 = wall.normal
		normal.y = 0.0
		normal = normal.normalized()
		shot.effect.show_contact(wall.point, true)
		var terrain_contact: bool = wall.get("collider") != null and session.terrain.is_ancestor_of(wall.collider)
		if wall.overlap or terrain_contact or normal.is_zero_approx() or shot.direction.dot(normal) >= -0.00001 or shot.bounces >= shot.stats.bounces:
			_finish_shot(shot)
			return
		shot.direction = shot.direction.bounce(normal).normalized()
		shot.bounces += 1
		wall_bounced.emit(wall.point, normal)
		_play_sound(bounce_sounds, &"mirror_wall", wall.point, GameAudio.Kind.ATTACK)
		if not _active() or shot not in _shots: return
		var separation := minf(0.003, shot.stats.distance - shot.travelled)
		shot.position += normal * separation
		shot.travelled += separation
		remaining = maxf(0.0, remaining - separation)
		shot.effect.move_to(shot.position, shot.direction)
		if shot.travelled >= shot.stats.distance - 0.00001: _finish_shot(shot)

func cancel_current() -> void:
	super.cancel_current()
	_marks.clear()
	for effect in _mark_effects:
		effect.stop()
		_release_mark(effect)
