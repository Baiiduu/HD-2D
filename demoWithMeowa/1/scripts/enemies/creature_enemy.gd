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
	# 预告用透明度，保留完整原生像素尺寸。
	sprite.scale = _sprite_scale
	if wave_target and is_instance_valid(wave_target.sprite):
		sprite.pixel_size = wave_target.sprite.pixel_size * wave_target.sprite.global_basis.x.length()
	if attack_root:
		_feedback = attack_root.get_node_or_null("EnemyFeedbackPool")
		if not _feedback:
			_feedback = EnemyFeedbackPool.new()
			_feedback.name = "EnemyFeedbackPool"
			attack_root.add_child(_feedback)

func _physics_process(delta: float) -> void:
	if wave_mode and combat_active.is_valid() and not combat_active.call(): return
	super._physics_process(delta)

func _move_chase(delta: float, stop: float) -> void:
	var direction := Vector3.ZERO
	if TerrainPath.horizontal_distance(global_position, target.global_position) > stop:
		_route_clock -= delta
		if _route_clock <= 0.0:
			_route_clock = route_interval
			_route = navigation.shared_pursuit_route(global_position, target.global_position)
			_waypoint = 1 if _route.size() > 1 else 0
		if not _route.is_empty() and TerrainPath.horizontal_distance(global_position, _route[-1]) > 0.1:
			while _waypoint < _route.size() - 1 and TerrainPath.horizontal_distance(global_position, _route[_waypoint]) < 0.14: _waypoint += 1
			direction = _route[_waypoint] - global_position
			direction.y = 0.0
			direction = direction.normalized()
			if spatial_index: direction = (direction + spatial_index.separation(self, separation_radius) * separation_strength).normalized()
	_move_direction(direction, effective_move_speed(), delta)

func _move_direction(direction: Vector3, speed: float, delta: float) -> void:
	velocity.y = 0.0 if is_on_floor() else velocity.y - gravity * delta
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	if not direction.is_zero_approx(): _look = direction
	move_and_slide()

func _move_local(direction: Vector3, delta: float) -> void:
	var length := effective_move_speed() * delta
	var ground := navigation.ground_position(global_position)
	if _surface_collision.ground_limit(navigation, global_position, direction, length, ground.y, 0.2) < length: direction = Vector3.ZERO
	_move_direction(direction, effective_move_speed(), delta)

func _touch_player() -> void:
	if attack_damage <= 0.0 or not damage_player.is_valid(): return
	if TerrainPath.horizontal_distance(global_position, target.global_position) >= contact_distance or absf(global_position.y - target.global_position.y) >= contact_height: return
	if can_damage_player.is_valid() and not can_damage_player.call(attack_damage): return
	if _can_see_target(): damage_player.call(attack_damage)

func _idle_motion(delta: float) -> void:
	_move_direction(Vector3.ZERO, 0.0, delta)

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
	sprite.modulate = _sprite_color * (1.8 if _hit_flash > 0.0 else 1.0)
	sprite.modulate.a = _sprite_color.a * (0.4 if spawn_delay > 0.0 else 1.0)
	if not animations or not camera: return
	var right := camera.global_basis.x
	var backward := camera.global_basis.z
	right.y = 0.0
	backward.y = 0.0
	var facing := posmod(roundi(atan2(_look.dot(right.normalized()), _look.dot(backward.normalized())) / (TAU / 8.0)), 8)
	var direction: String = DIRECTIONS[facing]
	sprite.flip_h = "left" in direction
	direction = direction.replace("left", "right")
	var action: StringName = _visual_action if not _visual_action.is_empty() else (&"walk" if Vector2(velocity.x, velocity.z).length() > 0.05 else &"idle")
	var clip := StringName("%s_%s" % [action, direction])
	if not animations.has_animation(clip): clip = StringName("%s_front" % action)
	if not animations.has_animation(clip): return
	var count := animations.get_frame_count(clip)
	if count == 0: return
	if _visual_progress >= 0.0:
		sprite.texture = animations.get_frame_texture(clip, clampi(roundi(_visual_progress * (count - 1)), 0, count - 1))
		return
	if String(_clip).get_slice("_", 0) != String(action):
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
	sprite.texture = animations.get_frame_texture(clip, _frame)
