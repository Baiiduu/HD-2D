class_name MirrorMarkEffect
extends Node3D

const EFFECT_LAYER := preload("res://scripts/rendering/combat_effect_layer.gd")
const MIRROR_SURFACE := preload("res://scripts/combat/mirror_reflection_surface.gd")

signal finished

const PIXEL_SHADER := preload("res://shaders/combat/mirror_pixels.gdshader")
@export var mirror_texture: Texture2D
## 正式人物 pixel_size 0.02 × Sprite 缩放 0.8；动画不缩放像素。
@export var pixel_size := 0.016
@export var attachment_height := 0.72
@export var reveal_time := 0.12
@export var glint_time := 0.18
@export var break_time := 0.28

var enemy: WaveEnemy
var normal := Vector3.LEFT
var _sprite: MeshInstance3D
var _material: ShaderMaterial
var _pieces: Array[MeshInstance3D] = []
var _piece_materials: Array[ShaderMaterial] = []
var _age := 0.0
var _glint_age := 1.0
var _breaking := false
var _break_position := Vector3.ZERO
var _break_basis := Basis.IDENTITY
var _break_opacity := 1.0
var _surface: MIRROR_SURFACE

func _ready() -> void:
	_material = _new_material(Rect2(0, 0, 1, 1))
	_sprite = _new_quad(_material)
	for index in 4:
		var material := _new_material(Rect2((index % 2) * 0.5, (index / 2) * 0.5, 0.5, 0.5))
		_piece_materials.append(material)
		_pieces.append(_new_quad(material))
	stop()

func prepare_feedback() -> void:
	if _surface: return
	_surface = MIRROR_SURFACE.new()
	add_child(_surface)
	_surface.reflected.connect(glint)
	_surface.stop()

func attach(target: WaveEnemy, surface_normal: Vector3) -> void:
	stop()
	enemy = target
	normal = surface_normal
	if not _surface:
		_surface = MIRROR_SURFACE.new()
		add_child(_surface)
		_surface.reflected.connect(glint)
	_surface.attach(target, normal, mirror_texture.get_size() * pixel_size, attachment_height)
	_age = 0.0
	_glint_age = 0.0
	var camera := get_viewport().get_camera_3d()
	_update_pose(target.global_position + Vector3.UP * attachment_height, camera.global_basis if camera else Basis.IDENTITY)
	EFFECT_LAYER.set_parameter(_material, "opacity", 1.0)
	EFFECT_LAYER.set_parameter(_material, "reveal", 1.0 if target.dead else 0.0)
	EFFECT_LAYER.set_parameter(_material, "glint", -1.0)
	_sprite.show()
	set_process(true)
	_process(0.0)

func glint() -> void:
	_glint_age = 0.0

func shatter(point: Vector3) -> void:
	if _breaking: return
	if _surface: _surface.stop()
	var camera := get_viewport().get_camera_3d()
	var facing := camera.global_basis if camera else Basis.IDENTITY
	var reveal := 1.0
	var glint := -1.0
	_break_opacity = 1.0
	if _sprite.visible:
		# 从上一帧真正显示的镜片拆开，保留尺寸、倾斜、显现和闪光。
		_break_position = _sprite.global_position
		_break_basis = facing.inverse() * _sprite.global_basis
		reveal = _material.get_shader_parameter("reveal")
		glint = _material.get_shader_parameter("glint")
		var opacity: Variant = _material.get_shader_parameter("opacity")
		if opacity != null: _break_opacity = opacity
	else:
		# 独立接触火花没有原镜片，不继承池中上次使用的姿态。
		_break_position = point
		var size := mirror_texture.get_size() * pixel_size
		_break_basis = Basis.IDENTITY.scaled(Vector3(size.x, size.y, 1))
	for material in _piece_materials:
		EFFECT_LAYER.set_parameter(material, "reveal", reveal)
		EFFECT_LAYER.set_parameter(material, "glint", glint)
	enemy = null
	_breaking = true
	_age = 0.0
	_sprite.hide()
	for piece in _pieces: piece.show()
	set_process(true)
	_process(0.0)

func stop() -> void:
	if _surface: _surface.stop()
	enemy = null
	_breaking = false
	if _sprite: _sprite.hide()
	for piece in _pieces: piece.hide()
	set_process(false)

func _process(delta: float) -> void:
	_age += delta
	_glint_age += delta
	var camera := get_viewport().get_camera_3d()
	var facing := camera.global_basis if camera else Basis.IDENTITY
	if _breaking:
		if _age >= break_time:
			stop()
			finished.emit()
			return
		var oriented := facing * _break_basis
		var travel := Vector2.ONE * floorf((_age / break_time) * 4.0) / mirror_texture.get_size()
		for index in 4:
			var side := Vector2(-1 if index % 2 == 0 else 1, 1 if index < 2 else -1)
			var offset := side * (Vector2.ONE * 0.25 + travel)
			_pieces[index].global_position = _break_position + oriented * Vector3(offset.x, offset.y, 0)
			_pieces[index].global_basis = oriented.scaled_local(Vector3(0.5, 0.5, 1))
			EFFECT_LAYER.set_parameter(_piece_materials[index], "opacity", _break_opacity * (1.0 - _age / break_time))
		return
	if not is_instance_valid(enemy) or enemy.dead:
		shatter(_sprite.global_position)
		return
	_update_pose(enemy.global_position + Vector3.UP * attachment_height, facing)
	EFFECT_LAYER.set_parameter(_material, "reveal", minf(1.0, _age / maxf(reveal_time, 0.001)))
	EFFECT_LAYER.set_parameter(_material, "glint", (_glint_age / glint_time) * 48.0 if _glint_age < glint_time else -1.0)

func _update_pose(point: Vector3, facing: Basis) -> void:
	_sprite.global_position = point
	var size := mirror_texture.get_size() * pixel_size
	# 镜面法线固定在世界中；Q/E 只改变投影，不改变实际反射方向。
	var tangent := Vector3.UP.cross(normal)
	var angle := atan2(tangent.dot(facing.y), tangent.dot(facing.x))
	_sprite.global_basis = facing * Basis(Vector3.BACK, angle) * Basis.from_scale(Vector3(size.x, size.y, 1))

func _new_material(rect: Rect2) -> ShaderMaterial:
	var material := EFFECT_LAYER.material(PIXEL_SHADER)
	EFFECT_LAYER.set_parameter(material, "effect_texture", mirror_texture)
	EFFECT_LAYER.set_parameter(material, "frame_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	return material

func _new_quad(material: ShaderMaterial) -> MeshInstance3D:
	if not PrismRicochetEffect._head_mesh: PrismRicochetEffect._head_mesh = QuadMesh.new()
	var instance := MeshInstance3D.new()
	instance.mesh = PrismRicochetEffect._head_mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance
