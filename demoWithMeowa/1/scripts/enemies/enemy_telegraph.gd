class_name EnemyTelegraph
extends MeshInstance3D

static var _quad: QuadMesh
static var _users := 0
var _material: ShaderMaterial

func _ready() -> void:
	_users += 1
	if not _quad: _quad = QuadMesh.new()
	mesh = _quad
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/combat/enemy_telegraph.gdshader")
	material_override = _material
	hide()

func _exit_tree() -> void:
	_users -= 1
	if _users == 0: _quad = null

func line(point: Vector3, direction: Vector3, length: float, width: float) -> void:
	global_position = point + direction * length * 0.5 + Vector3.UP * 0.025
	global_basis = Basis(direction * length, Vector3.UP.cross(direction) * width, Vector3.UP)
	_material.set_shader_parameter("display_size", Vector2(length, width))
	_material.set_shader_parameter("circle", false)
	_material.set_shader_parameter("tint", Color(1.0, 0.29, 0.08, 1.0))
	show()

func ring(point: Vector3, radius: float) -> void:
	global_position = point + Vector3.UP * 0.03
	global_basis = Basis(Vector3.RIGHT * radius * 2.0, Vector3.BACK * radius * 2.0, Vector3.UP)
	_material.set_shader_parameter("display_size", Vector2.ONE * radius * 2.0)
	_material.set_shader_parameter("circle", true)
	_material.set_shader_parameter("tint", Color(0.61, 0.9, 0.32, 1.0))
	show()

func set_opacity(value: float) -> void:
	_material.set_shader_parameter("opacity", value)

func set_tint(value: Color) -> void:
	_material.set_shader_parameter("tint", value)
