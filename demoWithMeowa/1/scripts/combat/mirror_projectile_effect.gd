class_name MirrorProjectileEffect
extends PrismRicochetEffect

## 复用弹丸节点池与共享四边形；残影也是原生像素图，不拉成长光带。
@export var pixel_size := 0.016
@export var mark_scene: PackedScene
@export_range(0.02, 0.3, 0.01) var ghost_spacing := 0.12
var motion_speed := 10.0
var _ghosts: Array[Dictionary] = []
var _idle_ghosts: Array[Dictionary] = []
var _sparks: Array[MirrorMarkEffect] = []
var _idle_sparks: Array[MirrorMarkEffect] = []
var _spacing_left := 0.0

func _ready() -> void:
	if not _head_mesh: _head_mesh = QuadMesh.new()
	_head_material = _material(head_texture)
	_head = _mesh(_head_mesh, _head_material)
	stop()

func launch(point: Vector3, direction: Vector3, _strength_value: float) -> void:
	stop()
	_position = point
	_direction = direction
	_spacing_left = ghost_spacing
	_flying = true
	set_process(true)
	_update_head(get_viewport().get_camera_3d())

func move_to(point: Vector3, direction: Vector3) -> void:
	var length := point.distance_to(_position)
	var offset := point - _position
	var travelled := _spacing_left
	while travelled <= length and length > 0.00001:
		# 同一帧扫掠多个反射点时，已超出尾迹寿命的采样无需创建节点。
		var age := (length - travelled) / maxf(motion_speed, 0.001)
		if age >= fade_time:
			travelled += ghost_spacing
			continue
		var ghost: Dictionary
		if _idle_ghosts.is_empty():
			var material := _material(head_texture)
			ghost = {"mesh": _mesh(_head_mesh, material), "material": material}
		else: ghost = _idle_ghosts.pop_back()
		ghost.position = _position + offset * (travelled / length)
		ghost.direction = _direction
		ghost.age = age
		_ghosts.append(ghost)
		travelled += ghost_spacing
	_spacing_left = travelled - length
	_position = point
	_direction = direction
	_update_head(get_viewport().get_camera_3d())

func show_contact(point: Vector3, _bounced := false) -> void:
	var spark: MirrorMarkEffect
	if _idle_sparks.is_empty():
		spark = mark_scene.instantiate()
		add_child(spark)
		_sparks.append(spark)
		spark.finished.connect(func():
			if spark not in _idle_sparks: _idle_sparks.append(spark))
	else: spark = _idle_sparks.pop_back()
	spark.pixel_size = pixel_size
	spark.shatter(point)

func end_flight() -> void:
	_flying = false
	_head.hide()

func stop() -> void:
	_flying = false
	if _head: _head.hide()
	for ghost in _ghosts:
		ghost.mesh.hide()
		_idle_ghosts.append(ghost)
	_ghosts.clear()
	for spark in _sparks:
		spark.stop()
		if spark not in _idle_sparks: _idle_sparks.append(spark)
	set_process(false)

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	_update_head(camera)
	for index in range(_ghosts.size() - 1, -1, -1):
		var ghost: Dictionary = _ghosts[index]
		ghost.age += delta
		if ghost.age >= fade_time:
			ghost.mesh.hide()
			_idle_ghosts.append(ghost)
			_ghosts.remove_at(index)
			continue
		_orient(ghost.mesh, ghost.position, ghost.direction, camera)
		ghost.mesh.show()
		ghost.material.set_shader_parameter("opacity", 0.22 * (1.0 - ghost.age / fade_time))
	if not _flying and _ghosts.is_empty() and _sparks.size() == _idle_sparks.size():
		set_process(false)
		finished.emit()

func _update_head(camera: Camera3D) -> void:
	_head.visible = _flying
	if _flying: _orient(_head, _position, _direction, camera)

func _orient(mesh: MeshInstance3D, point: Vector3, direction: Vector3, camera: Camera3D) -> void:
	mesh.global_position = point
	var facing := camera.global_basis if camera else Basis.IDENTITY
	var angle := atan2(direction.dot(facing.y), direction.dot(facing.x))
	var size := head_texture.get_size() * pixel_size
	mesh.global_basis = facing * Basis(Vector3.BACK, angle).scaled(Vector3(size.x, size.y, 1))

func _material(texture: Texture2D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = MirrorMarkEffect.PIXEL_SHADER
	material.set_shader_parameter("effect_texture", texture)
	return material
