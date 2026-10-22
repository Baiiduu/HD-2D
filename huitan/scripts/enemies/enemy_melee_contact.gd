extends MeshInstance3D

signal finished
const MATERIALS := preload("res://scripts/enemies/enemy_remains_materials.gd")
static var _quad: QuadMesh
static var _users := 0
var _frames: SpriteFrames
var _point := Vector3.ZERO
var _pixel := 0.016
var _heading := Vector3.RIGHT
var _age := 0.0
var _duration := 0.12
var _frame := -1
var _camera: Camera3D

func _ready() -> void:
	MATERIALS.retain()
	_users += 1
	if not _quad:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	mesh = _quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	hide()
	set_process(false)

func _exit_tree() -> void:
	MATERIALS.release()
	_users -= 1
	if _users == 0: _quad = null

func prepare(visuals: PlayerActionVisuals) -> void:
	MATERIALS.prepare_frames(visuals.combat_contact_frames)

func begin(point: Vector3, pixel: float, heading: Vector3, visuals: PlayerActionVisuals, camera: Camera3D) -> void:
	_frames = visuals.combat_contact_frames
	_point = point
	_pixel = pixel
	_heading = heading
	_camera = camera
	_age = 0.0
	_duration = maxf(0.06, visuals.combat_contact_seconds)
	_frame = -1
	set_instance_shader_parameter(&"tint", Color.WHITE)
	set_instance_shader_parameter(&"opacity", 0.85)
	set_instance_shader_parameter(&"death_energy", 0.75)
	show()
	set_process(true)
	_process(0.0)

func _process(delta: float) -> void:
	_age += delta
	if _age >= _duration:
		hide()
		set_process(false)
		finished.emit()
		return
	var count := _frames.get_frame_count(&"bounce")
	var frame := mini(count - 1, int(_age / _duration * count))
	var image := _frames.get_frame_texture(&"bounce", frame)
	if frame != _frame:
		var texture: Texture2D = image.atlas if image is AtlasTexture else image
		var rect: Rect2 = image.region if image is AtlasTexture else Rect2(Vector2.ZERO, image.get_size())
		var uv := Vector4(rect.position.x / texture.get_width(), rect.position.y / texture.get_height(), rect.size.x / texture.get_width(), rect.size.y / texture.get_height())
		material_override = MATERIALS.material(texture)
		set_instance_shader_parameter(&"frame_rect", uv)
		_frame = frame
	var facing := _camera.global_basis.orthonormalized() if is_instance_valid(_camera) else Basis.IDENTITY
	var angle := atan2(_heading.dot(facing.y), _heading.dot(facing.x))
	var basis := facing * Basis(Vector3.BACK, angle)
	var anchor := (image.get_size() * 0.5 - Vector2(19, 24)) * _pixel
	global_position = _point + basis * Vector3(anchor.x, -anchor.y, 0)
	global_basis = basis.scaled_local(Vector3(image.get_width() * _pixel, image.get_height() * _pixel, 1))
