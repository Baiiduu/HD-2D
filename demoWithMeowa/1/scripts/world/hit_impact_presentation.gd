extends Node3D
## 只消费已扣血事件；不改伤害、出手间隔、位移或怪物招式。
const DEBRIS = preload("res://scripts/enemies/hit_debris.gd")
const SLASHES = preload("res://scripts/enemies/kill_slash.gd")
const SOURCES := [&"basic_sword", &"flight_sword", &"ricochet_storm"]
@export var session: WavePrototype
var debris: MultiMeshInstance3D
var slashes: MultiMeshInstance3D
var beats := 0
var stop_remaining := 0.0
var _camera: FollowCamera
var _clock := 0.0
var _hit_cooldown_until := 0.0
var _slash_ready := 0.0
var _last_hits: Dictionary[int, float] = {}
var _cooldown := 0.0
var _sword_cooldown := 0.0
var _beat_is_kill := false
var _saved_scale := 1.0
var _owned_scale := -1.0
var _charge: ChargePresentation
var _borrowed_time: RefCounted
var _borrowed_base := 1.0
var _age := 0.0
var _duration := 0.0
var _hold_seconds := 0.0
var _tail_seconds := 0.0
var _shake_seconds := 0.0
var _shake_size := 0.0
var _shake_axis := Vector3.ZERO
var _shake_side := Vector3.ZERO
var _group_count := 0
var _group_point := Vector3.ZERO
var _group_until := 0.0
var _shot_point := Vector3.ZERO
var _shot_age := 0.0
var _shot_seconds := 0.0
var _shot_enter := 0.0
var _shot_cooldown := 0.0
var _zoom := 1.0
var _last_tick := 0

func _ready() -> void:
	process_priority = 5
	add_to_group(&"hit_impact_presentations")
	debris = DEBRIS.new()
	add_child(debris)
	slashes = SLASHES.new()
	add_child(slashes)
	set_process(false)
	if not is_instance_valid(session): return
	_camera = session.player.movement_camera as FollowCamera
	_charge = session.get_parent().get_node_or_null("MapEffects/ChargePresentation") as ChargePresentation
	session.enemy_spawned.connect(_watch)
	session.run_started.connect(clear)
	session.run_ended.connect(func(_reason): clear())
	session.phase_changed.connect(_phase_changed)
	session.combat_frozen_changed.connect(_frozen_changed)
	for enemy in session.enemies: _watch(enemy)

func _settings() -> PlayerActionVisuals:
	return session.player.action_visuals if is_instance_valid(session) and is_instance_valid(session.player) else null

func _watch(enemy: WaveEnemy) -> void:
	if not enemy.damaged.is_connected(_damaged.bind(enemy)): enemy.damaged.connect(_damaged.bind(enemy))
	var id := enemy.get_instance_id()
	enemy.tree_exiting.connect(func(): _last_hits.erase(id), CONNECT_ONE_SHOT)

