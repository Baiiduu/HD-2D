class_name PlayerSurfaceFeedback
extends Node3D

## 只消费真实飞行与反弹；不查询或修改伤害、镜头、物理和随机流。
const FLOW_SCENE_PATH := "res://scenes/effects/player_speed_flow.tscn"
const AIR_SCENE_PATH := "res://scenes/effects/player_air_envelope.tscn"
const MAX_WAVES := 8
var rim_amount := 0.0
var _clock := 0.0
var _serial := -1
var _player: Player
var _body: PlayerRicochet
var _active: Array[Dictionary] = []
var _pool: Array[Decal] = []
var _flow: GPUParticles3D
var _flow_process: ParticleProcessMaterial
var _flow_material: ShaderMaterial
var _flow_tail := 0.0
var _flow_amount := 0.0
var _flow_texture: Texture2D
var _flow_length := -1.0
var _flow_radius := -1.0
var _flow_points: Image
var _flow_point_texture: ImageTexture
var _air: PlayerAirEnvelope

func _ready() -> void:
	_player = get_parent() as Player
	_body = _player.body_ricochet
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_priority = 3
	_body.launched.connect(_launched)
	_body.impact_recorded.connect(_collided)
	if is_instance_valid(_body._session): _body._session.phase_changed.connect(_phase)
	if _player.action_visuals.speed_flow_enabled:
		if _player.action_visuals.speed_flow_mode == 1: _prepare_air()
		else: _prepare_flow()
	set_process(false)

func _launched(_direction: Vector3, _speed: float, _charge: float) -> void:
	var settings := _player.action_visuals
	if settings and (settings.speed_rim_enabled or settings.speed_flow_enabled): set_process(true)

func _phase(phase: WavePrototype.Phase) -> void:
	if phase != WavePrototype.Phase.BATTLE: clear()

func _collided(impact: RicochetImpact) -> void:
	if impact.serial <= _serial: return
	_serial = impact.serial
	var settings := _player.action_visuals
	if not settings or not settings.surface_wave_enabled or not settings.surface_wave_texture: return
	var strength := impact.strength(settings.motion_reference_speed)
	if strength < 0.025 or impact.normal.is_zero_approx(): return
	if _active.size() >= MAX_WAVES: _recycle(0)
	var decal := _acquire()
	var normal := impact.normal.normalized()
	var tangent := Vector3.UP.cross(normal).normalized()
	if tangent.is_zero_approx(): tangent = Vector3.RIGHT
	var up := normal.cross(tangent).normalized()
	var radius := maxf(0.05, settings.surface_wave_radius) * lerpf(0.65, 1.0, strength)
	# Godot projects decals along local -Y, into the actual contacted surface.
	decal.global_transform = Transform3D(Basis(tangent, normal, -up), impact.point)
	decal.texture_emission = settings.surface_wave_texture
	decal.texture_albedo = settings.surface_wave_texture
	decal.show()
	var item := {"decal": decal, "age": 0.0, "radius": radius,
		"energy": maxf(0.0, settings.surface_wave_energy) * strength,
		"duration": maxf(0.01, settings.surface_wave_seconds)}
	_active.append(item)
	_update_wave(item)
	set_process(true)

func _acquire() -> Decal:
	if not _pool.is_empty(): return _pool.pop_back()
	var decal := Decal.new()
	decal.name = "SurfaceWave"
	decal.albedo_mix = 0.0
	decal.modulate = Color(1.0, 0.78, 0.4)
	decal.normal_fade = 0.7
	decal.upper_fade = 0.01
	decal.lower_fade = 0.01
	add_child(decal)
	return decal

func _update_wave(item: Dictionary) -> void:
	var p := clampf(item.age / item.duration, 0.0, 1.0)
	var expansion := lerpf(0.22, 1.0, 1.0 - pow(1.0 - p, 3.0))
	item.decal.size = Vector3(item.radius * expansion * 2.0, 0.38, item.radius * expansion * 2.0)
	# Emission uses its own energy curve: modulate alpha does not fade emission.
	item.decal.emission_energy = item.energy * (1.0 - smoothstep(0.08, 1.0, p))

func _prepare_flow() -> void:
	if is_instance_valid(_flow): return
	_flow = load(FLOW_SCENE_PATH).instantiate() as GPUParticles3D
	_flow_process = _flow.process_material as ParticleProcessMaterial
	_flow_material = _flow.material_override.duplicate() as ShaderMaterial
	_flow.material_override = _flow_material
	_flow_points = Image.create(2, 1, false, Image.FORMAT_RGBF)
	_flow_point_texture = ImageTexture.create_from_image(_flow_points)
	_flow_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
	_flow_process.emission_point_count = 2
	_flow_process.emission_point_texture = _flow_point_texture
	add_child(_flow)

