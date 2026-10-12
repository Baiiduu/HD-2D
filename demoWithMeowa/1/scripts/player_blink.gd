class_name PlayerBlink
extends Node

const POSES := preload("res://assets/meowa/player/dodge/dodge.tres")
const ECHO_SHADER := preload("res://shaders/player_echo.gdshader")

var active := false
var _player: Player
var _elapsed := 0.0
var _cooldown := 0.0
var _duration := 0.24
var _anticipation := 0.04
var _hold := 0.07
var _direction := Vector3.ZERO
var _moved := false
var _facing: StringName
var _flip := false
var _echoes: Array[Dictionary] = []
var _buffer_remaining := 0.0
var _buffer_direction := Vector3.ZERO
var movement_locked: bool:
	get: return active and _elapsed < _anticipation + _hold

func _ready() -> void:
	_player = get_parent() as Player

func request(movement: Vector3) -> void:
	if not _player.blink_enabled or not _player.is_on_floor():
		return
	if not try_start(movement):
		# 只缓存短时间内的新按键，避免收尾/冷却边界吞掉输入。
		_buffer_remaining = _player.blink_input_buffer
		_buffer_direction = movement

func try_start(movement: Vector3) -> bool:
	if active or _cooldown > 0.0 or not _player.blink_enabled or not _player.is_on_floor():
		return false
	if get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null:
		return false
	_facing = _player._facing
	_flip = _player.sprite.flip_h
	_direction = movement
	if _direction.is_zero_approx():
		var camera := _player.movement_camera
		if _facing == &"back":
			_direction = -camera.global_basis.z if camera else Vector3.FORWARD
		else:
			_direction = camera.global_basis.x if camera else Vector3.RIGHT
			if _flip:
				_direction = -_direction
	_direction.y = 0.0
	_direction = _direction.normalized()
	_elapsed = 0.0
	_moved = false
	_duration = maxf(_player.blink_duration, 0.15)
	_anticipation = clampf(_player.blink_anticipation, 0.02, _duration * 0.4)
	_hold = clampf(_player.blink_pose_hold, 0.02, _duration - _anticipation - 0.04)
	_cooldown = maxf(_player.blink_cooldown, _duration)
	_buffer_remaining = 0.0
	active = true
	apply_pose()
	return true

func advance(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)
	_buffer_remaining = maxf(0.0, _buffer_remaining - delta)
	if get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null:
		_buffer_remaining = 0.0
		if active:
			_finish()
		return
	if not active:
		if _buffer_remaining > 0.0:
			try_start(_buffer_direction)
		return
	_elapsed += delta
	if not _moved and _elapsed >= _anticipation:
		apply_pose()
		_teleport()
		_moved = true
	if _elapsed >= _duration:
		_finish()

func apply_pose() -> void:
	_player.sprite.flip_h = _flip
	if _facing == &"side":
		var frame: int
		if _elapsed < _anticipation:
			frame = 0
		elif _elapsed < _anticipation + _hold:
			frame = 3
		else:
			frame = 7
		_player.sprite.texture = POSES.get_frame_texture(&"dodge", frame)
	else:
		# 当前只有侧面闪避美术；背向保留背向贴图，避免突然转身。
		var name := StringName("idle_" + str(_facing))
		if _player.animations and _player.animations.has_animation(name):
			_player.sprite.texture = _player.animations.get_frame_texture(name, 0)

func _teleport() -> void:
	var start := _player.global_position
	var destination := start + _direction * _player.blink_distance
	destination.x = clampf(destination.x, _player.bounds.position.x, _player.bounds.end.x)
	destination.z = clampf(destination.z, _player.bounds.position.y, _player.bounds.end.y)
	var motion := destination - start
	var collision := KinematicCollision3D.new()
	# 胶囊沿整段路径扫掠，不能只检查终点而穿过薄墙。
	if _player.test_move(_player.global_transform, motion, collision, _player.safe_margin):
		motion = collision.get_travel()
		motion -= _direction * minf(0.015, motion.length())
	if motion.length() < 0.025:
		return
	for index in _player.blink_echo_count:
		_spawn_echo(start + motion * float(index) / float(_player.blink_echo_count), index)
	_player.global_position = start + motion
	_player.reset_physics_interpolation()
	_player.blink_travelled.emit(start, _player.global_position)

func _spawn_echo(point: Vector3, index: int) -> void:
	var source := _player.sprite
	var echo := Sprite3D.new()
	echo.name = "BlinkEcho"
	echo.texture = source.texture
	echo.pixel_size = source.pixel_size
	echo.offset = source.offset
	echo.centered = source.centered
	echo.billboard = source.billboard
	echo.flip_h = source.flip_h
	echo.flip_v = source.flip_v
	echo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	echo.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	echo.add_to_group(&"blink_echoes")
	var material := ShaderMaterial.new()
	material.shader = ECHO_SHADER
	material.set_shader_parameter("sprite_texture", source.texture)
	material.set_shader_parameter("echo_color", _player.blink_echo_color)
	material.set_shader_parameter("energy", _player.blink_echo_energy)
	material.set_shader_parameter("fixed_y", source.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y)
	var opacity := _player.blink_echo_opacity * (1.0 - float(index) / maxf(1.0, _player.blink_echo_count) * 0.45)
	material.set_shader_parameter("opacity", opacity)
	echo.material_override = material
	_player.get_parent().add_child(echo)
	echo.global_transform = source.global_transform
	echo.global_position += point - _player.global_position
	echo.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_echoes.append({"sprite": echo, "material": material, "elapsed": 0.0,
		"lifetime": maxf(_player.blink_echo_lifetime, 0.05), "opacity": opacity})

func _process(delta: float) -> void:
	for index in range(_echoes.size() - 1, -1, -1):
		var echo := _echoes[index]
		echo.elapsed += delta
		if echo.elapsed >= echo.lifetime:
			echo.sprite.queue_free()
			_echoes.remove_at(index)
		else:
			echo.material.set_shader_parameter("opacity", echo.opacity * pow(1.0 - echo.elapsed / echo.lifetime, 1.25))

func _finish() -> void:
	active = false
	_player._facing = _facing
	_player._animation_frame = 0
	_player._animation_elapsed = 0.0
	if _player.animations and _player.animations.has_animation(_player._animation):
		_player.sprite.texture = _player.animations.get_frame_texture(_player._animation, 0)

func _exit_tree() -> void:
	for echo in _echoes:
		if is_instance_valid(echo.sprite):
			echo.sprite.queue_free()
