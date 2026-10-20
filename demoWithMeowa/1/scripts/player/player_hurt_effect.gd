extends Node3D

## 只消费真实扣血；碎点与画面提示独立开关，不驱动运动、声音或伤害。
const DEBRIS := preload("res://scripts/enemies/hit_debris.gd")
var particles: MultiMeshInstance3D
var _player: Player
var _session: WavePrototype
var _camera: FollowCamera

func _ready() -> void:
	_player = get_parent() as Player
	_session = _player._run_session
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_priority = 3
	_player.damaged.connect(_damaged)
	if is_instance_valid(_session):
		_session.phase_changed.connect(func(_phase): clear())
		_session.run_started.connect(clear)
		_session.run_ended.connect(func(_reason): clear())
	set_process(false)
	if _player.action_visuals.hurt_particles_enabled: prepare_feedback()

func prepare_feedback() -> void:
	if not _player.action_visuals or not _player.action_visuals.hurt_particles_enabled: return
	if is_instance_valid(particles): return
	particles = DEBRIS.new()
	particles.name = "RedPixels"
	particles.set("capacity", 64)
	add_child(particles)
	CombatEffectLayer.set_parameter(particles.material_override, &"hurt_pixels", true)

func _damaged(amount: float) -> void:
	var settings := _player.action_visuals
	if not settings or not is_finite(amount) or amount <= 0.0: return
	if is_instance_valid(_session) and (_session.phase != WavePrototype.Phase.BATTLE or _session.combat_frozen): return
	if settings.hurt_screen_enabled or settings.hurt_camera_enabled:
		var camera := _player.movement_camera as FollowCamera
		if camera != _camera and is_instance_valid(_camera): _camera.clear_hurt_feedback()
		_camera = camera
		if is_instance_valid(_camera) and _camera.target == _player:
			_camera.play_hurt_feedback(settings, _player.body_ricochet.orbiting)
	if not settings.hurt_particles_enabled: return
	var sprite := _player.sprite
	if not sprite or not sprite.texture: return
	var pixel := sprite.pixel_size * sprite.global_basis.x.length()
	if pixel <= 0.0: return
	var camera := get_viewport().get_camera_3d()
	var front := Vector3.BACK
	if camera:
		front = Vector3(camera.global_basis.z.x, 0.0, camera.global_basis.z.z).normalized()
		if front.is_zero_approx(): front = Vector3.BACK
	var right := Vector3.UP.cross(front)
	# 精灵原点已随当前动作锚定身体；向镜头侧留三原生像素，保留真实建筑遮挡。
	var point := sprite.global_position + Vector3.UP * pixel * 2.0 + front * pixel * 3.0
	prepare_feedback()
	particles.hurt_burst(point, right, front, pixel, settings)
	set_process(particles.active)

func _process(delta: float) -> void:
	if not _player.action_visuals or not _player.action_visuals.hurt_particles_enabled:
		clear(false)
		return
	if is_instance_valid(_session) and _session.combat_frozen: return
	particles.advance(maxf(delta, 0.0))
	if not particles.active: clear(false)

func clear(clear_screen := true) -> void:
	if is_instance_valid(particles): particles.clear()
	if clear_screen and is_instance_valid(_camera): _camera.clear_hurt_feedback()
	set_process(false)

func _exit_tree() -> void:
	clear()
