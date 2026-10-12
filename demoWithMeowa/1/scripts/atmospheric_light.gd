@tool
extends Node3D

const FOG_SHADER := preload("res://shaders/atmospheric_shafts.gdshader")
const BEAM_SHADER := preload("res://shaders/atmospheric_beam.gdshader")
const BEAM_LAYER := 1 << 17
const SHAFT_LAYER := 1 << 15

@export_group("远景空气光")
@export var art_direction: ArtDirection:
	set(value): art_direction = value; _queue_apply()
## 总开关；远景空气光与柔和地表补光共同关闭。
@export var enabled := true:
	set(value): enabled = value; _queue_apply()
@export var distant_enabled := true:
	set(value): distant_enabled = value; _queue_apply()
@export var light_color := Color(1.0, 0.83, 0.55):
	set(value): light_color = value; _queue_apply()
## 只照亮可玩区域以外的空气，地表补光不参与体积散射。
@export_range(0.0, 40.0, 0.5) var scattering := 12.0:
	set(value): scattering = value; _queue_apply()
## 远处雾体密度；可玩区域及其周围安全距离内始终为零。
@export_range(0.0, 0.05, 0.001) var haze_density := 0.014:
	set(value): haze_density = value; _queue_apply()
@export_range(1.0, 6.0, 0.1) var upper_air_gain := 1.8:
	set(value): upper_air_gain = value; _queue_apply()
## 远处薄雾中的柔和辉光；不改变全局泛光或曝光。
@export_range(0.0, 1.0, 0.05) var halo_strength := 0.3:
	set(value): halo_strength = value; _queue_apply()
@export_range(0.0, 1.0, 0.05) var background_scattering := 1.0:
	set(value): background_scattering = value; _queue_apply()
## 距地图北侧边缘的距离；自动保留最小安全距离，防止光束范围触碰地图。
@export_range(16.0, 50.0, 1.0, "suffix:m") var distant_distance := 28.0:
	set(value): distant_distance = value; _queue_apply()
@export_range(10.0, 36.0, 1.0, "suffix:m") var distant_height := 22.0:
	set(value): distant_height = value; _queue_apply()
@export_range(2.0, 12.0, 0.5, "suffix:m") var distant_width := 7.0:
	set(value): distant_width = value; _queue_apply()
## 仅增强地图外的远景光束形态；0 只显示远景体积散射。
@export_range(0.0, 0.3, 0.005) var beam_definition := 0.07:
	set(value): beam_definition = value; _queue_apply()
## 远景体积散射所需的渲染距离；关闭远景后恢复美术总控的原值。
@export_range(50.0, 120.0, 5.0, "suffix:m") var distant_fog_length := 80.0:
	set(value): distant_fog_length = value; _queue_apply()
@export_range(0.0, 1.0, 0.05) var texture_strength := 0.3:
	set(value): texture_strength = value; _queue_apply()
@export var moving := true

@export_group("地图局部点缀")
## 在整张地图分布固定的局部光斑，按人物位置平滑启用附近光斑；保留亮区之间的暗部。
@export var map_accents_enabled := false:
	set(value): map_accents_enabled = value; _queue_apply()
## 局部光与 ArtDirection 全局光保持同一世界方向；QE 不改变方向或光斑位置。
@export var follow_global_direction := true:
	set(value): follow_global_direction = value; _queue_apply()
## 同时参与渲染的局部光数量上限；提高会增加原生光照与阴影开销。
@export_range(1, 8, 1) var max_active_accents := 6:
	set(value): max_active_accents = value; _queue_apply()
## 人物周围的点缀范围，边缘 6 米平滑减弱。
@export_range(10.0, 28.0, 0.5, "suffix:m") var accent_radius := 18.0:
	set(value): accent_radius = value; _queue_apply()
## 进入 / 离开范围时的淡入淡出时间，避免行走时突然换光。
@export_range(0.2, 3.0, 0.1, "suffix:s") var accent_fade_time := 0.8

