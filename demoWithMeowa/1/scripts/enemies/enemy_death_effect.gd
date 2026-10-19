class_name EnemyDeathEffect
extends Node3D

signal finished
signal presentation_event(stage: StringName, point: Vector3)
const MATERIALS := preload("res://scripts/enemies/enemy_remains_materials.gd")
const ACCENTS := preload("res://scripts/enemies/enemy_death_accents.gd")
const HIT_SILHOUETTE := preload("res://scripts/rendering/hit_silhouette.gd")
static var _quad: QuadMesh
var _pieces: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _position := Vector3.ZERO
var _size := Vector2.ONE
var _pixel := 0.016
var _age := 0.0
var _shards := false
var _camera: Camera3D
var _knockout := false
var _active := false
var _duration := 0.25
var _travel := Vector3.ZERO
var _offset := Vector3.ZERO
var _height := 0.0
var _spin := 0.0
var _blocked := false
var _wall_offset := Vector3.ZERO
var _stars: EnemyStunEffect
var _collision: ProjectileCollision
var _random := RandomNumberGenerator.new()
var _pause_seconds := 0.0
var _air_seconds := 0.5
var _impact_source: SpriteFrames
var _impact_seconds := 0.16
var _impact_angle := 0.0
var _impact_frame := -1
var _ghosts: Array[MeshInstance3D] = []
var _accents: Node3D
var _trail_enabled := false
var _landing_enabled := false
var _bounce_height := 0.0
var _slide_distance := 0.0
var _burst_only := false
var _impact_radius := 0.0
var _air_announced := false
var _landing_announced := false
var _readability := false
var _focus_seconds := 0.28
var _visual_excluded: Array[RID] = []
var _hit_silhouette := HIT_SILHOUETTE.new()
var _impact_opacity := 1.0
var _impact_flash := 0.9

func _ready() -> void:
	MATERIALS.retain()
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_random.randomize()
	if not _quad: _quad = QuadMesh.new()
	for index in 4:
		var piece := MeshInstance3D.new()
		piece.mesh = _quad
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(piece)
		_pieces.append(piece)
		_materials.append(null)
	stop()

func _exit_tree() -> void:
	MATERIALS.release()

## 建立完整的闲置对象，不播放动画、不抽取死亡方向或发出声音。
func prepare(visuals: PlayerActionVisuals) -> void:
	_prepare_nodes(visuals)
	MATERIALS.prepare_frames(visuals.melee_death_impact_frames)

func _prepare_nodes(visuals: PlayerActionVisuals) -> void:
	if visuals.melee_death_trail_enabled or visuals.melee_death_landing_enabled or visuals.melee_death_cluster_enabled: _ensure_accents()
	if visuals.melee_death_trail_enabled and _ghosts.is_empty():
		for index in 2:
			var ghost := MeshInstance3D.new()
			ghost.mesh = _quad
			ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(ghost)
			ghost.hide()
			_ghosts.append(ghost)
	if not _collision: _collision = ProjectileCollision.new()
	if not _stars:
		_stars = EnemyStunEffect.new()
		add_child(_stars)