func _damaged(event: CombatDamageEvent, enemy: WaveEnemy) -> void:
	var settings := _settings()
	if not settings or event.source not in SOURCES or event.display_amount() <= 0.0: return
	if session.phase != WavePrototype.Phase.BATTLE or session.combat_frozen: return
	var emit_debris: bool = settings.hit_debris_enabled and (event.lethal or _clock >= _last_hits.get(event.target_id, -1.0))
	var emit_slash := settings.kill_slash_enabled and settings.kill_slash_texture != null and event.lethal and not event.simulated and _clock >= _slash_ready
	var camera_kill := settings.kill_impact_enabled and event.lethal and not event.simulated
	var emit_beat := camera_kill and _cooldown <= 0.0
	var emit_sword_beat := settings.sword_hit_impact_enabled and event.source == &"basic_sword" and not event.lethal and not event.simulated and _cooldown <= 0.0 and _sword_cooldown <= 0.0 and _age >= _duration and _shot_age >= _shot_seconds
	var collect_group := camera_kill and settings.kill_shot_enabled
	if emit_beat or emit_sword_beat or collect_group:
		if not is_instance_valid(_camera) or _camera.wave_shot_active or get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null:
			emit_beat = false
			emit_sword_beat = false
			collect_group = false
	if not emit_debris and not emit_slash and not emit_beat and not emit_sword_beat and not collect_group: return
	var heading := event.slash_direction if not event.slash_direction.is_zero_approx() else event.direction
	heading.y = 0.0
	if heading.is_zero_approx(): heading = enemy.global_position - session.player.global_position
	heading.y = 0.0
	if heading.is_zero_approx(): heading = Vector3.FORWARD
	heading = heading.normalized()
	var sprite := enemy.get_node_or_null("Sprite") as Sprite3D
	var contact := Vector3.ZERO
	if emit_debris or emit_slash or collect_group:
		contact = sprite.global_position if event.lethal and sprite else enemy.get_contact_feedback_position(session.player.global_position)
	if emit_debris:
		if sprite:
			debris.burst(contact, heading, sprite.pixel_size * sprite.global_basis.x.length(), settings, event.lethal and not event.simulated)
			_last_hits[event.target_id] = _clock + settings.hit_debris_interval
			_hit_cooldown_until = maxf(_hit_cooldown_until, _last_hits[event.target_id])
	if emit_slash:
		var actor := session.player.sprite
		if is_instance_valid(_camera) and actor:
			slashes.burst(contact, heading, actor.pixel_size * actor.global_basis.x.length(), _camera, settings)
			_slash_ready = _clock + settings.kill_slash_interval
	if emit_beat:
		_begin_beat(settings, heading)
	elif emit_sword_beat:
		_begin_beat(settings, heading, false)
	# 群杀推进独立于单杀短顿；后续击杀不重启正在播放的推进。
	if collect_group: _collect_group(settings, contact)
	if debris.active or slashes.active or _age < _duration or collect_group: _wake()

func _wake() -> void:
	if not is_processing(): _last_tick = Time.get_ticks_usec()
	set_process(true)

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_delta := maxf(0.0, (now - _last_tick) / 1000000.0)
	_last_tick = now
	advance(real_delta)

func advance(real_delta: float) -> void:
	var settings := _settings()
	if not settings or not is_instance_valid(_camera):
		clear()
		return
	var step := maxf(real_delta, 0.0)
	_clock += step
	_cooldown = maxf(0.0, _cooldown - step)
	_sword_cooldown = maxf(0.0, _sword_cooldown - step)
	_shot_cooldown = maxf(0.0, _shot_cooldown - step)
	if _clock >= _group_until: _group_count = 0
	if session.combat_frozen:
		cancel_beat()
		return
	if settings.hit_debris_enabled: debris.advance(step)
	else: debris.clear()
	if settings.kill_slash_enabled: slashes.advance(step)
	else: slashes.clear()
	var blocked := get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null
	if blocked or _camera.wave_shot_active or session.phase != WavePrototype.Phase.BATTLE:
		cancel_beat()
	else:
		if _age < _duration:
			var beat_enabled := settings.kill_impact_enabled if _beat_is_kill else settings.sword_hit_impact_enabled
			if beat_enabled:
				_age += step
				_advance_time()
			else:
				_age = _duration
				stop_remaining = 0.0
				_release_time()
		if not settings.kill_impact_enabled or not settings.kill_shot_enabled:
			_shot_age = _shot_seconds
			_group_count = 0
		elif _shot_age < _shot_seconds:
			_shot_age += step
		if _camera.hit_shot_active: _apply_shot()
	if not debris.active and not slashes.active and _age >= _duration and _shot_age >= _shot_seconds and _group_count == 0 and _cooldown == 0.0 and _sword_cooldown == 0.0 and _shot_cooldown == 0.0 and _clock >= maxf(_hit_cooldown_until, _slash_ready):
		set_process(false)

