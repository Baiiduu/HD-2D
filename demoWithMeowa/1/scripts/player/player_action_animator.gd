class_name PlayerActionAnimator
extends RefCounted

signal bounce_started

var bouncing: bool:
	get: return _attack == &"bounce"
var player: Player
var visuals: PlayerActionVisuals
var _context: StringName = &""
var _heading := Vector3.RIGHT
var _progress := -1.0
var _context_age := 0.0
var _attack: StringName = &""
var _attack_age := 0.0
var _attack_duration := 0.3
var _attack_heading := Vector3.RIGHT
var _attack_synced := false
var _attack_phases := Vector3.ZERO
var _attack_frame_breaks := Vector2.ZERO
var _attack_flip := false

func set_context(action: StringName, heading: Vector3, progress := -1.0) -> void:
	if _context != action: _context_age = 0.0
	_context = action
	_heading = heading
	_progress = progress

func request_attack(action: StringName, heading: Vector3) -> bool:
	if not _attack.is_empty(): return false
	_attack = action
	_attack_heading = heading
	_attack_age = 0.0
	var clip := _resolve(action, heading)
	_attack_duration = visuals.placeholder_attack_seconds if visuals else 0.3
	if not clip.is_empty():
		_attack_duration = 0.0
		for frame in clip.frames.get_frame_count(clip.name):
			_attack_duration += clip.frames.get_frame_duration(clip.name, frame) / clip.frames.get_animation_speed(clip.name)
	return true

func cancel_attack() -> void:
	_attack = &""
	_attack_age = 0.0
	_attack_synced = false

## 消费真实出剑事件与本刀快照时长；显示不能反过来限制出手。
func play_attack(action: StringName, heading: Vector3, duration: float) -> void:
	# 仅让位显示；真实剑术已经独立出手，伤害与攻击时钟继续运行。
	if _attack == &"bounce": return
	cancel_attack()
	request_attack(action, heading)
	_attack_duration = maxf(duration, 0.00001)

## 空槽保持当前动画。以后填入素材即可由真实反弹播放一次。
func request_bounce(heading: Vector3) -> bool:
	if _resolve(&"bounce", heading).is_empty():
		cancel_bounce()
		return false
	cancel_attack()
	var started := request_attack(&"bounce", heading)
	if started: bounce_started.emit()
	return started

func cancel_bounce() -> void:
	if _attack == &"bounce": cancel_attack()

func cancel_normal_attack() -> void:
	if _attack == &"normal_attack": cancel_attack()

## 普攻只按真实起手／扫刃／收刀时钟读取原帧，不追踪剑尖或重做人物素材。
func sync_normal_attack(age: float, phases: Vector3, frame_breaks: Vector2, flip: bool) -> void:
	if _attack != &"normal_attack": return
	if age < 0.0:
		cancel_normal_attack()
		return
	_attack_synced = true
	_attack_age = age
	_attack_phases = phases
	_attack_frame_breaks = frame_breaks
	_attack_flip = flip

func _synced_progress() -> float:
	if _attack_age < _attack_phases.x:
		return _attack_frame_breaks.x * _attack_age / maxf(_attack_phases.x, 0.000001)
	if _attack_age < _attack_phases.x + _attack_phases.y:
		return lerpf(_attack_frame_breaks.x, _attack_frame_breaks.y, (_attack_age - _attack_phases.x) / maxf(_attack_phases.y, 0.000001))
	return lerpf(_attack_frame_breaks.y, 1.0, clampf((_attack_age - _attack_phases.x - _attack_phases.y) / maxf(_attack_phases.z, 0.000001), 0.0, 1.0))

func render(delta: float) -> bool:
	_context_age += delta
	if not _attack.is_empty():
		if not _attack_synced: _attack_age += delta
		if _attack_age >= _attack_duration: cancel_attack()
	var attack_active := not _attack.is_empty() and _context != &"charge"
	var action: StringName = _attack if attack_active else _context
	var heading := _attack_heading if attack_active else _heading
	var clip := _resolve(action, heading)
	if clip.is_empty() and attack_active:
		attack_active = false
		clip = _resolve(_context, _heading)
	if clip.is_empty(): return false
	var frames: SpriteFrames = clip.frames
	var name: StringName = clip.name
	var count := frames.get_frame_count(name)
	var frame := 0
	if not attack_active and _progress >= 0.0:
		frame = clampi(roundi(clampf(_progress, 0.0, 1.0) * (count - 1)), 0, count - 1)
	else:
		var total := 0.0
		for index in count: total += frames.get_frame_duration(name, index)
		var elapsed := _attack_age / _attack_duration * total if attack_active else _context_age * frames.get_animation_speed(name)
		if attack_active and _attack_synced: elapsed = _synced_progress() * total + 0.000001
		if not attack_active and frames.get_animation_loop_mode(name) != SpriteFrames.LOOP_NONE: elapsed = fmod(elapsed, total)
		while frame < count - 1 and elapsed >= frames.get_frame_duration(name, frame):
			elapsed -= frames.get_frame_duration(name, frame)
			frame += 1
	player.sprite.flip_h = _attack_flip if attack_active and _attack_synced else clip.flip
	player.sprite.texture = frames.get_frame_texture(name, frame)
	return true

func _resolve(action: StringName, heading: Vector3) -> Dictionary:
	if not visuals or not is_instance_valid(player): return {}
	var frames := visuals.frames_for(action)
	if not frames: return {}
	var basis := player.movement_camera.global_basis if player.movement_camera else Basis.IDENTITY
	var right := basis.x
	var back := basis.z
	right.y = 0.0
	back.y = 0.0
	var x := heading.dot(right.normalized())
	var z := heading.dot(back.normalized())
	var name: StringName = &"side" if absf(x) >= absf(z) else (&"back" if z < 0.0 else &"front")
	var flip := name == &"side" and x < 0.0
	if not frames.has_animation(name):
		# 弹墙各方向共用侧向动作，镜像只取镜头下的水平分量。
		if action == &"bounce" and frames.has_animation(&"side"):
			name = &"side"
			flip = x < -0.0001
		elif frames.has_animation(action): name = action
		elif frames.has_animation(&"default"): name = &"default"
		else: return {}
	if frames.get_frame_count(name) <= 0 or frames.get_animation_speed(name) <= 0.0: return {}
	return {"frames": frames, "name": name, "flip": flip}
