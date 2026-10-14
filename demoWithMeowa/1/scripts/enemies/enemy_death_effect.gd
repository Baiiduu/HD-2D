class_name EnemyDeathEffect
extends Node3D

signal finished
const SHADER := preload("res://shaders/combat/enemy_remains.gdshader")
static var _quad: QuadMesh
var _pieces: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _position := Vector3.ZERO
var _size := Vector2.ONE
var _pixel := 0.016
var _age := 0.0
var _shards := false
var _camera: Camera3D

func _ready() -> void:
	if not _quad: _quad = QuadMesh.new()
	for index in 4:
		var material := ShaderMaterial.new()
		material.shader = SHADER
		var piece := MeshInstance3D.new()
		piece.mesh = _quad
		piece.material_override = material
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(piece)
		_pieces.append(piece)
		_materials.append(material)
	stop()

func begin(sprite: Sprite3D, shards: bool, camera: Camera3D) -> void:
	stop()
	_camera = camera
	_position = sprite.global_position
	_pixel = sprite.pixel_size * sprite.global_basis.x.length()
	_size = sprite.texture.get_size() * _pixel
	_age = 0.0
	_shards = shards
	var texture := sprite.texture
	var rect := Rect2(Vector2.ZERO, Vector2.ONE)
	if texture is AtlasTexture:
		var atlas := texture as AtlasTexture
		rect = Rect2(atlas.region.position / atlas.atlas.get_size(), atlas.region.size / atlas.atlas.get_size())
		texture = atlas.atlas
	if sprite.flip_h:
		rect.position.x += rect.size.x
		rect.size.x = -rect.size.x
	for index in (4 if shards else 1):
		var part := Rect2(Vector2.ZERO, Vector2.ONE)
		if shards: part = Rect2(Vector2(index % 2, index / 2) * 0.5, Vector2.ONE * 0.5)
		var uv := Rect2(rect.position + part.position * rect.size, part.size * rect.size)
		_materials[index].set_shader_parameter("effect_texture", texture)
		_materials[index].set_shader_parameter("frame_rect", Vector4(uv.position.x, uv.position.y, uv.size.x, uv.size.y))
		_pieces[index].show()
	set_process(true)
	_process(0.0)

func stop() -> void:
	for piece in _pieces: piece.hide()
	set_process(false)

func _process(delta: float) -> void:
	_age += delta
	var duration := 0.3 if _shards else 0.25
	if _age >= duration:
		stop()
		finished.emit()
		return
	var right := _camera.global_basis.x if is_instance_valid(_camera) else Vector3.RIGHT
	right.y = 0.0
	right = right.normalized()
	var facing := Basis(right, Vector3.UP, right.cross(Vector3.UP))
	var progress := _age / duration
	for index in (4 if _shards else 1):
		var side := Vector2(-1 if index % 2 == 0 else 1, 1 if index < 2 else -1)
		var offset := side * (_size * 0.25 + Vector2.ONE * floorf(progress * 4.0) * _pixel) if _shards else Vector2(0, -floorf(progress * 2.0) * _pixel)
		_pieces[index].global_position = _position + facing * Vector3(offset.x, offset.y, 0)
		_pieces[index].global_basis = facing.scaled_local(Vector3(_size.x, _size.y, 1) * Vector3(0.5, 0.5, 1) if _shards else Vector3(_size.x, _size.y, 1))
		_materials[index].set_shader_parameter("opacity", 1.0 - progress)
