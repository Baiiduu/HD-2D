@tool
class_name GroundSlashEffect
extends MeshInstance3D

const EFFECT_LAYER := preload("res://scripts/rendering/combat_effect_layer.gd")
const OBSTACLE_BATCH := preload("res://scripts/combat/preview_obstacle_batch.gd")

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
var _flat_meshes: Dictionary[Array, ArrayMesh] = {}
var _clipped: ArrayMesh
var _clipped_limits := PackedFloat64Array()
var _clipped_layout: Array = []
var _collision := ProjectileCollision.new()
var _layout := Vector3(-1, -1, -1)
var _radials := PackedVector3Array()
var _radial_angle := NAN
var _angular_steps := ANGLES
var _first_ring := 0
var _wall_ray := PhysicsRayQueryParameters3D.create(Vector3.ZERO, Vector3.ZERO, 1)
## 本次显示的实际射线与同步障碍证明省略数，不跨调用保存障碍结果。
var wall_rays := 0
var wall_rays_skipped := 0
var _parameter_material: ShaderMaterial
var _parameters: Dictionary = {}

func _parameter(name: StringName, value: Variant) -> void:
	if _parameter_material != _material:
		_parameter_material = _material
		_parameters.clear()
	# 仅记录本节点自己提交的值；动态动画参数和资源热调仍按精确值更新。
	if _parameters.has(name) and _parameters[name] == value: return
	_parameters[name] = value
	EFFECT_LAYER.set_parameter(_parameter_material, name, value)

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
	_collision.center_certificate_enabled = true
	_material = EFFECT_LAYER.material(preload("res://shaders/combat/player_sword.gdshader"))
	_frame_material = _material
	material_override = _material
	_build_indices(ANGLES)
	hide()

func _build_indices(steps: int, first_ring := 0) -> void:
	_angular_steps = steps
	_first_ring = first_ring
	_indices.clear()
	var stride := RINGS - first_ring + 1
	for angular in steps:
		for ring in range(first_ring, RINGS):
			var a := angular * stride + ring - first_ring
			var b := a + stride
			_indices.append_array(PackedInt32Array([a, b, b + 1, a, b + 1, a + 1]))

