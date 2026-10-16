class_name GroundSlashEffect
extends MeshInstance3D

const EFFECT_LAYER := preload("res://scripts/rendering/combat_effect_layer.gd")

## 帧动画与窄弧共用真实扫击投影、平地网格和实时挡墙裁切。
const ANGLES := 64
const RINGS := 4
var _material: ShaderMaterial
var _frame_material: ShaderMaterial
var _arc_material: ShaderMaterial
var _meowa_material: ShaderMaterial
var _indices := PackedInt32Array()
var _flat_meshes: Dictionary[Vector3, ArrayMesh] = {}
var _clipped: ArrayMesh
var _collision := ProjectileCollision.new()
var _layout := Vector4(-1, -1, -1, -1)

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = EFFECT_LAYER.material(preload("res://shaders/combat/player_sword.gdshader"))
	_frame_material = _material
	material_override = _material
	for angular in ANGLES:
		for ring in RINGS:
			var a := angular * (RINGS + 1) + ring
			var b := a + RINGS + 1
			_indices.append_array(PackedInt32Array([a, b, b + 1, a, b + 1, a + 1]))
	hide()

func display(origin: Vector3, heading: Vector3, radius: float, angle: float, reverse: bool,
		frames: SpriteFrames, age: float, rules: PlayerSwordRules, path: TerrainPath,
		surface: RefCounted, excluded: Array[RID]) -> void:
	var meowa_arc := rules.effect_mode == PlayerSwordRules.SlashVisual.MEOWA_ARC
	var arc_mode := rules.effect_mode != PlayerSwordRules.SlashVisual.FRAME_ANIMATION
	var uses_frames := rules.effect_mode != PlayerSwordRules.SlashVisual.THIN_ARC
	if uses_frames and (not frames or not frames.has_animation(&"slash") or frames.get_frame_count(&"slash") == 0):
		hide()
		return
	var progress := clampf(age / rules.sweep_seconds, 0.0, 1.0)
	var fade_seconds := rules.meowa_tail_seconds if meowa_arc else rules.fade_seconds
	var fade_progress := clampf((age - rules.sweep_seconds) / fade_seconds, 0.0, 1.0)
	var canvas := Vector2(2, 2)
	var art_radius := 1.0
	if meowa_arc:
		if not _meowa_material:
			_meowa_material = EFFECT_LAYER.material(preload("res://shaders/combat/player_sword_meowa_arc.gdshader"))
		_material = _meowa_material
		EFFECT_LAYER.set_parameter(_material, "body_opacity", rules.meowa_body_opacity)
		EFFECT_LAYER.set_parameter(_material, "tail_spread", rules.meowa_tail_spread)
		EFFECT_LAYER.set_parameter(_material, "tail_inner_ratio", rules.meowa_tail_inner_ratio)
	elif arc_mode:
		if not _arc_material:
			_arc_material = EFFECT_LAYER.material(preload("res://shaders/combat/player_sword_arc.gdshader"))
		_material = _arc_material
	else:
		_material = _frame_material
	if arc_mode:
		EFFECT_LAYER.set_parameter(_material, "attack_radius", radius)
		EFFECT_LAYER.set_parameter(_material, "band_width", rules.arc_width * clampf(pow(radius / rules.normal_range, 0.25), 1.0, 1.6))
		EFFECT_LAYER.set_parameter(_material, "trail_angle", deg_to_rad(rules.arc_trail_degrees))
		if not meowa_arc:
			EFFECT_LAYER.set_parameter(_material, "pixel_size", rules.arc_pixel_size)
			EFFECT_LAYER.set_parameter(_material, "blade_color", rules.arc_blade_color)
			EFFECT_LAYER.set_parameter(_material, "tail_color", rules.arc_tail_color)
	if uses_frames:
		var native_canvas := _bind_frame(frames, progress, fade_progress)
		if meowa_arc:
			EFFECT_LAYER.set_parameter(_material, "art_scale", Vector2.ONE * rules.art_radius_pixels / native_canvas)
		else:
			EFFECT_LAYER.set_parameter(_material, "half_angle", deg_to_rad(angle * 0.5))
			canvas = native_canvas
			art_radius = rules.art_radius_pixels
			EFFECT_LAYER.set_parameter(_material, "art_scale", canvas / art_radius)
	if material_override != _material: material_override = _material
	EFFECT_LAYER.set_parameter(_material, "opacity", rules.effect_opacity)
	EFFECT_LAYER.set_parameter(_material, "energy", rules.effect_energy)
	EFFECT_LAYER.set_parameter(_material, "leading_angle", lerpf(-deg_to_rad(angle * 0.5), deg_to_rad(angle * 0.5), progress))
	if not meowa_arc: EFFECT_LAYER.set_parameter(_material, "fade", 1.0 - fade_progress)
	global_position = origin
	global_basis = Basis(Vector3.UP, atan2(-heading.x, -heading.z))
	var camera := get_viewport().get_camera_3d()
	var view := camera.global_basis.z if camera else Vector3.BACK
	view.y = 0.0
	view = global_basis.inverse() * view.normalized()
	var toward := Vector2(view.x, view.z)
	var sideways := Vector2(-toward.y, toward.x)
	# 朝镜头抬起，避免浅俯视下某些出剑方向变成一条线；左右刀附加小幅斜切。
	var slope := -toward * tan(deg_to_rad(rules.effect_tilt_degrees))
	slope += sideways * tan(deg_to_rad(rules.effect_tilt_degrees * 0.35)) * (-1.0 if reverse else 1.0)
	slope = slope.limit_length(maxf(0.0, rules.effect_height - 0.08) / radius)
	EFFECT_LAYER.set_parameter(_material, "plane_slope", slope)
	var layout := Vector4(rules.effect_height, art_radius, canvas.x, canvas.y)
	if layout != _layout:
		_layout = layout
		_flat_meshes.clear()
	var flat: bool = surface.unclipped_flat(origin, radius)
	var key := Vector3(radius, angle, -1.0 if reverse else 1.0)
	if flat and _flat_meshes.has(key): mesh = _flat_meshes[key]
	else:
		var vertices := PackedVector3Array()
		var uvs := PackedVector2Array()
		var flat_ground: bool = flat or surface.flat_ground(origin, radius)
		var half := deg_to_rad(angle * 0.5)
		for angular in ANGLES + 1:
			var theta := lerpf(-half, half, float(angular) / ANGLES)
			var radial := Vector3(sin(theta), 0.0, -cos(theta))
			var direction := global_basis * radial
			var limit := radius
			if not flat:
				if not flat_ground: limit = _collision.ground_limit(path, origin, direction, limit, origin.y, rules.height_tolerance)
				var query := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.45, origin + Vector3.UP * 0.45 + direction * limit, 1, excluded)
				var hit := get_world_3d().direct_space_state.intersect_ray(query)
				if not hit.is_empty(): limit = maxf(0.0, origin.distance_to(hit.position - Vector3.UP * 0.45) - 0.02)
			for ring in RINGS + 1:
				var distance := limit * float(ring) / RINGS
				var point := radial * distance
				point.y = rules.effect_height if flat_ground else path.ground_position(origin + global_basis * point).y - origin.y + rules.effect_height
				vertices.append(point)
				var pixel := Vector2(radial.x * (-1.0 if reverse else 1.0), radial.z) * distance / radius * art_radius
				uvs.append(Vector2(0.5, 0.5) + pixel / canvas)
		var result: ArrayMesh = _flat_meshes.get(key) if flat else _clipped
		if result and DisplayServer.get_name() != "headless":
			result.surface_update_vertex_region(0, 0, vertices.to_byte_array())
			result.surface_update_attribute_region(0, 0, uvs.to_byte_array())
		else:
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			arrays[Mesh.ARRAY_INDEX] = _indices
			result = ArrayMesh.new()
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE)
		var bounds := AABB(vertices[0], Vector3.ZERO)
		for point in vertices: bounds = bounds.expand(point)
		# 顶点着色器只改变高度，预留导出倾斜上限的可见包围盒；旋转镜头不重建网格。
		var rise := radius * (tan(deg_to_rad(35.0)) + tan(deg_to_rad(35.0 * 0.35)))
		bounds.position.y -= rise
		bounds.size.y += rise * 2.0
		result.custom_aabb = bounds
		mesh = result
		if flat:
			# 当前参数的正反两把剑；参数改变时丢弃旧平面缓存。
			if _flat_meshes.size() >= 4: _flat_meshes.clear()
			_flat_meshes[key] = result
		else: _clipped = result
	show()

