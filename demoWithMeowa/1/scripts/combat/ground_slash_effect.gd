@tool
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
var _ribbon_material: ShaderMaterial
var _flow_material: ShaderMaterial
var _orbit_material: ShaderMaterial
var _indices := PackedInt32Array()
var _flat_meshes: Dictionary[Vector4, ArrayMesh] = {}
var _clipped: ArrayMesh
var _collision := ProjectileCollision.new()
var _layout := Vector3(-1, -1, -1)
var _radials := PackedVector3Array()
var _radial_angle := NAN
var _angular_steps := ANGLES
var _wall_ray := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 1)

class PreparationSurface extends RefCounted:
	func unclipped_flat(_origin: Vector3, _radius: float) -> bool: return true
	func flat_ground(_origin: Vector3, _radius: float) -> bool: return true

func prepare_feedback(rules: PlayerSwordRules, radius: float, angle: float) -> void:
	var placement := global_transform
	for reverse in [false, true]:
		display(Vector3.ZERO, Vector3.FORWARD, radius, angle, reverse, rules.frames,
			rules.sweep_seconds * 0.5, rules, null, PreparationSurface.new(), [])
	global_transform = placement
	hide()

func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = EFFECT_LAYER.material(preload("res://shaders/combat/player_sword.gdshader"))
	_frame_material = _material
	material_override = _material
	_build_indices(ANGLES)
	hide()

func _build_indices(steps: int) -> void:
	_angular_steps = steps
	_indices.clear()
	for angular in steps:
		for ring in RINGS:
			var a := angular * (RINGS + 1) + ring
			var b := a + RINGS + 1
			_indices.append_array(PackedInt32Array([a, b, b + 1, a, b + 1, a + 1]))