func _begin_beat(settings: PlayerActionVisuals, heading: Vector3, killed := true) -> void:
	# 同刀先伤后杀只增强当前一下，不重复起播或借用自己的近零时间基准。
	var upgrading := killed and not _beat_is_kill and _age < minf(_duration, 0.05)
	if not upgrading:
		beats += 1
		_age = 0.0
	_beat_is_kill = killed
	_hold_seconds = clampf(settings.kill_hitstop_seconds if killed else settings.sword_hitstop_seconds, 0.0, 0.2)
	# 蹬墙关键动作持续展开；保留命中视觉，短慢动作期间不再叠加定格。
	if is_instance_valid(_charge) and _charge.bounce_slow_active: _hold_seconds = 0.0
	_tail_seconds = clampf(settings.kill_slow_tail_seconds, 0.0, 0.2) if killed and _hold_seconds > 0.0 else 0.0
	_shake_seconds = maxf(settings.kill_shake_seconds if killed else settings.sword_hit_shake_seconds, 0.01)
	_duration = maxf(_hold_seconds + _tail_seconds, _shake_seconds)
	if killed: _cooldown = maxf(settings.kill_hitstop_interval, _duration + 0.12)
	else: _sword_cooldown = maxf(settings.sword_hit_impact_interval, _duration + 0.1)
	var viewport_size := get_viewport().get_visible_rect().size
	var short_side := maxf(1.0, minf(viewport_size.x, viewport_size.y))
	_shake_size = _camera._short_side_span() * clampf(settings.kill_shake_pixels if killed else settings.sword_hit_shake_pixels, 0.0, 16.0) / short_side
	if not upgrading:
		_shake_axis = (heading - _camera.global_basis.z * heading.dot(_camera.global_basis.z)).normalized()
		_shake_side = _camera.global_basis.z.cross(_shake_axis).normalized()
	_camera.hit_shot_active = true
	stop_remaining = maxf(0.0, _hold_seconds - _age)
	# 在真实命中信号中立即留住这一帧，允许借用弹射慢动作，结束归还原基准。
	if stop_remaining > 0.0 and Engine.time_scale > 0.001:
		_saved_scale = Engine.time_scale
		_borrowed_time = null
		if is_instance_valid(_charge) and _charge._time_scale.active and is_equal_approx(_charge._time_scale.get("_owned_scale"), _saved_scale):
			_borrowed_time = _charge._time_scale
			_borrowed_base = _borrowed_time.get("_saved_scale")
		_owned_scale = 0.001
		_camera.hit_stop_active = true
		Engine.time_scale = _owned_scale
	_set_actor_hold(stop_remaining > 0.0 and _owned_scale >= 0.0 and is_equal_approx(Engine.time_scale, _owned_scale))
	_apply_shot()

func _collect_group(settings: PlayerActionVisuals, point: Vector3) -> void:
	if _shot_age < _shot_seconds or _shot_cooldown > 0.0: return
	if _group_count == 0 or _clock >= _group_until:
		_group_count = 0
		_group_point = Vector3.ZERO
		_group_until = _clock + maxf(settings.kill_shot_group_window, 0.01)
	_group_point += point
	_group_count += 1
	if _group_count < maxi(2, settings.kill_shot_minimum_kills): return
	_shot_point = _group_point / _group_count
	_group_count = 0
	_shot_age = 0.0
	_shot_seconds = maxf(settings.kill_shot_seconds, 0.25)
	_shot_enter = clampf(settings.kill_shot_enter_seconds, 0.06, _shot_seconds * 0.5)
	_shot_cooldown = maxf(settings.kill_shot_interval, _shot_seconds + 0.12)
	_zoom = clampf(settings.kill_shot_zoom_scale, 0.6, 1.0)
	_camera.hit_shot_active = true
	_apply_shot()

func _advance_time() -> void:
	stop_remaining = maxf(0.0, _hold_seconds - _age)
	_set_actor_hold(stop_remaining > 0.0 and _owned_scale >= 0.0 and is_equal_approx(Engine.time_scale, _owned_scale))
	if _owned_scale < 0.0: return
	if not is_equal_approx(Engine.time_scale, _owned_scale):
		_owned_scale = -1.0
		_borrowed_time = null
		_camera.hit_stop_active = false
		return
	if _age >= _hold_seconds + _tail_seconds:
		_release_time()
	elif _age >= _hold_seconds:
		var t := (_age - _hold_seconds) / maxf(_tail_seconds, 0.001)
		_owned_scale = maxf(0.001, _saved_scale * lerpf(0.28, 1.0, smoothstep(0.3, 1.0, t)))
		Engine.time_scale = _owned_scale