func _advance_flow(delta: float, settings: PlayerActionVisuals) -> void:
	if settings.speed_flow_mode == 1:
		_advance_air(delta, settings)
		return
	if is_instance_valid(_air): _air.stop()
	var target := 0.0
	if settings.speed_flow_enabled and settings.speed_flow_texture and _body.flying:
		var low := maxf(0.0, settings.speed_rim_min_speed)
		target = smoothstep(low, maxf(low + 0.1, settings.motion_reference_speed), _body.flight_speed)
	_flow_amount = lerpf(_flow_amount, target, 1.0 - exp(-delta / 0.045))
	if target <= 0.0: _flow_amount = 0.0
	if _flow_amount > 0.01:
		_prepare_flow()
		if _flow_texture != settings.speed_flow_texture:
			_flow_texture = settings.speed_flow_texture
			_flow_material.set_shader_parameter(&"airflow_texture", _flow_texture)
		var region := settings.speed_flow_texture_region
		_flow_material.set_shader_parameter(&"brush_region", Vector4(region.position.x, region.position.y, region.size.x, region.size.y))
		if _flow_length != settings.speed_flow_length:
			_flow_length = settings.speed_flow_length
			var card := QuadMesh.new()
			card.size = Vector2(_flow_length * 0.16, _flow_length)
			_flow.draw_pass_1 = card
		_flow.lifetime = maxf(0.01, settings.speed_flow_lifetime)
		if not is_equal_approx(_flow_radius, settings.speed_flow_radius):
			_flow_radius = settings.speed_flow_radius
			_flow_points.set_pixel(0, 0, Color(-_flow_radius, 0.04, 0.0))
			_flow_points.set_pixel(1, 0, Color(_flow_radius, -0.04, 0.0))
			_flow_point_texture.update(_flow_points)
		var heading := _body.direction.normalized()
		var side := Vector3.UP.cross(heading).normalized()
		var center := _player.get_global_transform_interpolated().origin + Vector3.UP * 0.62 - heading * 0.18
		# New particles inherit this basis. Emitted particles keep their world path.
		_flow.global_transform = Transform3D(Basis(side, Vector3.UP, heading), center)
		_flow.amount_ratio = clampf(_flow_amount, 0.15, 1.0)
		_flow_material.set_shader_parameter(&"flow_opacity", settings.speed_flow_opacity * _flow_amount)
		_flow.emitting = true
		_flow.show()
		_flow_tail = _flow.lifetime
	elif is_instance_valid(_flow):
		_flow.emitting = false
		_flow_tail = maxf(0.0, _flow_tail - delta)
		if _flow_tail <= 0.0: _flow.hide()

func _prepare_air() -> void:
	if is_instance_valid(_air): return
	_air = load(AIR_SCENE_PATH).instantiate() as PlayerAirEnvelope
	add_child(_air)

func _advance_air(delta: float, settings: PlayerActionVisuals) -> void:
	if is_instance_valid(_flow):
		_flow.emitting = false
		_flow.hide()
	var target := 0.0
	if settings.speed_flow_enabled and _body.flying:
		var low := maxf(0.0, settings.speed_rim_min_speed)
		target = smoothstep(low, maxf(low + 0.1, settings.motion_reference_speed), _body.flight_speed)
	var response := 0.045 if target > _flow_amount else maxf(0.02, settings.speed_flow_lifetime * 0.35)
	_flow_amount = lerpf(_flow_amount, target, 1.0 - exp(-delta / response))
	if target == 0.0 and _flow_amount < 0.002: _flow_amount = 0.0
	if _flow_amount > 0.0:
		_prepare_air()
		_air.synchronize(_player.sprite, _body.direction, _flow_amount, delta, settings)
		_flow_tail = settings.speed_flow_lifetime
	else:
		if is_instance_valid(_air): _air.stop()
		_flow_tail = 0.0

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	var settings := _player.action_visuals
	if not settings or _player.current_health <= 0.0:
		clear()
		return
	if _body.is_frozen():
		if is_instance_valid(_flow): _flow.speed_scale = 0.0
		return
	if is_instance_valid(_flow): _flow.speed_scale = 1.0
	delta = maxf(0.0, delta)
	_clock += delta
	_advance_flow(delta, settings)
	var target := 0.0
	if settings.speed_rim_enabled and _body.flying:
		var low := maxf(0.0, settings.speed_rim_min_speed)
		var high := maxf(low + 0.1, settings.motion_reference_speed)
		target = smoothstep(low, high, _body.flight_speed) * maxf(0.0, settings.speed_rim_strength)
	rim_amount = lerpf(rim_amount, target, 1.0 - exp(-delta / (0.025 if target > rim_amount else 0.055)))
	if not settings.speed_rim_enabled or (target == 0.0 and rim_amount < 0.002): rim_amount = 0.0
	_apply_rim(Vector4(rim_amount, settings.speed_rim_width_pixels, _clock, 0.0), _body.direction, settings.speed_rim_color)
	for index in range(_active.size() - 1, -1, -1):
		var item := _active[index]
		item.age += delta
		if not settings.surface_wave_enabled or item.age >= item.duration:
			_recycle(index)
		else:
			_update_wave(item)
	if rim_amount == 0.0 and _flow_tail <= 0.0 and _active.is_empty() and (not _body.flying or (not settings.speed_rim_enabled and not settings.speed_flow_enabled)): set_process(false)

func _apply_rim(data: Vector4, direction: Vector3, color: Color) -> void:
	if is_instance_valid(_player.sprite) and _player.sprite.has_method("set_speed_rim"):
		_player.sprite.set_speed_rim(data, direction, color)

func _recycle(index: int) -> void:
	var decal: Decal = _active[index].decal
	decal.hide()
	_pool.append(decal)
	_active.remove_at(index)

func active_count() -> int:
	return _active.size()

func clear() -> void:
	for index in range(_active.size() - 1, -1, -1): _recycle(index)
	rim_amount = 0.0
	_clock = 0.0
	_flow_amount = 0.0
	_flow_tail = 0.0
	if is_instance_valid(_air): _air.stop()
	if is_instance_valid(_flow):
		_flow.emitting = false
		_flow.speed_scale = 1.0
		_flow.restart()
		_flow.emitting = false
		_flow.hide()
	_apply_rim(Vector4.ZERO, Vector3.ZERO, Color.WHITE)
	set_process(false)