func display(origin: Vector3, heading: Vector3, radius: float, angle: float, reverse: bool,
		frames: SpriteFrames, age: float, rules: PlayerSwordRules, path: TerrainPath,
		surface: RefCounted, excluded: Array[RID], presentation_opacity := 1.0) -> void:
	wall_rays = 0
	wall_rays_skipped = 0
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
		_parameter("body_opacity", rules.meowa_body_opacity * stretch.z)
		_parameter("tail_width_scale", stretch.y)
		_parameter("visibility_strength", rules.meowa_visibility_strength)
		_parameter("tail_spread", rules.meowa_tail_spread)
		_parameter("tail_inner_ratio", rules.meowa_tail_inner_ratio)
	elif ribbon:
		if rules.ribbon_visual.ribbon_layered_enabled or rules.ribbon_visual.ribbon_orbit_enabled:
			if rules.ribbon_visual.ribbon_orbit_enabled:
				if not _orbit_material:
					_orbit_material = EFFECT_LAYER.material(preload("res://shaders/combat/player_sword_orbit.gdshader"))
				_material = _orbit_material
				_parameter("secondary_strength", rules.ribbon_visual.ribbon_orbit_secondary_strength)
				_parameter("secondary_offset", deg_to_rad(rules.ribbon_visual.ribbon_orbit_secondary_offset))
			else:
				if not _flow_material:
					_flow_material = EFFECT_LAYER.material(preload("res://shaders/combat/player_sword_flow_slash.gdshader"))
				_material = _flow_material
				for property in ["hilt_enabled", "hilt_offset", "hilt_width_ratio"]:
					_parameter(property, rules.ribbon_visual.get("ribbon_" + property))
			_parameter("stroke_texture", rules.ribbon_visual.ribbon_brush)
			_parameter("flow_noise", rules.ribbon_visual.ribbon_noise)
			_parameter("visual_age", age)
			_parameter("sweep_seconds", rules.sweep_seconds)
			_parameter("attack_angle", deg_to_rad(angle))
			for property in ["flow_speed", "distortion", "wake_strength", "spark_strength"]:
				_parameter(property, rules.ribbon_visual.get("ribbon_" + property))
		else:
			if not _ribbon_material:
				_ribbon_material = EFFECT_LAYER.material(preload("res://shaders/combat/player_sword_ribbon.gdshader"))
			_material = _ribbon_material
		stretch = rules.ribbon_visual.profile(progress, fade_progress)
		var style := rules.ribbon_visual
		for property in ["inner_ratio", "pixel_size", "blade_color", "middle_color", "tail_color", "blade_enabled", "trail_enabled"]:
			_parameter(property, style.get("ribbon_" + property))
		_parameter("release", fade_progress)
		_parameter("blade_presence", stretch.z)
	elif arc_mode:
		if not _arc_material:
			_arc_material = EFFECT_LAYER.material(preload("res://shaders/combat/player_sword_arc.gdshader"))
		_material = _arc_material
	else:
		_material = _frame_material
	if arc_mode:
		_parameter("attack_radius", radius)
		var width := rules.arc_width * clampf(pow(radius / rules.normal_range, 0.25), 1.0, 1.6)
		if meowa_arc: width *= 1.0 + 0.35 * rules.meowa_visibility_strength
		if ribbon: width = rules.ribbon_visual.ribbon_width * clampf(pow(radius / rules.normal_range, 0.25), 1.0, 1.6) * stretch.y
		_parameter("band_width", width)
		var trail_angle := deg_to_rad(rules.ribbon_visual.ribbon_degrees if ribbon else rules.arc_trail_degrees) * stretch.x
		if ribbon: trail_angle = minf(trail_angle, deg_to_rad(angle) * maxf(progress, 0.001))
		_parameter("trail_angle", trail_angle)
		if not meowa_arc and not ribbon:
			_parameter("pixel_size", rules.arc_pixel_size)
			_parameter("blade_color", rules.arc_blade_color)
			_parameter("tail_color", rules.arc_tail_color)
	if uses_frames:
		var native_canvas := _bind_frame(frames, progress, fade_progress)
		if meowa_arc:
			_parameter("art_scale", Vector2.ONE * rules.art_radius_pixels / native_canvas)
		else:
			_parameter("half_angle", deg_to_rad(angle * 0.5))
			canvas = native_canvas
			art_radius = rules.art_radius_pixels
			_parameter("art_scale", canvas / art_radius)
	if material_override != _material: material_override = _material
	_parameter("opacity", rules.effect_opacity * presentation_opacity)
	_parameter("energy", rules.ribbon_visual.ribbon_emission if ribbon else rules.effect_energy)
	_parameter("leading_angle", lerpf(-deg_to_rad(angle * 0.5), deg_to_rad(angle * 0.5), progress))
	if not meowa_arc and not ribbon: _parameter("fade", 1.0 - fade_progress)
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
	_parameter("plane_slope", slope)
	var layout := Vector3(art_radius, canvas.x, canvas.y)
	if layout != _layout:
		_layout = layout
		_flat_meshes.clear()
	var first_ring := 0
	if ribbon and rules.ribbon_visual.ribbon_orbit_enabled:
		# 整个三角形均在透明内圈才剔除，保留所有可见三角形及其原始插值。
		# 按完整半径选择固定环数；贴墙缩短半径只会使剔除区域更小。
		first_ring = clampi(floori(rules.ribbon_visual.ribbon_inner_ratio * RINGS - 0.0001), 0, RINGS - 1)
	var steps := maxi(ANGLES, ceili(angle / 180.0 * ANGLES))
	if steps != _angular_steps or first_ring != _first_ring:
		_build_indices(steps, first_ring)
		_clipped = null
	var flat: bool = surface.unclipped_flat(origin, radius)
	# 普攻腰前高度与弹射原高度各自复用，切换模式不清空另一套平地网格。
	var key: Array = [Vector4(radius, angle, -1.0 if reverse else 1.0, effect_height), first_ring]
	if flat and _flat_meshes.has(key): mesh = _flat_meshes[key]
	else:
		var vertices := PackedVector3Array()
		var uvs := PackedVector2Array()
		var flat_ground: bool = flat or surface.flat_ground(origin, radius)
		var half := deg_to_rad(angle * 0.5)
		# 仅复用局部角度模板，不缓存当前墙体命中或地面裁切结果。
		if _radial_angle != angle:
			_radial_angle = angle
			_radials.clear()
			for angular in _angular_steps + 1:
				var theta := lerpf(-half, half, float(angular) / _angular_steps)
				_radials.append(Vector3(sin(theta), 0.0, -cos(theta)))
		var space := get_world_3d().direct_space_state if not flat else null
		if not flat:
			_wall_ray.from = origin + Vector3.UP * 0.45
			_wall_ray.exclude = excluded
		var obstacles: RefCounted
		var ray_candidates := PackedByteArray()
		if (not flat and path and is_instance_valid(path.terrain) and path.terrain.get_world_3d() == get_world_3d()
				and _wall_ray.collide_with_bodies and not _wall_ray.collide_with_areas
				and (_wall_ray.collision_mask & ~ProjectileCollision.REFLECTION_MASK) == 0
				and not ProjectSettings.get_setting("physics/3d/run_on_separate_thread", false)):
			obstacles = OBSTACLE_BATCH.new(path.terrain, excluded)
			obstacles.cover(PackedVector3Array([
				_wall_ray.from + Vector3(-radius, 0, -radius), _wall_ray.from + Vector3(radius, 0, -radius),
				_wall_ray.from + Vector3(radius, 0, radius), _wall_ray.from + Vector3(-radius, 0, radius)]))
			ray_candidates = obstacles.fan_candidates(_wall_ray.from, global_basis, radius, deg_to_rad(angle), _angular_steps)
		var limits := PackedFloat64Array()
		limits.resize(_radials.size())
		var ground_minimum := origin
		var ground_maximum := origin
		for angular in _radials.size():
			var radial := _radials[angular]
			var direction := global_basis * radial
			var limit := radius
			if not flat:
				if not flat_ground: limit = _collision.ground_limit(path, origin, direction, limit, origin.y, rules.height_tolerance)
				_wall_ray.to = origin + Vector3.UP * 0.45 + direction * limit
				if not ray_candidates.is_empty() and ray_candidates[angular] == 0:
					wall_rays_skipped += 1
				else:
					wall_rays += 1
					var hit := space.intersect_ray(_wall_ray)
					if not hit.is_empty(): limit = maxf(0.0, origin.distance_to(hit.position - Vector3.UP * 0.45) - 0.02)
			limits[angular] = limit
			if not flat_ground:
				var endpoint := origin + global_basis * (radial * limit)
				ground_minimum = ground_minimum.min(endpoint)
				ground_maximum = ground_maximum.max(endpoint)
		if not flat_ground:
			# 边缘的整圆资格可能覆盖地图外；只证明实时裁切后的实际顶点范围。
			# 微小外扩覆盖浮点运算的舍入差异，水面／断层／自定义投影仍回退逐点采样。
			var padding := Vector3(0.0001, 0.0, 0.0001)
			var height := path.flat_center_ground_height(ground_minimum - padding, ground_maximum + padding)
			flat_ground = not is_nan(height) and Vector3(0.0, height, 0.0).y == origin.y
		var clipped_layout: Array = [key, _layout]
		# 墙体和地面仍逐次实查；只省去结果完全相同的顶点重建及上传。
		if not flat and flat_ground and _clipped and _clipped_layout == clipped_layout and _clipped_limits == limits:
			mesh = _clipped
			show()
			return
		for angular in _radials.size():
			var radial := _radials[angular]
			var limit := limits[angular]
			for ring in range(first_ring, RINGS + 1):
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
		else:
			_clipped = result
			_clipped_limits = limits
			_clipped_layout = clipped_layout if flat_ground else []
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
		_parameter("slash_texture", texture.atlas)
		_parameter("frame_rect", Vector4(texture.region.position.x / size.x, texture.region.position.y / size.y, texture.region.size.x / size.x, texture.region.size.y / size.y))
	else:
		_parameter("slash_texture", texture)
		_parameter("frame_rect", Vector4(0, 0, 1, 1))
	var blade_angles: PackedFloat32Array = frames.get_meta(&"blade_angles", PackedFloat32Array())
	_parameter("art_angle", blade_angles[index] if index < blade_angles.size() else 0.0)
	return Vector2(texture.get_size())