static func shake_curve(age: float, seconds: float) -> Vector3:
	if age <= 0.0 or age >= seconds: return Vector3.ZERO
	var fade := minf(1.0, age / 0.012) * pow(1.0 - age / seconds, 1.25)
	var x := sin(TAU * 25.0 * age + 0.35 * sin(TAU * 7.0 * age)) * 0.7 + sin(TAU * 43.0 * age) * 0.3
	var y := sin(TAU * 31.0 * age + 0.8) * 0.65 + sin(TAU * 17.0 * age) * 0.35
	var roll := sin(TAU * 19.0 * age + 0.4) * 0.5
	return Vector3(x, y, roll).limit_length(1.0) * fade

func _apply_shot() -> void:
	var impact_active := _age < _duration
	var shot_active := _shot_age < _shot_seconds
	var weight := 0.0
	if shot_active:
		var enter := smoothstep(0.0, _shot_enter, _shot_age)
		var leave := 1.0 - smoothstep(_shot_seconds * 0.55, _shot_seconds, _shot_age)
		weight = enter * leave
	_camera.hit_shot_active = impact_active or shot_active
	_camera.hit_closeup_active = shot_active
	_camera.hit_shot_focus = _camera.focus + (_shot_point - _camera.focus).limit_length(1.0) if shot_active else Vector3.ZERO
	_camera.hit_shot_weight = weight * 0.25
	_camera.hit_shot_distance_scale = lerpf(1.0, _zoom, weight)
	var curve := shake_curve(_age, _shake_seconds) if impact_active else Vector3.ZERO
	_camera.hit_shake_offset = (_shake_axis * curve.x + _shake_side * curve.y) * _shake_size * _camera.hit_shot_distance_scale
	_camera.hit_shake_roll = curve.z * 0.6 * (1.0 if _beat_is_kill else 0.35)
	if _camera.is_processing(): _camera._apply_transform()

func _release_time() -> void:
	_set_actor_hold(false)
	if _owned_scale >= 0.0 and is_equal_approx(Engine.time_scale, _owned_scale):
		Engine.time_scale = _borrowed_base if _borrowed_time and not _borrowed_time.get("active") else _saved_scale
	_owned_scale = -1.0
	_borrowed_time = null
	if is_instance_valid(_camera): _camera.hit_stop_active = false

func _set_actor_hold(holding: bool) -> void:
	if is_instance_valid(session) and is_instance_valid(session.player): session.player.hit_stop_active = holding

func cancel_beat() -> void:
	_release_time()
	stop_remaining = 0.0
	_age = _duration
	_shot_age = _shot_seconds
	_group_count = 0
	if is_instance_valid(_camera):
		_camera.hit_shot_active = false
		_camera.hit_closeup_active = false
		_camera.hit_shot_weight = 0.0
		_camera.hit_shot_distance_scale = 1.0
		_camera.hit_shot_focus = Vector3.ZERO
		_camera.hit_shake_offset = Vector3.ZERO
		_camera.hit_shake_roll = 0.0
		if _camera.is_processing() and _camera.is_inside_tree() and is_instance_valid(_camera.target) and _camera.target.is_inside_tree(): _camera._apply_transform()

func clear() -> void:
	cancel_beat()
	_last_hits.clear()
	_clock = 0.0
	_hit_cooldown_until = 0.0
	_slash_ready = 0.0
	_cooldown = 0.0
	_sword_cooldown = 0.0
	_shot_cooldown = 0.0
	if is_instance_valid(debris): debris.clear()
	if is_instance_valid(slashes): slashes.clear()
	set_process(false)

func _phase_changed(phase: WavePrototype.Phase) -> void:
	if phase == WavePrototype.Phase.REST: cancel_beat()
	elif phase != WavePrototype.Phase.BATTLE: clear()

func _frozen_changed(frozen: bool) -> void:
	if frozen:
		cancel_beat()
		set_process(false)
	elif debris.active or slashes.active or _age < _duration or _cooldown > 0.0 or _sword_cooldown > 0.0 or _shot_cooldown > 0.0 or _clock < maxf(_hit_cooldown_until, _slash_ready): _wake()

func _exit_tree() -> void:
	clear()
