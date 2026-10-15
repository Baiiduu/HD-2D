class_name AimPathPreview
extends Node3D

const IMPORTED_IMAGE := preload("res://scripts/rendering/imported_texture_image.gd")

## 可复用的虚线路径／接触点／单目标角标显示。消费世界路径，不读取技能或怪物规则。
static var _quad: QuadMesh
static var _users := 0
var route: AimPathData
var _camera: Camera3D
var _lines: MultiMeshInstance3D
var _contacts: MultiMeshInstance3D
var _target: MeshInstance3D
var _line_material: ShaderMaterial
var _contact_material: ShaderMaterial
var _target_material: ShaderMaterial
var _target_sprite: Sprite3D
var _bounds: Dictionary[Texture2D, Rect2i] = {}
var _source_images: Dictionary[Texture2D, Image] = {}
var _image_watches: Dictionary[Texture2D, bool] = {}
var _source_image_bytes := 0
var _pixel := 0.016
var _height := 0.0
var _skip := 0.0
var _width := 1.0
var _opacity := 0.45

func _ready() -> void:
	_users += 1
	if not _quad: _quad = QuadMesh.new()
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	process_priority = 3
	_lines = _make_multimesh(true)
	_contacts = _make_multimesh(false)
	_line_material = ShaderMaterial.new()
	_line_material.shader = preload("res://shaders/combat/aim_path.gdshader")
	_lines.material_override = _line_material
	_contact_material = ShaderMaterial.new()
	_contact_material.shader = preload("res://shaders/combat/aim_marker.gdshader")
	_contacts.material_override = _contact_material
	_target = MeshInstance3D.new()
	_target.mesh = _quad
	_target.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_target_material = ShaderMaterial.new()
	_target_material.shader = preload("res://shaders/combat/aim_marker.gdshader")
	_target_material.set_shader_parameter("brackets", true)
	_target.material_override = _target_material
	add_child(_target)
	stop()

func _exit_tree() -> void:
	_clear_image_facts()
	_users -= 1
	if _users == 0: _quad = null

func _make_multimesh(custom: bool) -> MultiMeshInstance3D:
	var instance := MultiMeshInstance3D.new()
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.multimesh = MultiMesh.new()
	instance.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	instance.multimesh.use_custom_data = custom
	instance.multimesh.mesh = _quad
	instance.multimesh.instance_count = 8
	add_child(instance)
	return instance

func display(data: AimPathData, camera: Camera3D, pixel: float, height: float,
		skip_distance: float, width: float, tint: Color, opacity: float) -> void:
	route = data
	_camera = camera
	_pixel = pixel
	_height = height
	_skip = skip_distance
	_width = width
	_opacity = opacity
	for material in [_line_material, _contact_material, _target_material]:
		material.set_shader_parameter("tint", tint)
		material.set_shader_parameter("opacity", opacity)
	_line_material.set_shader_parameter("dash_period", _pixel * 14.0)
	_target_material.set_shader_parameter("opacity", minf(0.8, opacity * 1.4))
	show()
	set_process(true)
	_process(0.0)

func mark_target(sprite: Sprite3D) -> void:
	_target_sprite = sprite
	_update_target()

func stop() -> void:
	hide()
	set_process(false)
	route = null
	_target_sprite = null
	if _target: _target.hide()

func _process(_delta: float) -> void:
	if not route: return
	global_transform = Transform3D.IDENTITY
	var view := _camera.global_basis.z if is_instance_valid(_camera) else Vector3.BACK
	if _lines.multimesh.instance_count < route.segments.size(): _lines.multimesh.instance_count = route.segments.size()
	var count := 0
	for piece in route.segments:
		var length := TerrainPath.horizontal_distance(piece.start, piece.end)
		var skipped := clampf(_skip - piece.distance, 0.0, length)
		if length - skipped < 0.00001: continue
		var start: Vector3 = piece.start.lerp(piece.end, skipped / length)
		var end: Vector3 = piece.end
		var heading: Vector3 = (end - start).normalized()
		var side := view.cross(heading).normalized()
		if side.is_zero_approx(): side = Vector3.UP
		var basis := Basis(heading * (length - skipped), side * _pixel * _width, view)
		_lines.multimesh.set_instance_transform(count, Transform3D(basis, (start + end) * 0.5 + Vector3.UP * _height))
		var first := _fade(piece.distance + skipped, piece.bounce)
		var last := _fade(piece.distance + length, piece.bounce)
		_lines.multimesh.set_instance_custom_data(count, Color(piece.distance + skipped, length - skipped, first, last))
		count += 1
	_lines.multimesh.visible_instance_count = count
	var camera_basis := _camera.global_basis.orthonormalized() if is_instance_valid(_camera) else Basis.IDENTITY
	var contact_count := route.contacts.size() + route.crowd_contacts.size()
	if _contacts.multimesh.instance_count < contact_count: _contacts.multimesh.instance_count = contact_count
	_contacts.multimesh.visible_instance_count = contact_count
	_contact_material.set_shader_parameter("size_pixels", Vector2.ONE * 6.0)
	for index in contact_count:
		var point := route.contacts[index] if index < route.contacts.size() else route.crowd_contacts[index - route.contacts.size()]
		_contacts.multimesh.set_instance_transform(index, Transform3D(camera_basis.scaled_local(Vector3.ONE * _pixel * 6.0), point + Vector3.UP * _height))
	_update_target()

