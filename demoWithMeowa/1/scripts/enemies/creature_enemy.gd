class_name CreatureEnemy
extends SlimeEnemy

@export var attack_sound: AudioStream
@export var death_sound: AudioStream
@export var death_shards := false
var _visual_action: StringName = &""
var _visual_progress := -1.0
var _feedback: EnemyFeedbackPool
var _surface_collision := ProjectileCollision.new()

func _ready() -> void:
	super._ready()
	# 出生直接保留完整原生像素尺寸。
	sprite.scale = _sprite_scale
	if wave_target and is_instance_valid(wave_target.sprite):
		sprite.pixel_size = wave_target.sprite.pixel_size * wave_target.sprite.global_basis.x.length()
	if attack_root:
		_feedback = attack_root.get_node_or_null("EnemyFeedbackPool")
		if not _feedback:
			_feedback = EnemyFeedbackPool.new()
			_feedback.name = "EnemyFeedbackPool"
			attack_root.add_child(_feedback)

func _on_stun_started() -> void:
	_release_warning()
	_visual_action = &""
	_visual_progress = -1.0
	super._on_stun_started()

func _move_chase(delta: float, stop: float) -> void:
	if _try_native_chase(delta, stop): return
	var origin := global_position
	var goal := target.global_position
	var away := origin - goal
	away.y = 0.0
	var target_distance := TerrainPath.horizontal_distance(origin, goal)
	var direction := Vector3.ZERO
	stop = _personal_stop_distance(stop)
	if target_distance > stop:
		_route_clock -= delta
		if _route_clock <= 0.0:
			_route_clock = route_interval
			_route = navigation.chase_route(origin, goal, pursuit_lookahead)
			_waypoint = 1 if _route.size() > 1 else 0
		if not _route.is_empty() and TerrainPath.horizontal_distance(origin, _route[-1]) > 0.1:
			while _waypoint < _route.size() - 1 and TerrainPath.horizontal_distance(origin, _route[_waypoint]) < 0.14: _waypoint += 1
			direction = _route[_waypoint] - origin
			direction.y = 0.0
			direction = direction.normalized()
	var intended := direction
	direction = _pursuit_crowd_direction(direction, origin, target_distance)
	var actual_speed := effective_move_speed()
	direction = _personal_space_direction(direction, stop, away, target_distance, actual_speed)
	_move_direction(direction, actual_speed, delta, true)
	_update_chase_facing(intended)

func _move_direction(direction: Vector3, speed: float, delta: float, ordinary_chase := false) -> void:
	velocity.y = 0.0 if is_on_floor() or (ordinary_chase and _ground_moved) else velocity.y - gravity * delta
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if ordinary_chase: _move_combat_body(delta)
	else:
		_ground_moved = false
		move_and_slide()

func _move_local(direction: Vector3, delta: float) -> void:
	var intended := direction
	direction = _crowd_direction(direction)
	var origin := global_position
	var away := Vector3.INF
	if target is Player and (target as Player).crowd_clearance_distance > 0.0:
		away = origin - target.global_position
		away.y = 0.0
	var actual_speed := effective_move_speed()
	direction = _personal_space_direction(direction, _personal_stop_distance(combat_stop_distance), away, -1.0, actual_speed)
	var length := direction.length() * actual_speed * delta
	var ground := navigation.ground_position(origin)
	if length > 0.0 and _surface_collision.ground_limit(navigation, origin, direction.normalized(), length, ground.y, 0.2) < length: direction = Vector3.ZERO
	_move_direction(direction, actual_speed, delta)
	if not intended.is_zero_approx(): _look = intended.normalized()
	else: _update_chase_facing(Vector3.ZERO)

func _touch_player() -> void:
	if attack_damage <= 0.0 or not damage_player.is_valid(): return
	if TerrainPath.horizontal_distance(global_position, target.global_position) >= contact_distance or absf(global_position.y - target.global_position.y) >= contact_height: return
	if can_damage_player.is_valid() and not can_damage_player.call(attack_damage): return
	if _can_see_target(): damage_player.call(attack_damage)

func _idle_motion(delta: float, yield_space := false) -> void:
	if yield_space: _move_local(Vector3.ZERO, delta)
	else: _move_direction(Vector3.ZERO, 0.0, delta)

## 所有新怪物共用两处主预告预算；尸体、取消与退出立即释放。
func _claim_warning() -> bool:
	if not is_instance_valid(attack_root): return false
	var claims: Dictionary = attack_root.get_meta(&"enemy_warnings", {})
	for id in claims.keys():
		var enemy: WaveEnemy = claims[id].get_ref()
		if not is_instance_valid(enemy) or enemy.dead: claims.erase(id)
	if claims.size() >= 2 and not claims.has(get_instance_id()): return false
	claims[get_instance_id()] = weakref(self)
	attack_root.set_meta(&"enemy_warnings", claims)
	return true

func _release_warning() -> void:
	if not is_instance_valid(attack_root): return
	var claims: Dictionary = attack_root.get_meta(&"enemy_warnings", {})
	claims.erase(get_instance_id())

func _sound(clip: AudioStream, cue: StringName, kind: GameAudio.Kind) -> void:
	if clip and is_instance_valid(_feedback): _feedback.play_sound(clip, cue, global_position, kind)

func _on_defeated() -> void:
	_release_warning()
	if is_instance_valid(_feedback): _feedback.death(sprite, death_shards)
	_sound(death_sound, &"creature_death", GameAudio.Kind.DEATH)

func cancel() -> void:
	_release_warning()
	super.cancel()

func _exit_tree() -> void:
	_release_warning()
	super._exit_tree()

func _process(delta: float) -> void:
	_hit_flash = maxf(0.0, _hit_flash - delta)
	var tint := _sprite_color * (1.8 if _hit_flash > 0.0 else 1.0)
	tint.a = _sprite_color.a
	if sprite.modulate != tint: sprite.modulate = tint
	if not animations or not camera: return
	var facing := _camera_facing_index()
	var flip := facing >= 5
	if sprite.flip_h != flip: sprite.flip_h = flip
	var action: StringName = _visual_action if not _visual_action.is_empty() else (&"walk" if Vector2(velocity.x, velocity.z).length() > 0.05 else &"idle")
	var clips := _clips_for(action)
	var clip: StringName = clips[MIRRORED_FACINGS[facing]]
	if not animations.has_animation(clip): clip = clips[0]
	if not animations.has_animation(clip): return
	var count := animations.get_frame_count(clip)
	if count == 0: return
	if _visual_progress >= 0.0:
		var texture := animations.get_frame_texture(clip, clampi(roundi(_visual_progress * (count - 1)), 0, count - 1))
		if sprite.texture != texture: sprite.texture = texture
		return
	if _clip_action(_clip) != action:
		_frame = 0
		_elapsed = 0.0
	_clip = clip
	_frame %= count
	var fps := animations.get_animation_speed(clip)
	if fps <= 0.0: return
	_elapsed += delta * animation_speed
	var duration := animations.get_frame_duration(clip, _frame) / fps
	while _elapsed >= duration:
		_elapsed -= duration
		_frame = (_frame + 1) % count
		duration = animations.get_frame_duration(clip, _frame) / fps
	var texture := animations.get_frame_texture(clip, _frame)
	if sprite.texture != texture: sprite.texture = texture