@export_group("方向与地表补光")
## 世界方位，不跟随 QE 镜头旋转。
@export_range(-180.0, 180.0, 1.0, "degrees") var azimuth := -24.0:
	set(value): azimuth = value; _queue_apply()
@export_range(15.0, 70.0, 1.0, "degrees") var elevation := 38.0:
	set(value): elevation = value; _queue_apply()
@export_range(6.0, 20.0, 0.5, "suffix:m") var source_height := 12.0:
	set(value): source_height = value; _queue_apply()
@export_range(0.5, 6.0, 0.1, "suffix:m") var beam_width := 4.2:
	set(value): beam_width = value; _queue_apply()
@export_range(1.0, 18.0, 0.5, "suffix:m") var spacing := 11.0:
	set(value): spacing = value; _queue_apply()
## 仅实际受光与阴影，永远不生成场景内的空气光束。0 关闭补光。
@export_range(0.0, 5.0, 0.05) var surface_energy := 2.2:
	set(value): surface_energy = value; _queue_apply()
@export_range(0.0, 1.0, 0.05) var breakup_strength := 0.7:
	set(value): breakup_strength = value; _queue_apply()
@export var shadows_enabled := true:
	set(value): shadows_enabled = value; _queue_apply()
## 原生光源尺寸，控制地表阴影的柔和程度；0 恢复硬影。
@export_range(0.0, 0.6, 0.01, "suffix:m") var shadow_softness := 0.25:
	set(value): shadow_softness = value; _queue_apply()

var _rays: Array[SpotLight3D] = []
var _distant_rays: Array[SpotLight3D] = []
var _beams: Array[MeshInstance3D] = []
var _beam_material: ShaderMaterial
var _beam_mesh: CylinderMesh
var _fog: FogVolume
var _material: ShaderMaterial
var _projector: ImageTexture
var _projector_strength := -1.0
var _apply_queued := false
var _clock := 0.0
var _accent_targets := PackedVector3Array()
var _accent_slots := PackedInt32Array()
var _accent_weights := PackedFloat32Array()
var _surface_direction := Vector3.DOWN
var _bound_data: TerrainData

func _ready() -> void:
	process_priority = 40
	set_notify_transform(true)
	_apply()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_queue_apply()

func _queue_apply() -> void:
	if _apply_queued or not is_inside_tree():
		return
	_apply_queued = true
	_apply.call_deferred()

func _apply() -> void:
	_apply_queued = false
	if art_direction:
		art_direction.apply()
	else:
		apply_atmosphere()

func _process(delta: float) -> void:
	if not is_instance_valid(_fog) or _distant_rays.size() != 3:
		_apply()
	if not _material:
		return
	if enabled and moving and not Engine.is_editor_hint():
		_clock += delta
	_material.set_shader_parameter("haze_clock", _clock)
	if map_accents_enabled:
		if follow_global_direction and art_direction and art_direction.moon:
			_surface_direction = -art_direction.moon.global_basis.z.normalized()
		_update_map_accents(delta)

func _build_accent_targets() -> void:
	var data: TerrainData = art_direction.terrain.data if art_direction and art_direction.terrain else null
	if data != _bound_data:
		if _bound_data and _bound_data.changed.is_connected(_queue_apply):
			_bound_data.changed.disconnect(_queue_apply)
		_bound_data = data
		if data and not data.changed.is_connected(_queue_apply):
			data.changed.connect(_queue_apply)
	var rect := art_direction.get_map_rect() if art_direction else Rect2(-12.0, -10.4, 48.0, 20.8)
	var targets := PackedVector3Array()
	var gap := maxf(spacing, 4.0)
	var anchor := Vector2(global_position.x, global_position.z)
	var first := Vector2i(floor((rect.position - anchor) / gap))
	var last := Vector2i(ceil((rect.end - anchor) / gap))
	var noise := FastNoiseLite.new()
	noise.seed = 527811
	noise.frequency = 0.7
	for z in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			# Keep the original courtyard row; lightly offset other rows to avoid a visible grid.
			var jitter := Vector2(noise.get_noise_2d(x, z), noise.get_noise_2d(x + 73, z - 51)) * gap * 0.3 if z != 0 else Vector2.ZERO
			var point := anchor + Vector2(x, z) * gap + jitter
			if not rect.grow(-0.5).has_point(point):
				continue
			var y := global_position.y
			if data:
				var terrain := art_direction.terrain
				var cell := data.world_to_cell(Vector3(point.x, 0.0, point.y) - terrain.global_position)
				y = terrain.global_position.y + data.get_level(cell) * data.layer_height
			targets.append(Vector3(point.x, y, point.y))
	if targets != _accent_targets or _accent_slots.size() != _rays.size():
		_accent_targets = targets
		_accent_slots.resize(_rays.size())
		_accent_slots.fill(-1)
		_accent_weights.resize(_rays.size())
		_accent_weights.fill(0.0)

func _update_map_accents(delta: float) -> void:
	if _accent_slots.size() != _rays.size():
		return
	var focus := global_position
	if art_direction and art_direction.scene_root:
		var player := art_direction.scene_root.get_node_or_null("Player") as Node3D
		if player:
			focus = player.global_position
	var nearest: Array[int] = []
	for i in _accent_targets.size():
		if _accent_distance(i, focus) < accent_radius:
			nearest.append(i)
	nearest.sort_custom(func(a: int, b: int): return _accent_distance(a, focus) < _accent_distance(b, focus))
	nearest.resize(mini(nearest.size(), _rays.size()))
	var fade := delta / maxf(accent_fade_time, 0.2)
	for i in _rays.size():
		var index := _accent_slots[i]
		var weight := 0.0
		if enabled and index in nearest:
			weight = 1.0 - smoothstep(accent_radius - 6.0, accent_radius, _accent_distance(index, focus))
		_accent_weights[i] = move_toward(_accent_weights[i], weight, fade)
		if _accent_weights[i] <= 0.001 and index not in nearest:
			_accent_slots[i] = -1
			for candidate in nearest:
				if candidate not in _accent_slots:
					_accent_slots[i] = candidate
					break
		index = _accent_slots[i]
		var ray := _rays[i]
		ray.visible = enabled and surface_energy > 0.0 and index >= 0 and _accent_weights[i] > 0.001
		ray.light_energy = surface_energy * _accent_weights[i]
		if index >= 0:
			_place_surface(ray, _accent_targets[index], _surface_direction)

func _accent_distance(index: int, focus: Vector3) -> float:
	var offset := _accent_targets[index] - focus
	return Vector2(offset.x, offset.z).length()

func _place_surface(surface: SpotLight3D, target: Vector3, direction: Vector3) -> void:
	var length := source_height / maxf(-direction.y, 0.1)
	var origin := target - direction * length
	# Selection/fades update every frame; fixed lights need no repeated transform/shadow invalidation.
	if not surface.global_position.is_equal_approx(origin):
		surface.global_position = origin
	if not (-surface.global_basis.z).is_equal_approx(direction):
		surface.look_at(target, Vector3.UP if absf(direction.y) < 0.99 else Vector3.FORWARD)
	var angle := rad_to_deg(atan2(beam_width * 1.25, length))
	if not is_equal_approx(surface.spot_range, length + 6.0):
		surface.spot_range = length + 6.0
	if not is_equal_approx(surface.spot_angle, angle):
		surface.spot_angle = angle

func _configure_surface(surface: SpotLight3D) -> void:
	surface.light_color = light_color
	surface.spot_angle_attenuation = 1.5
	surface.spot_attenuation = 0.0
	surface.shadow_enabled = shadows_enabled
	surface.shadow_bias = 0.03
	surface.shadow_normal_bias = 0.3
	surface.light_size = shadow_softness
	surface.light_projector = _projector if breakup_strength > 0.0 else null
	surface.light_cull_mask = 0xFFFFFFFF & ~(BEAM_LAYER | SHAFT_LAYER)
	surface.light_volumetric_fog_energy = 0.0