func _bind_frame(frames: SpriteFrames, progress: float, fade_progress: float) -> Vector2:
	var units := 0.0
	for frame in frames.get_frame_count(&"slash"): units += frames.get_frame_duration(&"slash", frame)
	var elapsed := units * (progress * 0.5 if progress < 1.0 else 0.5 + fade_progress * 0.5)
	var index := 0
	while index < frames.get_frame_count(&"slash") - 1 and elapsed >= frames.get_frame_duration(&"slash", index):
		elapsed -= frames.get_frame_duration(&"slash", index)
		index += 1
	var texture := frames.get_frame_texture(&"slash", index)
	if texture is AtlasTexture:
		var size: Vector2 = texture.atlas.get_size()
		EFFECT_LAYER.set_parameter(_material, "slash_texture", texture.atlas)
		EFFECT_LAYER.set_parameter(_material, "frame_rect", Vector4(texture.region.position.x / size.x, texture.region.position.y / size.y, texture.region.size.x / size.x, texture.region.size.y / size.y))
	else:
		EFFECT_LAYER.set_parameter(_material, "slash_texture", texture)
		EFFECT_LAYER.set_parameter(_material, "frame_rect", Vector4(0, 0, 1, 1))
	var blade_angles: PackedFloat32Array = frames.get_meta(&"blade_angles", PackedFloat32Array())
	EFFECT_LAYER.set_parameter(_material, "art_angle", blade_angles[index] if index < blade_angles.size() else 0.0)
	return Vector2(texture.get_size())