func begin(sprite: Sprite3D, shards: bool, camera: Camera3D, visuals: PlayerActionVisuals = null, hit: Dictionary = {}) -> void:
	stop()
	_camera = camera
	_position = sprite.global_position
	_pixel = sprite.pixel_size * sprite.global_basis.x.length()
	_size = sprite.texture.get_size() * _pixel
	_age = 0.0
	_air_announced = false
	_landing_announced = false
	_knockout = visuals != null
	_impact_opacity = 0.45 if _knockout and visuals.kill_impact_enabled else 1.0
	_impact_flash = 0.35 if _knockout and visuals.kill_shot_enabled else 0.9
	_shards = shards and not _knockout
	_duration = 0.3 if _shards else 0.25
	_offset = Vector3.ZERO
	_blocked = false
	_wall_offset = Vector3.ZERO
	_visual_excluded.assign(hit.get("visual_excluded", []))
	_burst_only = false
	_impact_radius = 0.0
	if _knockout:
		# 每次死亡只抽取一次世界方向，不消耗出怪／成长使用的全局随机流。
		var angle := _random.randf_range(-PI, PI)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var strength := visuals.melee_death_strength(hit)
		_readability = visuals.combat_readability_enabled
		_focus_seconds = visuals.combat_death_focus_seconds
		_travel = direction * visuals.melee_death_distance * strength * _random.randf_range(0.85, 1.15)
		_height = visuals.melee_death_height * sqrt(strength) * _random.randf_range(0.93, 1.07)
		_duration = maxf(visuals.melee_death_seconds, 0.1)
		_pause_seconds = clampf(visuals.melee_death_hit_pause, 0.0, _duration * 0.25)
		_air_seconds = clampf(visuals.melee_death_air_seconds, 0.05, maxf(0.05, _duration - _pause_seconds))
		_impact_source = visuals.melee_death_impact_frames
		_impact_seconds = maxf(0.01, visuals.melee_death_impact_seconds)
		_impact_frame = -1
		_impact_angle = _random.randf_range(-PI, PI)
		_spin = deg_to_rad(visuals.melee_death_spin_degrees) * strength * _random.randf_range(0.9, 1.1) * (-1.0 if _random.randi_range(0, 1) == 0 else 1.0)
		_trail_enabled = visuals.melee_death_trail_enabled
		_landing_enabled = visuals.melee_death_landing_enabled
		_bounce_height = visuals.melee_death_bounce_height * sqrt(strength)
		_slide_distance = visuals.melee_death_slide_distance * strength
		_prepare_nodes(visuals)
	var texture := sprite.texture
	var rect := Rect2(Vector2.ZERO, Vector2.ONE)
	if texture is AtlasTexture:
		var atlas := texture as AtlasTexture
		rect = Rect2(atlas.region.position / atlas.atlas.get_size(), atlas.region.size / atlas.atlas.get_size())
		texture = atlas.atlas
	if sprite.flip_h:
		rect.position.x += rect.size.x
		rect.size.x = -rect.size.x
	if sprite.flip_v:
		rect.position.y += rect.size.y
		rect.size.y = -rect.size.y
	for index in (4 if _shards else 1):
		_materials[index] = MATERIALS.material(texture, _knockout)
		_pieces[index].material_override = _materials[index]
		var part := Rect2(Vector2.ZERO, Vector2.ONE)
		if _shards: part = Rect2(Vector2(index % 2, index / 2) * 0.5, Vector2.ONE * 0.5)
		var uv := Rect2(rect.position + part.position * rect.size, part.size * rect.size)
		_pieces[index].set_instance_shader_parameter(&"frame_rect", Vector4(uv.position.x, uv.position.y, uv.size.x, uv.size.y))
		_pieces[index].set_instance_shader_parameter(&"tint", sprite.modulate if _knockout else Color.WHITE)
		_pieces[index].set_instance_shader_parameter(&"hit_flash", 0.0)
		_pieces[index].set_instance_shader_parameter(&"death_energy", 0.3 if _knockout else 0.0)
		_pieces[index].show()
	if _knockout and _trail_enabled:
		for ghost in _ghosts:
			ghost.material_override = MATERIALS.material(texture, true, true)
			for parameter in [&"frame_rect", &"tint"]:
				ghost.set_instance_shader_parameter(parameter, _pieces[0].get_instance_shader_parameter(parameter))
			ghost.set_instance_shader_parameter(&"death_energy", 0.1)
	if _hit_silhouette.strike(visuals, hit.get("source", &"")):
		for piece in _pieces:
			piece.set_instance_shader_parameter(&"hit_silhouette_rim_color", _hit_silhouette.rim_color)
	_active = true
	set_process(true)
	_process(0.0)

func get_focus_subject() -> MeshInstance3D:
	return _pieces[0] if not _pieces.is_empty() else null

func stop() -> void:
	_active = false
	_hit_silhouette.clear()
	for piece in _pieces:
		piece.hide()
		piece.set_instance_shader_parameter("wave_finish_silhouette", 0.0)
		piece.set_instance_shader_parameter(&"hit_silhouette_amount", 0.0)
	for ghost in _ghosts: ghost.hide()
	_impact_opacity = 1.0
	_impact_flash = 0.9
	if is_instance_valid(_accents): _accents.hide()
	if is_instance_valid(_stars): _stars.stop()
	set_process(false)

func _process(delta: float) -> void:
	if not _active: return
	if _hit_silhouette.remaining > 0.0:
		_hit_silhouette.advance(delta / maxf(Engine.time_scale, 0.001))
		for piece in _pieces:
			if piece.visible: piece.set_instance_shader_parameter(&"hit_silhouette_amount", _hit_silhouette.amount)
	_age += delta
	if _age >= _duration:
		stop()
		finished.emit()
		return
	var right := _camera.global_basis.x if is_instance_valid(_camera) else Vector3.RIGHT
	right.y = 0.0
	right = right.normalized()
	var facing := Basis(right, Vector3.UP, right.cross(Vector3.UP))
	var progress := _age / _duration
	if _burst_only:
		_display_impact(facing)
		_accents.burst(_position, _pixel, facing, progress, _impact_angle)
		return
	if _knockout:
		_display_knockout(facing, progress)
		return
	for index in (4 if _shards else 1):
		var side := Vector2(-1 if index % 2 == 0 else 1, 1 if index < 2 else -1)
		var offset := side * (_size * 0.25 + Vector2.ONE * floorf(progress * 4.0) * _pixel) if _shards else Vector2(0, -floorf(progress * 2.0) * _pixel)
		_pieces[index].global_position = _position + facing * Vector3(offset.x, offset.y, 0)
		_pieces[index].global_basis = facing.scaled_local(Vector3(_size.x, _size.y, 1) * Vector3(0.5, 0.5, 1) if _shards else Vector3(_size.x, _size.y, 1))
		_pieces[index].set_instance_shader_parameter("opacity", 1.0 - progress)

func _display_knockout(facing: Basis, progress: float) -> void:
	var flight := clampf((_age - _pause_seconds) / _air_seconds, 0.0, 1.0)
	var next := _flight_offset(flight)
	var landing := clampf((_age - _pause_seconds - _air_seconds) / 0.18, 0.0, 1.0)
	if _landing_enabled and flight >= 1.0:
		if not _blocked: next += _travel.normalized() * _slide_distance * (1.0 - pow(1.0 - landing, 2.0))
		next.y = 4.0 * _bounce_height * landing * (1.0 - landing)
	if not _blocked and not next.is_equal_approx(_offset):
		var start := _position + _offset
		var end := _position + next
		var contact := _collision.wall_contact(get_world_3d().direct_space_state, start, end, maxf(_pixel * 2.0, 0.04), _visual_excluded)
		if not contact.is_empty():
			var point := start.move_toward(end, maxf(0.0, float(contact.distance) - 0.005)) - _position
			_wall_offset = Vector3(point.x, 0.0, point.z)
			_blocked = true
			presentation_event.emit(&"wall", _position + point)
	if _blocked:
		next.x = _wall_offset.x
		next.z = _wall_offset.z
	_offset = next
	if not _air_announced and _age >= _pause_seconds:
		_air_announced = true
		presentation_event.emit(&"air", _position + next)
	if _landing_enabled and flight >= 1.0 and not _landing_announced:
		_landing_announced = true
		presentation_event.emit(&"land", _position + next)
	var opacity := 1.0 - smoothstep(0.72, 1.0, progress)
	var retire := smoothstep(_focus_seconds, _focus_seconds + 0.18, _age) if _readability else 0.0
	opacity *= lerpf(1.0, 0.7, retire)
	_pieces[0].set_instance_shader_parameter(&"death_energy", lerpf(0.3, 0.08, retire))
	_pieces[0].global_position = _position + next
	_pieces[0].global_basis = (facing * Basis(Vector3.BACK, _spin * flight)).scaled_local(Vector3(_size.x, _size.y, 1.0))
	_pieces[0].set_instance_shader_parameter(&"opacity", opacity)
	_pieces[0].set_instance_shader_parameter(&"hit_flash", maxf(0.0, 1.0 - _age / 0.1) * _impact_flash)
	_stars.display_at(_position + next + Vector3.UP * (_size.y * 0.5 + _pixel * 2.0), _pixel, _age, opacity, _camera)
	_display_trail(facing, flight, opacity)
	if _trail_enabled or _landing_enabled: _accents.flight(self, facing, progress)
	_display_impact(facing)

func _flight_offset(flight: float) -> Vector3:
	var point := _travel * (1.0 - pow(1.0 - flight, 3.0))
	point.y = 4.0 * _height * flight * (1.0 - flight)
	if _blocked:
		point.x = _wall_offset.x
		point.z = _wall_offset.z
	return point

func _display_trail(facing: Basis, flight: float, opacity: float) -> void:
	if not _trail_enabled: return
	for index in _ghosts.size():
		var ghost := _ghosts[index]
		var delay := (index + 1) * 0.055 / _air_seconds
		ghost.visible = flight > delay and flight < 0.95
		if not ghost.visible: continue
		var part := flight - delay
		ghost.global_position = _position + _flight_offset(part)
		ghost.global_basis = (facing * Basis(Vector3.BACK, _spin * part)).scaled_local(Vector3(_size.x, _size.y, 1))
		ghost.set_instance_shader_parameter(&"opacity", opacity * (0.22 - index * 0.07))

func _ensure_accents() -> void:
	if _accents: return
	_accents = ACCENTS.new()
	add_child(_accents)

## 同一反馈池的密集击杀只生成一次较宽的放射爆点，没有尸体或伤害。
func begin_burst(point: Vector3, pixel: float, camera: Camera3D, visuals: PlayerActionVisuals) -> void:
	stop()
	_impact_opacity = 0.45 if visuals.kill_impact_enabled else 1.0
	_position = point
	_pixel = pixel
	_camera = camera
	_age = 0.0
	_burst_only = true
	_knockout = false
	_duration = 0.22
	_impact_seconds = _duration
	_impact_source = visuals.melee_death_impact_frames
	_impact_frame = -1
	_impact_angle = _random.randf_range(-PI, PI)
	_impact_radius = 0.75
	_ensure_accents()
	_active = true
	set_process(true)
	_process(0.0)

func _display_impact(facing: Basis) -> void:
	if _age >= _impact_seconds or not _impact_source or not _impact_source.has_animation(&"bounce"):
		for index in range(1, 4): _pieces[index].hide()
		return
	var count := _impact_source.get_frame_count(&"bounce")
	if count == 0: return
	var frame := mini(count - 1, int(_age / _impact_seconds * count))
	var image := _impact_source.get_frame_texture(&"bounce", frame)
	if not image: return
	var size := image.get_size() * _pixel
	for index in 3:
		var slot := index + 1
		if frame != _impact_frame:
			var texture: Texture2D = image.atlas if image is AtlasTexture else image
			var rect: Rect2 = image.region if image is AtlasTexture else Rect2(Vector2.ZERO, image.get_size())
			var uv := Vector4(rect.position.x / texture.get_width(), rect.position.y / texture.get_height(), rect.size.x / texture.get_width(), rect.size.y / texture.get_height())
			_materials[slot] = MATERIALS.material(texture)
			_pieces[slot].material_override = _materials[slot]
			_pieces[slot].set_instance_shader_parameter(&"frame_rect", uv)
			_pieces[slot].set_instance_shader_parameter(&"tint", Color.WHITE)
			_pieces[slot].set_instance_shader_parameter(&"opacity", _impact_opacity)
			_pieces[slot].set_instance_shader_parameter(&"hit_flash", 0.0)
			_pieces[slot].set_instance_shader_parameter(&"death_energy", 1.2)
		var basis := facing * Basis(Vector3.BACK, _impact_angle + index * TAU / 3.0)
		# 原生 56×48 碰点的 (19,24) 是中心；三份原帧组成紧凑的放射爆点。
		var anchor := (image.get_size() * 0.5 - Vector2(19, 24)) * _pixel
		var spread := Vector3(_impact_radius * _age / _impact_seconds, 0, 0)
		_pieces[slot].global_position = _position + basis * (Vector3(anchor.x, -anchor.y, 0.0) + spread)
		_pieces[slot].global_basis = basis.scaled_local(Vector3(size.x, size.y, 1.0))
		_pieces[slot].show()
	_impact_frame = frame