func _fade(distance: float, bounce: int) -> float:
	var end := 1.0 - smoothstep(maxf(_skip, route.total_distance * 0.75), route.total_distance, distance)
	return end * pow(0.6, bounce)

func _update_target() -> void:
	_target.visible = is_instance_valid(_target_sprite) and _target_sprite.is_visible_in_tree() and _target_sprite.texture != null
	if not _target.visible: return
	var sprite := _target_sprite
	var texture := sprite.texture
	var rect: Rect2
	if not _bounds.has(texture):
		# 有效期随纹理资源，最多保留 64 个原生帧；只读透明边界，不处理或重采样素材。
		if _bounds.size() >= 64: _bounds.clear()
		var atlas := texture as AtlasTexture
		var source := atlas.atlas if atlas else texture
		var cacheable := _watch_bounds_texture(texture)
		var image := _bounds_source_image(source, cacheable)
		if atlas and image:
			var region := atlas.region
			if region.size == Vector2.ZERO: region.size = source.get_size()
			image = image.get_region(region)
		var used := image.get_used_rect() if image and not image.is_empty() else Rect2i(Vector2i.ZERO, texture.get_size())
		if atlas: used.position += Vector2i(atlas.margin.position)
		if cacheable: _bounds[texture] = used
		rect = Rect2(used)
	else:
		rect = Rect2(_bounds[texture])
	var camera_basis := _camera.global_basis.orthonormalized() if is_instance_valid(_camera) else Basis.IDENTITY
	var right := camera_basis.x
	var up := camera_basis.y
	if sprite.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y:
		right.y = 0.0
		right = right.normalized()
		up = Vector3.UP
	var density := Vector2(sprite.global_basis.x.length(), sprite.global_basis.y.length()) * sprite.pixel_size
	var center := rect.get_center() - Vector2(texture.get_size()) * 0.5
	center.x *= -1.0 if sprite.flip_h else 1.0
	center.y *= -1.0 if sprite.flip_v else 1.0
	center = Vector2(center.x, -center.y) + sprite.offset
	var size := rect.size * density + Vector2.ONE * _pixel * 6.0
	_target.position = sprite.get_global_transform_interpolated().origin + right * center.x * density.x + up * center.y * density.y
	_target.basis = Basis(right * size.x, up * size.y, right.cross(up))
	_target_material.set_shader_parameter("size_pixels", size / _pixel)

## Images are private facts owned by this preview, bounded by sheet count and
## decoded bytes. A changed texture clears both sheet images and frame bounds.
func _watch_bounds_texture(texture: Texture2D) -> bool:
	var chain: Array[Texture2D] = []
	var current: Texture2D = texture
	var seen: Dictionary[int, bool] = {}
	while current:
		var id := current.get_instance_id()
		if seen.has(id) or chain.size() >= 128:
			return false
		seen[id] = true
		chain.append(current)
		current = current.atlas if current is AtlasTexture else null
	if _image_watches.size() + chain.size() > 128:
		_clear_image_facts()
	for item in chain:
		if not _image_watches.has(item):
			item.changed.connect(_on_bounds_texture_changed)
			_image_watches[item] = true
	return true

func _on_bounds_texture_changed() -> void:
	_clear_image_facts()

func _clear_image_facts() -> void:
	for texture in _image_watches:
		if texture.changed.is_connected(_on_bounds_texture_changed):
			texture.changed.disconnect(_on_bounds_texture_changed)
	_image_watches.clear()
	_source_images.clear()
	_source_image_bytes = 0
	_bounds.clear()

func _bounds_source_image(source: Texture2D, cacheable: bool) -> Image:
	if cacheable and _source_images.has(source):
		return _source_images[source]
	var image: Image = _read_bounds_image(source)
	if image and image.is_compressed():
		image.decompress()
	if cacheable and image:
		var bytes := image.get_data().size()
		# A large source can still be read exactly without retaining it.
		if bytes <= 8 * 1024 * 1024:
			if _source_images.size() >= 32 or _source_image_bytes + bytes > 8 * 1024 * 1024:
				_source_images.clear()
				_source_image_bytes = 0
			_source_images[source] = image
			_source_image_bytes += bytes
	return image

func _read_bounds_image(source: Texture2D) -> Image:
	return IMPORTED_IMAGE.read(source)
