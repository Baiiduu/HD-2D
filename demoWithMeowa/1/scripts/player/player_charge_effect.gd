class_name PlayerChargeEffect
extends Node3D

## 蓄力专用地面提示，不驱动人物动作或运动；首次蓄力创建，之后复用。
const MOTE_COUNT := 10
static var _quad: QuadMesh
static var _mote_material: ShaderMaterial
static var _users := 0
var _player: Player
var _body: PlayerRicochet
var _visuals: PlayerActionVisuals
var _ring: MeshInstance3D
var _aim: AimPathPreview
var _motes: MultiMeshInstance3D
var _light: OmniLight3D
var _ring_material: ShaderMaterial
var _prediction := BodyPathPrediction.new()
var _route := AimPathData.new()
var _target_enemy: WaveEnemy
var _pixel := 0.016
var _radius := 0.672
var _age := 0.0
var _full_at := -1.0
var _foot_texture: Texture2D
var _foot_pixel := 0.0
var _foot_height := 0.015

func _ready() -> void:
	_users += 1
	if not _quad:
		_quad = QuadMesh.new()
		_mote_material = ShaderMaterial.new()
		_mote_material.shader = preload("res://shaders/combat/charge_mote.gdshader")
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# 跟随镜头更新后再对齐地面圆弧和光点，位置与人物渲染插值一致。
	process_priority = 2
	_ring = _make_plane()
	_aim = AimPathPreview.new()
	_aim.name = "CollisionPath"
	add_child(_aim)
	_ring_material = _ring.material_override
	_motes = MultiMeshInstance3D.new()
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motes.multimesh = MultiMesh.new()
	_motes.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_motes.multimesh.use_colors = true
	_motes.multimesh.mesh = _quad
	_motes.multimesh.instance_count = MOTE_COUNT
	_motes.material_override = _mote_material
	add_child(_motes)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.position.y = 0.22
	_light.omni_range = 1.45
	_light.omni_attenuation = 1.8
	_light.light_specular = 0.35
	_light.shadow_enabled = false
	add_child(_light)
	stop()

func _exit_tree() -> void:
	_users -= 1
	if _users == 0:
		_quad = null
		_mote_material = null

func _make_plane() -> MeshInstance3D:
	var plane := MeshInstance3D.new()
	plane.mesh = _quad
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/combat/player_charge.gdshader")
	plane.material_override = material
	add_child(plane)
	return plane

func display(player: Player, body: PlayerRicochet, visuals: PlayerActionVisuals) -> void:
	_player = player
	_body = body
	_visuals = visuals
	_pixel = player.sprite.pixel_size * player.sprite.global_basis.x.length()
	_radius = visuals.charge_radius_pixels * _pixel
	# 待机母帧的透明脚边只在素材更换时读取，避免把留白当脚底或逐帧抖动。
	var reference := player.animations.get_frame_texture(&"idle", 0) if player.animations and player.animations.has_animation(&"idle") else player.sprite.texture
	if reference != _foot_texture:
		_foot_texture = reference
		var image := reference.get_image() if reference else null
		_foot_pixel = reference.get_height() * 0.5 - image.get_used_rect().end.y if image and not image.is_empty() else 0.0
	_foot_height = maxf(0.015, player.sprite.position.y + (_foot_pixel + player.sprite.offset.y) * player.sprite.pixel_size * player.sprite.global_basis.y.length())
	if not visible:
		_age = 0.0
		_full_at = -1.0
		show()
		set_process(true)
	_update_aim()
	_process(0.0)

func stop() -> void:
	hide()
	set_process(false)
	if is_instance_valid(_aim): _aim.stop()
	_target_enemy = null
	_route.clear()

func _process(delta: float) -> void:
	if not is_instance_valid(_body) or not _body.charging or not _visuals.show_charge_effect:
		stop()
		return
	var frozen := _body.is_frozen()
	if not frozen: _age += delta
	var fraction := _body.charge_fraction
	if fraction >= 1.0 and _full_at < 0.0: _full_at = _age
	var flash := maxf(0.0, 1.0 - (_age - _full_at) / 0.18) if _full_at >= 0.0 else 0.0
	global_position = _player.get_global_transform_interpolated().origin + Vector3.UP * _foot_height
	global_basis = Basis.IDENTITY
	var camera := _player.movement_camera
	var camera_basis := camera.global_basis.orthonormalized() if is_instance_valid(camera) else Basis.IDENTITY
	var right := camera_basis.x
	right.y = 0.0
	right = right.normalized()
	var toward := right.cross(Vector3.UP)
	var diameter := (_visuals.charge_radius_pixels + 3.0) * 2.0 * _pixel
	_ring.basis = Basis(right * diameter, toward * diameter, Vector3.UP)
	_ring_material.set_shader_parameter("size_pixels", Vector2.ONE * diameter / _pixel)
	_ring_material.set_shader_parameter("radius_pixels", _visuals.charge_radius_pixels)
	_ring_material.set_shader_parameter("charge", fraction)
	_ring_material.set_shader_parameter("full_flash", flash)
	_ring_material.set_shader_parameter("opacity", _visuals.charge_effect_opacity)
	_ring_material.set_shader_parameter("energy", _visuals.charge_effect_energy)
	_update_motes(camera_basis, fraction)
	_light.light_energy = (0.06 + fraction * 0.12 + flash * 0.12) * _visuals.charge_effect_opacity
	_light.omni_range = _radius * 2.1
	if not is_instance_valid(_target_enemy) or _target_enemy.dead or _target_enemy.spawn_delay > 0.0:
		_aim.mark_target(null)

## 每物理帧重新读取动态世界；渲染只消费路线，镜头旋转不重做碰撞查询。
func _update_aim() -> void:
	if not _visuals.show_aim_guide:
		_aim.stop()
		_target_enemy = null
		return
	_body.predict_path(_prediction, _route, _visuals.preview_distance, _visuals.preview_bounces)
	_target_enemy = _player.sword.preview_target(_route) if _visuals.preview_show_target and is_instance_valid(_player.sword) else null
	_aim.display(_route, _player.movement_camera, _pixel, _foot_height, _radius + _pixel * 5.0,
		_visuals.preview_line_width_pixels, _visuals.preview_color, _visuals.preview_opacity)
	_aim.mark_target(_target_enemy.get_node_or_null("Sprite") as Sprite3D if is_instance_valid(_target_enemy) else null)

func _update_motes(camera_basis: Basis, fraction: float) -> void:
	for index in MOTE_COUNT:
		var life := fposmod(_age / 0.7 + float(index) / MOTE_COUNT, 1.0)
		var angle := index * 2.39996 + floorf(_age / 0.7 + float(index) / MOTE_COUNT) * 0.7
		var radius := lerpf(_radius * 1.65, _radius * 0.18, life)
		var offset := Vector3(cos(angle) * radius, sin(life * PI) * 0.18, sin(angle) * radius)
		offset = offset.snapped(Vector3.ONE * _pixel)
		var size := _pixel * (2.0 if index % 3 else 3.0)
		var basis := camera_basis.scaled_local(Vector3(size, size, size))
		_motes.multimesh.set_instance_transform(index, Transform3D(basis, offset))
		var color := Color(1.0, 0.78, 0.39) if index % 3 else Color(1.0, 0.93, 0.72)
		color.a = minf(life / 0.12, (1.0 - life) / 0.22) * (0.35 + fraction * 0.6) * _visuals.charge_effect_opacity
		_motes.multimesh.set_instance_color(index, color)
