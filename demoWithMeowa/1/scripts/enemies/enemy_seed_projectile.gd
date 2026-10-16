class_name EnemySeedProjectile
extends Node3D

signal finished
const SHADER := preload("res://shaders/combat/mirror_pixels.gdshader")
static var _quad: QuadMesh
static var _texture: Texture2D
var active := false
var direction := Vector3.FORWARD
var travel := 0.0
var _distance := 0.0
var _speed := 0.0
var _radius := 0.0
var _damage := 0.0
var _plane := 0.0
var _damage_player: Callable
var _can_damage: Callable
var _combat_active: Callable
var _player: Player
var _navigation: TerrainPath
var _camera: Camera3D
var _collision := ProjectileCollision.new()
var _visual: MeshInstance3D

func _ready() -> void:
	if not _quad: _quad = QuadMesh.new()
	if not _texture: _texture = load("res://assets/meowa/enemies/lantern_spitter/seed.png")
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("effect_texture", _texture)
	_visual = MeshInstance3D.new()
	_visual.mesh = _quad
	_visual.material_override = material
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_visual)
	stop()

func begin(enemy: WaveEnemy, heading: Vector3, rules: LanternSpitterDefinition) -> void:
	direction = heading.normalized()
	global_position = enemy.global_position + Vector3.UP * 0.45 + direction * (rules.body_radius + 0.12)
	_plane = enemy.navigation.ground_position(enemy.global_position).y
	_navigation = enemy.navigation
	_player = enemy.wave_target
	_camera = get_viewport().get_camera_3d()
	_damage_player = enemy.damage_player
	_can_damage = enemy.can_damage_player
	_combat_active = enemy.combat_active
	_damage = enemy.attack_damage
	_speed = rules.projectile_speed
	_distance = rules.projectile_distance
	_radius = rules.projectile_radius
	travel = 0.0
	active = true
	show()
	set_process(true)
	set_physics_process(true)
	_process(0.0)

func stop() -> void:
	active = false
	_player = null
	_navigation = null
	_damage_player = Callable()
	_can_damage = Callable()
	_combat_active = Callable()
	hide()
	set_process(false)
	set_physics_process(false)

func _finish() -> void:
	stop()
	finished.emit()

func _physics_process(delta: float) -> void:
	if not active: return
	if not is_instance_valid(_player):
		_finish()
		return
	if _combat_active.is_valid() and not _combat_active.call(): return
	var step := minf(_speed * delta, _distance - travel)
	var allowed := _collision.ground_limit(_navigation, global_position, direction, step, _plane, 0.2)
	var hit := _collision.wall_contact(get_world_3d().direct_space_state, global_position, global_position + direction * allowed, _radius, [])
	if not hit.is_empty():
		if hit.get("collider") == _player and _damage_player.is_valid() and (not _can_damage.is_valid() or _can_damage.call(_damage)):
			_damage_player.call(_damage)
		_finish()
		return
	global_position += direction * allowed
	travel += allowed
	if allowed < step or travel >= _distance - 0.001: _finish()

func _process(_delta: float) -> void:
	if not active or not is_instance_valid(_camera): return
	var angle := atan2(direction.dot(_camera.global_basis.y), direction.dot(_camera.global_basis.x))
	var size := _texture.get_size() * 0.016
	_visual.global_basis = _camera.global_basis * Basis(Vector3.BACK, angle) * Basis.from_scale(Vector3(size.x, size.y, 1))
