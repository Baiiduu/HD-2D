class_name PlayerActionAnimator
extends RefCounted

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

func render(delta: float) -> bool:
	_context_age += delta
	if not _attack.is_empty():
		_attack_age += delta
		if _attack_age >= _attack_duration: cancel_attack()
	var attack_active := not _attack.is_empty() and _context != &"charge"
	var action: StringName = _attack if attack_active else _context
	var heading := _attack_heading if attack_active else _heading
	var clip := _resolve(action, heading)
	if clip.is_empty(): return false
	var frames: SpriteFrames = clip.frames
	var name: StringName = clip.name
	var count := frames.get_frame_count(name)
	var frame := 0
	if not attack_active and _progress >= 0.0:
		frame = clampi(roundi(clampf(_progress, 0.0, 1.0) * (count - 1)), 0, count - 1)
	else:
		var elapsed := (_attack_age if attack_active else _context_age) * frames.get_animation_speed(name)
		var total := 0.0
		for index in count: total += frames.get_frame_duration(name, index)
		if not attack_active and frames.get_animation_loop_mode(name) != SpriteFrames.LOOP_NONE: elapsed = fmod(elapsed, total)
		while frame < count - 1 and elapsed >= frames.get_frame_duration(name, frame):
			elapsed -= frames.get_frame_duration(name, frame)
			frame += 1
	player.sprite.flip_h = clip.flip
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
		if frames.has_animation(action): name = action
		elif frames.has_animation(&"default"): name = &"default"
		else: return {}
	if frames.get_frame_count(name) <= 0 or frames.get_animation_speed(name) <= 0.0: return {}
	return {"frames": frames, "name": name, "flip": flip}
