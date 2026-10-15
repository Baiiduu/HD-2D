class_name EnemyStunEffect
extends MultiMeshInstance3D

## 每只怪物首次受控时创建，后续复用；三颗星共用一张网格和材质。
static var _quad: QuadMesh
static var _material: StandardMaterial3D
static var _users := 0
var _enemy: WaveEnemy
var _camera: Camera3D
var _pixel := 0.016
var _height := 1.0
var _age := 0.0

func _ready() -> void:
	# 星星在渲染帧更新，自行跟随怪物插值位置，避免 MultiMesh 在非物理帧写入插值缓存。
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_users += 1
	if not _quad:
		_quad = QuadMesh.new()
		_material = StandardMaterial3D.new()
		_material.albedo_texture = preload("res://assets/meowa/combat/status/stun_star.png")
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.vertex_color_use_as_albedo = true
		_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _quad
	multimesh.instance_count = 3
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	stop()

func _exit_tree() -> void:
	_users -= 1
	if _users == 0:
		_quad = null
		_material = null

func begin(enemy: WaveEnemy, sprite: Sprite3D, body_height: float) -> void:
	_enemy = enemy
	_camera = get_viewport().get_camera_3d()
	var source := enemy.wave_target.sprite if is_instance_valid(enemy.wave_target) else sprite
	_pixel = source.pixel_size * source.global_basis.x.length()
	_height = maxf(body_height, sprite.position.y + sprite.texture.get_height() * sprite.pixel_size * sprite.scale.y * 0.5) + _pixel * 2.0
	_age = 0.0
	show()
	set_process(true)
	_process(0.0)

func stop() -> void:
	hide()
	set_process(false)

func _process(delta: float) -> void:
	if not is_instance_valid(_enemy) or _enemy.dead or _enemy.stun_remaining <= 0.0:
		stop()
		return
	_age += delta
	global_position = _enemy.get_global_transform_interpolated().origin + Vector3.UP * _height
	global_basis = _camera.global_basis.orthonormalized() if is_instance_valid(_camera) else Basis.IDENTITY
	var size := Vector2(_material.albedo_texture.get_size()) * _pixel
	var opacity := minf(1.0, _enemy.stun_remaining / 0.12)
	for index in 3:
		var angle := _age * TAU / 0.65 + index * TAU / 3.0
		var offset := Vector3(roundf(cos(angle) * 14.0), roundf(sin(angle) * 4.0), 0.0) * _pixel
		multimesh.set_instance_transform(index, Transform3D(Basis.from_scale(Vector3(size.x, size.y, 1.0)), offset))
		multimesh.set_instance_color(index, Color(1, 1, 1, opacity))
