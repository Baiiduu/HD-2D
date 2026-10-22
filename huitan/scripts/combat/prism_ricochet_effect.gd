class_name PrismRicochetEffect
extends Node3D

const EFFECT_LAYER := preload("res://scripts/rendering/combat_effect_layer.gd")

signal finished

const CRYSTAL_SHADER := preload("res://shaders/combat/prism_crystal.gdshader")

@export var head_texture: Texture2D
@export var trail_texture: Texture2D
@export var feedback_scene: PackedScene
@export var head_width := 0.9
@export var trail_width := 0.7
@export var trail_length := 3.2
@export var fade_time := 0.25

static var _head_mesh: QuadMesh
var _head: MeshInstance3D
var _head_material: ShaderMaterial
var _feedback: LightPierceEffect
var _light: OmniLight3D
var _legs: Array[Dictionary] = []
var _pool: Array[Dictionary] = []
var _position := Vector3.ZERO
var _direction := Vector3.RIGHT
var _flying := false
var _strength := 1.0
var _new_leg := true

func _ready() -> void:
	if not _head_mesh: _head_mesh = QuadMesh.new()
	_head_material = EFFECT_LAYER.material(CRYSTAL_SHADER)
	EFFECT_LAYER.set_parameter(_head_material, "effect_texture", head_texture)
	_head = _mesh(_head_mesh, _head_material)
	_feedback = feedback_scene.instantiate() as LightPierceEffect
	_feedback.head_texture = null
	_feedback.trail_texture = null
	_feedback.ground_light_enabled = false
	_feedback.impact_width = 1.5
	_feedback.impact_duration = 0.32
	add_child(_feedback)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.45, 0.85, 1.0)
	_light.omni_range = 1.8
	_light.light_energy = 0.18
	_light.shadow_enabled = false
	add_child(_light)
	stop()

func prepare_feedback() -> void:
	if _feedback: _feedback.prepare_feedback()
	if _pool.is_empty():
		launch(Vector3.ZERO, Vector3.RIGHT, 1.0)
		move_to(Vector3.RIGHT, Vector3.RIGHT)
		stop()

func launch(position_on_path: Vector3, direction: Vector3, strength: float) -> void:
	stop()
	_position = position_on_path
	_direction = direction
	_strength = strength
	_flying = true
	_new_leg = true
	_feedback.impact_width = 1.5 * strength
	set_process(true)
	_update_head(get_viewport().get_camera_3d())

func move_to(point: Vector3, direction: Vector3) -> void:
	if point.distance_squared_to(_position) > 0.000001:
		if _new_leg or _legs.is_empty():
			var leg: Dictionary
			if _pool.is_empty():
				var material := _material(trail_texture)
				leg = {"mesh": _mesh(LightPierceEffect._shared_ribbon_mesh(), material), "material": material}
			else: leg = _pool.pop_back()
			leg.from = _position
			leg.to = point
			leg.age = 0.0
			_legs.append(leg)
			_new_leg = false
		else:
			_legs[-1].to = point
			_legs[-1].age = 0.0
	_position = point
	_direction = direction
	_trim_tail()
	_update_head(get_viewport().get_camera_3d())

func show_contact(point: Vector3, bounced := false) -> void:
	_feedback.show_hit(point - Vector3.UP * _feedback.impact_height)
	if bounced: _new_leg = true

func end_flight() -> void:
	_flying = false
	_head.hide()
	_light.hide()

func stop() -> void:
	_flying = false
	for leg in _legs: _recycle(leg)
	_legs.clear()
	if _head: _head.hide()
	if _light: _light.hide()
	if _feedback: _feedback.stop()
	set_process(false)

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	_update_head(camera)
	for index in range(_legs.size() - 1, -1, -1):
		var leg: Dictionary = _legs[index]
		leg.age += delta
		if leg.age >= fade_time:
			_recycle(leg)
			_legs.remove_at(index)
			continue
		var offset: Vector3 = leg.to - leg.from
		var forward := offset.normalized()
		var side := camera.global_basis.z.cross(forward).normalized() if camera else Vector3.UP
		leg.mesh.global_position = leg.from
		leg.mesh.global_basis = Basis(offset, side * trail_width * _strength, forward.cross(side))
		leg.mesh.visible = true
		EFFECT_LAYER.set_parameter(leg.material, "opacity", 0.85 * (1.0 - leg.age / fade_time))
	if not _flying and _legs.is_empty() and not _feedback.is_processing():
		set_process(false)
		finished.emit()

func _update_head(camera: Camera3D) -> void:
	_head.visible = _flying
	_light.visible = _flying
	if not _flying: return
	_head.global_position = _position
	_light.global_position = _position
	var size := head_texture.get_size()
	var scale := Vector3(head_width * _strength, head_width * _strength * size.y / size.x, 1)
	if camera:
		var angle := atan2(_direction.dot(camera.global_basis.y), _direction.dot(camera.global_basis.x))
		_head.global_basis = camera.global_basis * Basis(Vector3.BACK, angle) * Basis.from_scale(scale)
	else: _head.scale = scale

func _trim_tail() -> void:
	var length := 0.0
	for leg in _legs: length += leg.from.distance_to(leg.to)
	var excess := length - trail_length
	while excess > 0.00001 and not _legs.is_empty():
		var leg: Dictionary = _legs[0]
		var distance: float = leg.from.distance_to(leg.to)
		if distance <= excess:
			excess -= distance
			_recycle(leg)
			_legs.remove_at(0)
		else:
			leg.from = leg.from.move_toward(leg.to, excess)
			break

func _recycle(leg: Dictionary) -> void:
	leg.mesh.hide()
	_pool.append(leg)

func _material(texture: Texture2D) -> ShaderMaterial:
	var material := EFFECT_LAYER.material(LightPierceEffect.EFFECT_SHADER)
	EFFECT_LAYER.set_parameter(material, "effect_texture", texture)
	EFFECT_LAYER.set_parameter(material, "energy", 1.15)
	EFFECT_LAYER.set_parameter(material, "opacity", 0.9)
	EFFECT_LAYER.set_parameter(material, "edge_fade", 0.0)
	return material

func _mesh(mesh: Mesh, material: ShaderMaterial) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance
