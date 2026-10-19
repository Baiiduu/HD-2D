class_name PlayerBounceEffect
extends Node3D

## 只消费已完成的真实反弹事件；Meowa 原生帧留在世界碰点，不结算运动或伤害。
const SHADER := preload("res://shaders/combat/player_bounce.gdshader")
const DEBRIS := preload("res://scripts/enemies/hit_debris.gd")
static var _quad: QuadMesh
var _player: Player
var _body: PlayerRicochet
var _active: Array[Dictionary] = []
var _pool: Array[Dictionary] = []
var _source: SpriteFrames
var _frames: Array[Dictionary] = []
var _materials: Dictionary = {}
var sparks: MultiMeshInstance3D
var _particle_serial := -1

func _ready() -> void:
	_player = get_parent() as Player
	_body = _player.body_ricochet
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_priority = 3
	_body.wall_bounced.connect(_bounced)
	_body.impact_recorded.connect(_impact_recorded)
	if _player.action_visuals and _player.action_visuals.bounce_particles_enabled: _prepare_sparks()
	if is_instance_valid(_body._session): _body._session.phase_changed.connect(_phase_changed)
	set_process(false)

func _phase_changed(_phase: int) -> void:
	clear()

func _frames_changed() -> void:
	_frames = []
	_materials = {}

func _prepare_frames(source: SpriteFrames) -> bool:
	if source != _source:
		if _source and _source.changed.is_connected(_frames_changed): _source.changed.disconnect(_frames_changed)
		_source = source
		if _source: _source.changed.connect(_frames_changed)
		_frames_changed()
	if not _source or not _source.has_animation(&"bounce"): return false
	if not _frames.is_empty(): return true
	var frames: Array[Dictionary] = []
	var total := 0.0
	for index in _source.get_frame_count(&"bounce"):
		var frame := _source.get_frame_texture(&"bounce", index)
		if not frame: return false
		var texture: Texture2D = frame.atlas if frame is AtlasTexture else frame
		var region: Rect2 = frame.region if frame is AtlasTexture else Rect2(Vector2.ZERO, frame.get_size())
		if not texture: return false
		if not _materials.has(texture):
			var material := ShaderMaterial.new()
			material.shader = SHADER
			material.set_shader_parameter("effect_texture", texture)
			_materials[texture] = material
		total += _source.get_frame_duration(&"bounce", index)
		frames.append({"material": _materials[texture], "size": frame.get_size(), "end": total,
			"uv": Vector4(region.position.x / texture.get_width(), region.position.y / texture.get_height(), region.size.x / texture.get_width(), region.size.y / texture.get_height())})
	if total <= 0.0: return false
	for frame in frames: frame.end /= total
	_frames = frames
	return not _frames.is_empty()

func _bounced(point: Vector3, normal: Vector3) -> void:
	var maximum := _body._settings.maximum_launch_speed if _body._settings else _body.flight_speed
	play(point, normal, _body.direction, clampf(_body.flight_speed / maxf(maximum, 0.001), 0.0, 1.0))

func _prepare_sparks() -> void:
	if is_instance_valid(sparks): return
	sparks = DEBRIS.new()
	sparks.set("capacity", 256)
	add_child(sparks)

func _impact_recorded(impact: RicochetImpact) -> void:
	var settings := _player.action_visuals
	if impact.serial <= _particle_serial or not settings or not settings.bounce_particles_enabled: return
	_particle_serial = impact.serial
	_prepare_sparks()
	var point := impact.point
	point.y = _player.global_position.y + settings.bounce_height
	sparks.rebound(point, impact, _player.sprite.pixel_size * _player.sprite.global_basis.x.length(), settings)
	if sparks.active:
		show()
		set_process(true)

func play(contact: Vector3, normal: Vector3, outgoing: Vector3, strength := 1.0) -> bool:
	var settings := _player.action_visuals
	if not settings or not settings.show_bounce_effect or not is_finite(settings.bounce_duration) or settings.bounce_duration <= 0.0: return false
	if not contact.is_finite() or not normal.is_finite() or not outgoing.is_finite(): return false
	if not _prepare_frames(settings.bounce_frames): return false
	var pixel := _player.sprite.pixel_size * _player.sprite.global_basis.x.length()
	if pixel <= 0.0: return false
	normal.y = 0.0
	normal = normal.normalized()
	var direction := normal.lerp(outgoing, 0.35).normalized()
	if direction.is_zero_approx(): direction = normal if not normal.is_zero_approx() else Vector3.RIGHT
	# 碰点 XZ 保持真实接触，显示高度单独配置，略向墙外留出深度间隔。
	var point := contact + normal * (0.02 + pixel * 0.5)
	point.y = _player.global_position.y + settings.bounce_height
	var item: Dictionary = _pool.pop_back() if not _pool.is_empty() else _create()
	item.merge({"point": point, "direction": direction, "age": 0.0, "presented": false, "frame": -1,
		"duration": settings.bounce_duration, "pixel": pixel, "anchor": settings.bounce_anchor_pixels,
		"opacity": settings.bounce_opacity * lerpf(0.75, 1.0, clampf(strength, 0.0, 1.0)),
		"energy": settings.bounce_energy * lerpf(0.65, 1.0, clampf(strength, 0.0, 1.0)), "frames": _frames}, true)
	_active.append(item)
	_update(item, get_viewport().get_camera_3d())
	show()
	set_process(true)
	return true

func _create() -> Dictionary:
	if not _quad: _quad = QuadMesh.new()
	var mesh := MeshInstance3D.new()
	mesh.mesh = _quad
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mesh.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(mesh)
	return {"mesh": mesh}

func _process(delta: float) -> void:
	if not _player.action_visuals:
		clear()
		return
	if _body.is_frozen(): return
	if is_instance_valid(sparks):
		if _player.action_visuals.bounce_particles_enabled: sparks.advance(maxf(0.0, delta))
		else: sparks.clear()
	var camera := get_viewport().get_camera_3d()
	for index in range(_active.size() - 1, -1, -1):
		var item := _active[index]
		# 新碰撞至少显示一次首帧，低帧率时也不直接跳过整次短闪。
		if item.presented: item.age += maxf(0.0, delta)
		item.presented = true
		if item.age >= item.duration or not _player.action_visuals.show_bounce_effect:
			item.mesh.hide()
			_pool.append(item)
			_active.remove_at(index)
			continue
		_update(item, camera)
	if _active.is_empty() and (not is_instance_valid(sparks) or not sparks.active):
		hide()
		set_process(false)

func _update(item: Dictionary, camera: Camera3D) -> void:
	var progress: float = item.age / item.duration
	var index := 0
	while index < item.frames.size() - 1 and progress >= float(item.frames[index].end): index += 1
	var frame: Dictionary = item.frames[index]
	var mesh := item.mesh as MeshInstance3D
	if item.frame != index:
		mesh.material_override = frame.material
		mesh.set_instance_shader_parameter("frame_rect", frame.uv)
		item.frame = index
	var basis := camera.global_basis.orthonormalized() if camera else Basis.IDENTITY
	var angle := atan2(item.direction.dot(basis.y), item.direction.dot(basis.x))
	basis *= Basis(Vector3.BACK, angle)
	var size: Vector2 = frame.size
	var offset := Vector2(size.x * 0.5 - item.anchor.x, item.anchor.y - size.y * 0.5) * float(item.pixel)
	mesh.global_transform = Transform3D(basis.scaled_local(Vector3(size.x * item.pixel, size.y * item.pixel, 1.0)), item.point + basis.x * offset.x + basis.y * offset.y)
	mesh.set_instance_shader_parameter("opacity", item.opacity * (1.0 - smoothstep(0.75, 1.0, progress)))
	mesh.set_instance_shader_parameter("energy", item.energy)
	mesh.show()

func clear() -> void:
	if is_instance_valid(sparks): sparks.clear()
	for item in _active:
		item.mesh.hide()
		_pool.append(item)
	_active.clear()
	hide()
	set_process(false)

func _exit_tree() -> void:
	if _source and _source.changed.is_connected(_frames_changed): _source.changed.disconnect(_frames_changed)