func display(origin: Vector3, heading: Vector3, radius: float, angle: float, reverse: bool,
		frames: SpriteFrames, age: float, rules: PlayerSwordRules, path: TerrainPath,
		surface: RefCounted, excluded: Array[RID], presentation_opacity := 1.0) -> void:
	var meowa_arc := rules.effect_mode == PlayerSwordRules.SlashVisual.MEOWA_ARC
	var ribbon := rules.effect_mode == PlayerSwordRules.SlashVisual.NATIVE_RIBBON
	var arc_mode := rules.effect_mode != PlayerSwordRules.SlashVisual.FRAME_ANIMATION
	var uses_frames := not ribbon and rules.effect_mode != PlayerSwordRules.SlashVisual.THIN_ARC
	if ribbon and not rules.ribbon_visual:
		hide()
		return
	var effect_height := maxf(0.08, rules.effect_height + rules.ribbon_visual.ribbon_height_offset) if ribbon else rules.effect_height
	if uses_frames and (not frames or not frames.has_animation(&"slash") or frames.get_frame_count(&"slash") == 0):
		hide()
		return
	var progress := clampf(age / rules.sweep_seconds, 0.0, 1.0)
	var fade_seconds := rules.tail_seconds() if rules.has_world_tail() else rules.fade_seconds
	var fade_progress := clampf((age - rules.sweep_seconds) / fade_seconds, 0.0, 1.0)
	var canvas := Vector2(2, 2)
	var art_radius := 1.0
	var stretch := Vector3.ONE
	if meowa_arc:
		if not _meowa_material:
			_meowa_material = EFFECT_LAYER.material(preload("res://shaders/combat/player_sword_meowa_arc.gdshader"))
		_material = _meowa_material
		stretch = rules.meowa_stretch_profile(progress, fade_progress)
		EFFECT_LAYER.set_parameter(_material, "body_opacity", rules.meowa_body_opacity * stretch.z)
		EFFECT_LAYER.set_parameter(_material, "tail_width_scale", stretch.y)
		EFFECT_LAYER.set_parameter(_material, "visibility_strength", rules.meowa_visibility_strength)
		EFFECT_LAYER.set_parameter(_material, "tail_spread", rules.meowa_tail_spread)
		EFFECT_LAYER.set_parameter(_material, "tail_inner_ratio", rules.meowa_tail_inner_ratio)
	elif ribbon:
		if rules.ribbon_visual.ribbon_layered_enabled or rules.ribbon_visual.ribbon_orbit_enabled:
			if rules.ribbon_visual.ribbon_orbit_enabled:
				if not _orbit_material:
					_orbit_material = EFFECT_LAYER.material(preload("res://shaders/combat/player_sword_orbit.gdshader"))
				_material = _orbit_material
				EFFECT_LAYER.set_parameter(_material, "secondary_strength", rules.ribbon_visual.ribbon_orbit_secondary_strength)
				EFFECT_LAYER.set_parameter(_material, "secondary_offset", deg_to_rad(rules.ribbon_visual.ribbon_orbit_secondary_offset))
			else:
				if not _flow_material:
					_flow_material = EFFECT_LAYER.material(preload("res://shaders/combat/player_sword_flow_slash.gdshader"))
				_material = _flow_material
				for property in ["hilt_enabled", "hilt_offset", "hilt_width_ratio"]:
					EFFECT_LAYER.set_parameter(_material, property, rules.ribbon_visual.get("ribbon_" + property))
			EFFECT_LAYER.set_parameter(_material, "stroke_texture", rules.ribbon_visual.ribbon_brush)
			EFFECT_LAYER.set_parameter(_material, "flow_noise", rules.ribbon_visual.ribbon_noise)
			EFFECT_LAYER.set_parameter(_material, "visual_age", age)
			EFFECT_LAYER.set_parameter(_material, "sweep_seconds", rules.sweep_seconds)
			EFFECT_LAYER.set_parameter(_material, "attack_angle", deg_to_rad(angle))
			for property in ["flow_speed", "distortion", "wake_strength", "spark_strength"]:
				EFFECT_LAYER.set_parameter(_material, property, rules.ribbon_visual.get("ribbon_" + property))
		else:
			if not _ribbon_material:
				_ribbon_material = EFFECT_LAYER.material(preload("res://shaders/combat/player_sword_ribbon.gdshader"))
			_material = _ribbon_material
		stretch = rules.ribbon_visual.profile(progress, fade_progress)
		var style := rules.ribbon_visual
		for property in ["inner_ratio", "pixel_size", "blade_color", "middle_color", "tail_color", "blade_enabled", "trail_enabled"]:
			EFFECT_LAYER.set_parameter(_material, property, style.get("ribbon_" + property))
		EFFECT_LAYER.set_parameter(_material, "release", fade_progress)
		EFFECT_LAYER.set_parameter(_material, "blade_presence", stretch.z)
	elif arc_mode:
		if not _arc_material:
			_arc_material = EFFECT_LAYER.material(preload("res://shaders/combat/player_sword_arc.gdshader"))
		_material = _arc_material
	else:
		_material = _frame_material
	if arc_mode:
		EFFECT_LAYER.set_parameter(_material, "attack_radius", radius)
		var width := rules.arc_width * clampf(pow(radius / rules.normal_range, 0.25), 1.0, 1.6)
		if meowa_arc: width *= 1.0 + 0.35 * rules.meowa_visibility_strength
		if ribbon: width = rules.ribbon_visual.ribbon_width * clampf(pow(radius / rules.normal_range, 0.25), 1.0, 1.6) * stretch.y
		EFFECT_LAYER.set_parameter(_material, "band_width", width)
		var trail_angle := deg_to_rad(rules.ribbon_visual.ribbon_degrees if ribbon else rules.arc_trail_degrees) * stretch.x
		if ribbon: trail_angle = minf(trail_angle, deg_to_rad(angle) * maxf(progress, 0.001))
		EFFECT_LAYER.set_parameter(_material, "trail_angle", trail_angle)
		if not meowa_arc and not ribbon:
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
	EFFECT_LAYER.set_parameter(_material, "opacity", rules.effect_opacity * presentation_opacity)
	EFFECT_LAYER.set_parameter(_material, "energy", rules.ribbon_visual.ribbon_emission if ribbon else rules.effect_energy)
	EFFECT_LAYER.set_parameter(_material, "leading_angle", lerpf(-deg_to_rad(angle * 0.5), deg_to_rad(angle * 0.5), progress))
	if not meowa_arc and not ribbon: EFFECT_LAYER.set_parameter(_material, "fade", 1.0 - fade_progress)
	global_position = origin
	global_basis = Basis(Vector3.UP, atan2(-heading.x, -heading.z))
	var camera := get_viewport().get_camera_3d()
	var view := camera.global_basis.z if camera else Vector3.BACK
	view.y = 0.0
	view = global_basis.inverse() * view.normalized()
	var toward := Vector2(view.x, view.z)
	var sideways := Vector2(-toward.y, toward.x)
	# 朝镜头抬起，避免浅俯视下某些出剑方向变成一条线；左右刀附加小幅斜切。
	var tilt := rules.ribbon_visual.ribbon_view_tilt if ribbon and (rules.ribbon_visual.ribbon_layered_enabled or rules.ribbon_visual.ribbon_orbit_enabled) else rules.effect_tilt_degrees
	var slope := -toward * tan(deg_to_rad(tilt))
	slope += sideways * tan(deg_to_rad(tilt * 0.35)) * (-1.0 if reverse else 1.0)
	slope = slope.limit_length(maxf(0.0, effect_height - 0.08) / radius)
	EFFECT_LAYER.set_parameter(_material, "plane_slope", slope)
	var layout := Vector3(art_radius, canvas.x, canvas.y)
	if layout != _layout:
		_layout = layout
		_flat_meshes.clear()
	var flat: bool = surface.unclipped_flat(origin, radius)
	# 普攻腰前高度与弹射原高度各自复用，切换模式不清空另一套平地网格。
	var key := Vector4(radius, angle, -1.0 if reverse else 1.0, effect_height)
	if flat and _flat_meshes.has(key): mesh = _flat_meshes[key]
	else:
		var vertices := PackedVector3Array()
		var uvs := PackedVector2Array()
		var flat_ground: bool = flat or surface.flat_ground(origin, radius)
		var half := deg_to_rad(angle * 0.5)
		# 仅复用局部角度模板，不缓存当前墙体命中或地面裁切结果。
		if _radial_angle != angle:
			_radial_angle = angle
			var steps := maxi(ANGLES, ceili(angle / 180.0 * ANGLES))
			if steps != _angular_steps:
				_build_indices(steps)
				_clipped = null
			_radials.clear()
			for angular in _angular_steps + 1:
				var theta := lerpf(-half, half, float(angular) / _angular_steps)
				_radials.append(Vector3(sin(theta), 0.0, -cos(theta)))
		var space := get_world_3d().direct_space_state if not flat else null
		if not flat:
			_wall_ray.from = origin + Vector3.UP * 0.45
			_wall_ray.exclude = excluded
		for radial in _radials:
			var direction := global_basis * radial
			var limit := radius
			if not flat:
				if not flat_ground: limit = _collision.ground_limit(path, origin, direction, limit, origin.y, rules.height_tolerance)
				_wall_ray.to = origin + Vector3.UP * 0.45 + direction * limit
				var hit := space.intersect_ray(_wall_ray)
				if not hit.is_empty(): limit = maxf(0.0, origin.distance_to(hit.position - Vector3.UP * 0.45) - 0.02)
			for ring in RINGS + 1:
				var distance := limit * float(ring) / RINGS
				var point := radial * distance
				point.y = effect_height if flat_ground else path.ground_position(origin + global_basis * point).y - origin.y + effect_height
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