func _ensure_rays() -> void:
	var count := max_active_accents if map_accents_enabled else 3
	if is_instance_valid(_fog) and _fog.name == "DistantAir" and _rays.size() == count and _distant_rays.size() == 3 and _beams.size() == 3:
		return
	# Open editor instances can retain the old scene-local helpers after reload.
	for child in get_children():
		if child.owner == null and (child.name.begins_with("Shaft") or child.name.begins_with("Distant") or child.name.begins_with("Surface")):
			remove_child(child)
			child.queue_free()
	_rays.clear()
	_distant_rays.clear()
	_beams.clear()
	_projector_strength = -1.0
	_material = ShaderMaterial.new()
	_material.shader = FOG_SHADER
	_fog = FogVolume.new()
	_fog.name = "DistantAir"
	_fog.material = _material
	add_child(_fog)
	_beam_material = ShaderMaterial.new()
	_beam_material.shader = BEAM_SHADER
	_beam_mesh = CylinderMesh.new()
	_beam_mesh.radial_segments = 48
	_beam_mesh.rings = 8
	_beam_mesh.cap_top = false
	_beam_mesh.cap_bottom = false
	for i in count:
		var surface := SpotLight3D.new()
		surface.name = "Surface%d" % i
		surface.light_indirect_energy = 0.0
		surface.shadow_caster_mask = 1
		surface.add_to_group("shadow_lights")
		add_child(surface)
		_rays.append(surface)
	for i in 3:
		var distant := SpotLight3D.new()
		distant.name = "Distant%d" % i
		distant.light_indirect_energy = 0.0
		distant.light_cull_mask = SHAFT_LAYER
		distant.shadow_enabled = false
		add_child(distant)
		_distant_rays.append(distant)
		var beam := MeshInstance3D.new()
		beam.name = "DistantShape%d" % i
		beam.mesh = _beam_mesh
		beam.material_override = _beam_material
		beam.layers = SHAFT_LAYER
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beam.add_to_group("atmospheric_beams")
		add_child(beam)
		_beams.append(beam)

func _update_projector() -> void:
	if is_equal_approx(_projector_strength, breakup_strength):
		return
	_projector_strength = breakup_strength
	var noise := FastNoiseLite.new()
	noise.seed = 527811
	noise.frequency = 1.3
	noise.fractal_octaves = 3
	var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var uv := Vector2(x + 0.5, y + 0.5) / 128.0
			var bands := maxf(exp(-pow((uv.x - 0.28) / 0.17, 2.0)),
				maxf(0.78 * exp(-pow((uv.x - 0.52) / 0.1, 2.0)), 0.9 * exp(-pow((uv.x - 0.73) / 0.18, 2.0))))
			var mottling := smoothstep(-0.3, 0.35, noise.get_noise_2d(uv.x * 5.0, uv.y * 5.0))
			var value := lerpf(1.0, (0.12 + bands * 0.88) * lerpf(0.18, 1.0, mottling), breakup_strength)
			image.set_pixel(x, y, Color(value, value, value, 1.0))
	if _projector:
		_projector.update(image)
	else:
		_projector = ImageTexture.create_from_image(image)
	_material.set_shader_parameter("shaft_mask", _projector)

func apply_atmosphere() -> void:
	if not is_inside_tree():
		return
	# Preserve valid zero/false values after editor tool reload.
	var script: Script = get_script()
	for property in script.get_script_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_EDITOR:
			var default_value: Variant = script.get_property_default_value(property.name)
			if get(property.name) == null and default_value != null:
				set(property.name, default_value)
	_ensure_rays()
	_update_projector()
	_build_accent_targets()
	var root := art_direction.scene_root if art_direction and art_direction.scene_root else get_parent()
	for other: Light3D in root.find_children("*", "Light3D", true, false):
		if other.get_parent() != self:
			other.light_cull_mask &= ~SHAFT_LAYER
	var active := enabled and distant_enabled and (not art_direction or art_direction.volumetric_fog)
	if art_direction and art_direction.world_environment and active:
		var env := art_direction.world_environment.environment
		env.volumetric_fog_sky_affect = background_scattering
		env.volumetric_fog_length = maxf(art_direction.volumetric_length, distant_fog_length)
	var rect := art_direction.get_map_rect() if art_direction else Rect2(-12.0, -10.4, 48.0, 20.8)
	var exclusion := rect.grow(8.0)
	var az := deg_to_rad(azimuth)
	var el := deg_to_rad(elevation)
	var direction := Vector3(sin(az) * cos(el), -sin(el), cos(az) * cos(el))
	_surface_direction = -art_direction.moon.global_basis.z.normalized() if map_accents_enabled and follow_global_direction and art_direction and art_direction.moon else direction
	for surface in _rays:
		_configure_surface(surface)
	var right := direction.cross(Vector3.UP).normalized()
	var up := right.cross(direction).normalized()
	var far_length := distant_height / maxf(sin(el), 0.1)
	# The entire distant light sphere stays beyond the map, even at maximum width.
	var gap := maxf(distant_distance, (1.0 - direction.z) * far_length + 10.0)
	_beam_mesh.height = far_length
	_beam_mesh.top_radius = 0.08
	_beam_mesh.bottom_radius = distant_width * 0.8
	_beam_material.set_shader_parameter("height", far_length)
	_beam_material.set_shader_parameter("beam_width", distant_width)
	_beam_material.set_shader_parameter("gain", beam_definition)
	_beam_material.set_shader_parameter("shaft_mask", _projector)
	_beam_material.set_shader_parameter("ray_right", right)
	_beam_material.set_shader_parameter("ray_up", up)
	var origins := PackedVector3Array()
	var directions := PackedVector3Array()
	var bounds := AABB()
	for i in 3:
		var target := global_position + Vector3.RIGHT * (i - 1) * spacing
		if not map_accents_enabled:
			var surface := _rays[i]
			_place_surface(surface, target, direction)
			surface.visible = enabled and surface_energy > 0.0
			surface.light_energy = surface_energy
		var far_target := Vector3(target.x, global_position.y, rect.position.y - gap)
		var far_origin := far_target - direction * far_length
		origins.append(far_origin)
		directions.append(direction)
		bounds = AABB(far_origin, Vector3.ZERO) if i == 0 else bounds.expand(far_origin)
		bounds = bounds.expand(far_target)
		var distant := _distant_rays[i]
		distant.global_position = far_origin
		distant.look_at(far_target, Vector3.UP)
		distant.light_color = light_color
		distant.spot_range = far_length
		distant.spot_angle = rad_to_deg(atan2(distant_width * 1.25, far_length))
		distant.spot_angle_attenuation = 0.6
		distant.spot_attenuation = 0.0
		distant.light_energy = 1.0
		distant.light_volumetric_fog_energy = scattering if active else 0.0
		distant.visible = active and (scattering > 0.0 or beam_definition > 0.0)
		var beam := _beams[i]
		beam.global_transform = Transform3D(Basis(right, -direction, -up), (far_origin + far_target) * 0.5)
		beam.set_instance_shader_parameter("ray_origin", far_origin)
		beam.visible = active and beam_definition > 0.0
	_fog.visible = active and haze_density > 0.0
	_fog.global_position = bounds.get_center()
	_fog.size = bounds.size + Vector3.ONE * distant_width * 4.0
	_material.set_shader_parameter("origins", origins)
	_material.set_shader_parameter("directions", directions)
	_material.set_shader_parameter("ray_right", right)
	_material.set_shader_parameter("ray_up", up)
	_material.set_shader_parameter("ray_length", far_length)
	_material.set_shader_parameter("beam_width", distant_width)
	_material.set_shader_parameter("density", haze_density)
	_material.set_shader_parameter("upper_air_gain", upper_air_gain)
	_material.set_shader_parameter("texture_strength", texture_strength)
	_material.set_shader_parameter("halo_strength", halo_strength)
	_material.set_shader_parameter("glow_color", light_color)
	_material.set_shader_parameter("exclusion_bounds", Vector4(exclusion.position.x, exclusion.position.y, exclusion.end.x, exclusion.end.y))
	if map_accents_enabled:
		_update_map_accents(0.0)
