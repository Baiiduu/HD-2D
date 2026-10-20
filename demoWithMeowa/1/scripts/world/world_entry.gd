class_name WorldEntry
extends Node3D
## 菜单请求驱动的短暂入场；只借用现有相机，不改 Style、天气或战斗状态。
const REQUEST = preload("res://scripts/world/world_entry_request.gd")
const VOLUME_FOG = preload("res://shaders/effects/world_entry_volume.gdshader")
const CLOUD_NOISE = preload("res://assets/effects/world_entry/cloud_noise_atlas.png")
const WISP_SHADER = preload("res://shaders/effects/world_entry_wisp.gdshader")
const WISP_TEXTURE = preload("res://assets/meowa/effects/world_entry/cloud_bank_density.png")
const CITY_SHADER = preload("res://shaders/environment/city_background_blend.gdshader")
const ENTRY_BUILDING_SHADER = preload("res://shaders/effects/world_entry_building.gdshader")
const SOFT_FOCUS_SHADER = preload("res://shaders/effects/world_entry_soft_focus.gdshader")
const EMISSION_FOG = preload("res://scripts/world/world_entry_emission_fog.gd")
const CLOUD_DEPTH := 96.0
const PREWARM_PROGRESS := [0.0, 0.4, 0.8, 1.0]

signal finished
@export_group("场景连接")
@export var camera: FollowCamera
@export var player: Node3D
@export var terrain: Terrain
## 正式地图中的建筑间通路；留空时沿用远空环绕。
@export var flight_path: Path3D
@export var hud_layers: Array[CanvasLayer] = []
@export var settings: WorldEntrySettings
@export_group("人工预览")
## 仅供直接 F5/F6 地图时观察；主菜单入口不需要开启此项。
@export var preview_on_direct_run := false

var active := false
var fog_amount := 0.0
var _elapsed := 0.0
var _camera_was_processing := true
var _base_offset := Vector3.ZERO
var _normal_rotation := Quaternion.IDENTITY
var _right := Vector3.RIGHT
var _backward := Vector3.BACK
var _route_curve: Curve3D
var _route_transform := Transform3D.IDENTITY
var _route_focus := Vector3.ZERO
var _route_length := 0.0
var _outline_sprite: Sprite3D
var _outline_was_enabled := false
var _hud_visibility: Dictionary = {}
var _effects: Node3D
var _volume_material: ShaderMaterial
var _cover_retreat_distance := 0.0
var _fog: FogVolume
var _fog_banks: Array[FogVolume] = []
var _bank_materials: Array[ShaderMaterial] = []
var _bank_origins: Array[Vector3] = []
var _spotlight: SpotLight3D
var _original_environment: Environment
var _scene_environment: Environment
var _wisps: Array[MeshInstance3D] = []
var _wisp_origins: Array[Vector3] = []
var _wisp_bases: Array[Basis] = []
var _wisp_directions: Array[Vector3] = []
var _wisp_retreat_distances: Array[float] = []
var _wisp_material: ShaderMaterial
var _soft_focus: MeshInstance3D
var _soft_focus_material: ShaderMaterial
var _emission_fog := EMISSION_FOG.new()
var _building_surfaces: Array[Dictionary] = []
var _building_materials: Dictionary[ShaderMaterial, ShaderMaterial] = {}
var _render_wait_frames := 0
var _drop_next_delta := false
var _traversal: AudioStreamPlayer
var _audible_entry := true
var _prewarming := false
var _prewarm_index := 0

func _ready() -> void:
	set_process(false)
	set_process_input(false)
	var requested := REQUEST.consume()
	if not (requested or preview_on_direct_run) or not settings or not settings.enabled: return
	# 父场景先完成出生点与延迟 snap，再应用入场首帧，避免正常取景闪现。
	if get_parent().is_node_ready():
		play.call_deferred()
	else:
		get_parent().ready.connect(func(): play.call_deferred(), CONNECT_ONE_SHOT)

func play(audible := true) -> bool:
	if active or not is_inside_tree() or not settings or not settings.enabled: return false
	if not is_instance_valid(camera) or not is_instance_valid(player) or camera.target != player: return false
	if not camera.is_inside_tree() or not player.is_inside_tree(): return false
	_camera_was_processing = camera.is_processing()
	camera.snap_to_target()
	_base_offset = camera.global_position - camera.focus
	_right = camera.global_basis.x
	_backward = Vector3(_base_offset.x, 0.0, _base_offset.z).normalized()
	_normal_rotation = camera.global_basis.get_rotation_quaternion()
	if is_instance_valid(flight_path) and flight_path.curve and flight_path.curve.point_count >= 2:
		_route_curve = flight_path.curve.duplicate()
		_route_transform = flight_path.global_transform
		_route_focus = camera.focus
		var end := _route_transform * _route_curve.get_point_position(_route_curve.point_count - 1)
		var incoming := _route_transform.basis * -_route_curve.get_point_in(_route_curve.point_count - 1)
		var authored_forward := Vector3(incoming.x, 0.0, incoming.z)
		var actual_forward := Vector3(-camera.global_basis.z.x, 0.0, -camera.global_basis.z.z)
		var turn := Quaternion(Vector3.UP, authored_forward.signed_angle_to(actual_forward, Vector3.UP)) if not authored_forward.is_zero_approx() else Quaternion.IDENTITY
		var inverse_route := _route_transform.affine_inverse()
		# 一次性适配整段高空收尾，保留切线；不在飞行中突然推拉终点。
		for index in range(maxi(_route_curve.point_count - 3, 0), _route_curve.point_count):
			var point := _route_transform * _route_curve.get_point_position(index)
			_route_curve.set_point_position(index, inverse_route * (camera.global_position + turn * (point - end)))
			_route_curve.set_point_in(index, inverse_route.basis * (turn * (_route_transform.basis * _route_curve.get_point_in(index))))
			_route_curve.set_point_out(index, inverse_route.basis * (turn * (_route_transform.basis * _route_curve.get_point_out(index))))
		_route_length = _route_curve.get_baked_length()
		if is_zero_approx(_route_length): _route_curve = null
	camera.set_process(false)
	_elapsed = 0.0
	_audible_entry = audible
	active = true
	add_to_group(&"gameplay_input_blockers")
	_outline_sprite = player.get_node_or_null("Sprite") as Sprite3D
	if _outline_sprite and "occlusion_outline_enabled" in _outline_sprite:
		_outline_was_enabled = _outline_sprite.occlusion_outline_enabled
		_outline_sprite.occlusion_outline_enabled = false
	else:
		_outline_sprite = null
	for hud in hud_layers:
		if is_instance_valid(hud):
			_hud_visibility[hud] = hud.visible
			hud.hide()
	_create_effects()
	_apply(0.0)
	set_process(true)
	set_process_input(true)
	# 冷启动的首轮绘制／管线编译可能很长，先呈现起始云层再启动视觉时钟。
	if DisplayServer.get_name() != "headless":
		_render_wait_frames = 2
		RenderingServer.frame_post_draw.connect(_on_render_frame)
	if settings.duration_seconds <= 0.0: skip()
	return true

## 菜单背后只绘制代表性的穿雾／到位／散雾状态，不等待整段演出时长。
func prewarm() -> bool:
	if not play(false) or not active: return false
	_prewarming = true
	_prewarm_index = 0
	_render_wait_frames = 2
	set_process_input(false)
	return true

func _create_effects() -> void:
	_effects = Node3D.new()
	_effects.name = "TemporaryEntryLighting"
	add_child(_effects)
	# 相机独享临时环境，确保天空也经过雾积分；不改地图或本机画质存档。
	_original_environment = camera.environment
	var source := _original_environment if _original_environment else camera.get_world_3d().environment
	_scene_environment = source
	var entry_environment := source.duplicate() as Environment if source else Environment.new()
	entry_environment.volumetric_fog_enabled = true
	entry_environment.volumetric_fog_density = 0.0
	entry_environment.volumetric_fog_length = CLOUD_DEPTH
	entry_environment.volumetric_fog_sky_affect = 1.0
	entry_environment.volumetric_fog_ambient_inject = 0.18
	entry_environment.volumetric_fog_albedo = settings.fog_color
	entry_environment.volumetric_fog_temporal_reprojection_enabled = false
	camera.environment = entry_environment
	_prepare_buildings()
	var focus := camera.focus
	# 包住完整前向视锥，而不只包住相机位置；转向／侧倾时远景也经过厚云层。
	var cover := _cloud_cover_bounds(focus)
	_cover_retreat_distance = cover.size.length()
	_fog = _cloud_volume("MapCloudCover", cover.size)
	_fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	_fog.global_position = cover.get_center()
	_volume_material = _fog.material as ShaderMaterial
	_volume_material.set_shader_parameter("box_volume", true)
	_volume_material.set_shader_parameter("coverage_floor", 0.35)
	# 更浓的局部云团提供前后层次；体积与位置固定在世界中。
	for index in 7:
		var along := index / 6.0
		var bank := _cloud_volume("CloudBank%d" % index, Vector3(48, 32, 48) * settings.cloud_bank_scale)
		var side := -1.0 if index % 2 == 0 else 1.0
		var offset := _route_offset(along)
		var view := Basis(_flight_rotation(along, offset))
		# 云团固定在各段前侧，让镜头掠过体积边缘，避免一直埋在重叠云团中央。
		bank.global_position = focus + offset - view.z * 12.0 + view.x * side * 8.0 + view.y * ((index % 3) - 1) * 3.0
		_fog_banks.append(bank)
		_bank_materials.append(bank.material as ShaderMaterial)
		_bank_materials[-1].set_shader_parameter("noise_offset", Vector3(index * 0.17, (index % 3) * 0.27, index * 0.31))
		_bank_origins.append(bank.global_position)
	# 地图四周的雾团在散雾时真实退到外围，保留云墙的轮廓与厚度。
	for index in 8:
		var angle := TAU * index / 8.0
		var bank := _cloud_volume("MapBank%d" % index, Vector3(24, 16, 24) * settings.cloud_bank_scale)
		bank.global_position = focus + Vector3(cos(angle) * 11.0, 3.0 + index % 3, sin(angle) * 11.0)
		_fog_banks.append(bank)
		_bank_materials.append(bank.material as ShaderMaterial)
		_bank_materials[-1].set_shader_parameter("noise_offset", Vector3(index * 0.23, 0.5, index * -0.19))
		_bank_origins.append(bank.global_position)
	_create_wisps(focus)
	_create_soft_focus()
	_emission_fog.prepare(get_parent(), _effects, settings)
	_spotlight = SpotLight3D.new()
	_spotlight.name = "PlayerSpotlight"
	_spotlight.light_color = settings.spotlight_color
	_spotlight.spot_angle = settings.spotlight_angle
	_spotlight.spot_angle_attenuation = 2.0
	_spotlight.spot_attenuation = 0.2
	_spotlight.spot_range = settings.spotlight_height * 1.7
	_spotlight.light_specular = 0.35
	_spotlight.shadow_enabled = true
	_effects.add_child(_spotlight)

func _prepare_buildings() -> void:
	if not settings.building_atmosphere_enabled: return
	# 只扫描一次本地图的外围城市；每份原材质共用一份临时材质，不动网格资源。
	for node in get_tree().get_nodes_in_group(&"distant_city_geometry"):
		if not node is MeshInstance3D or not get_parent().is_ancestor_of(node) or not node.mesh or node.material_override: continue
		for surface in node.mesh.get_surface_count():
			var source := node.get_active_material(surface) as ShaderMaterial
			if not source or source.shader != CITY_SHADER: continue
			if not _building_materials.has(source):
				var material := source.duplicate() as ShaderMaterial
				material.shader = ENTRY_BUILDING_SHADER
				for uniform in source.shader.get_shader_uniform_list():
					if uniform.usage & PROPERTY_USAGE_GROUP: continue
					var value: Variant = source.get_shader_parameter(uniform.name)
					if value != null: material.set_shader_parameter(uniform.name, value)
				material.set_shader_parameter("entry_light_gain", settings.building_light_gain)
				_building_materials[source] = material
			_building_surfaces.append({"mesh": weakref(node), "surface": surface, "original": node.get_surface_override_material(surface)})
			node.set_surface_override_material(surface, _building_materials[source])

func _restore_buildings() -> void:
	for item in _building_surfaces:
		var mesh: MeshInstance3D = item.mesh.get_ref()
		if mesh: mesh.set_surface_override_material(item.surface, item.original)
	_building_surfaces.clear()
	_building_materials.clear()

func _create_soft_focus() -> void:
	if not settings.building_atmosphere_enabled or settings.building_edge_blur_strength <= 0.0: return
	_soft_focus_material = ShaderMaterial.new()
	_soft_focus_material.shader = SOFT_FOCUS_SHADER
	# 每帧只处理一次，先模糊真实画面，再照常叠加各层云片；不反复覆盖前层雾色。
	_soft_focus_material.render_priority = -127
	_soft_focus_material.set_shader_parameter("blur_radius_pixels", settings.building_edge_softness_pixels)
	_soft_focus_material.set_shader_parameter("blur_strength", settings.building_edge_blur_strength)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_soft_focus = MeshInstance3D.new()
	_soft_focus.name = "EntrySilhouetteBlur"
	_soft_focus.mesh = quad
	_soft_focus.material_override = _soft_focus_material
	_soft_focus.extra_cull_margin = 16384.0
	_soft_focus.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_soft_focus.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_effects.add_child(_soft_focus)

func _view_size(depth: float) -> Vector2:
	var viewport := get_viewport().get_visible_rect().size
	var aspect := viewport.x / maxf(viewport.y, 1.0)
	var span := 2.0 * depth * tan(deg_to_rad(camera.fov) * 0.5)
	return Vector2(span * aspect, span) if camera.keep_aspect == Camera3D.KEEP_HEIGHT else Vector2(span, span / aspect)

func _cloud_cover_bounds(focus: Vector3) -> AABB:
	var rect := terrain.get_world_rect() if is_instance_valid(terrain) else Rect2(Vector2(focus.x, focus.z) - Vector2(24, 24), Vector2(48, 48))
	var cover := AABB(Vector3(rect.position.x, focus.y - 8.0, rect.position.y), Vector3(rect.size.x, 64.0, rect.size.y))
	var half_view := _view_size(CLOUD_DEPTH) * 0.5
	for index in 65:
		var travel := index / 64.0
		var offset := _route_offset(travel)
		var basis := Basis(_flight_rotation(travel, offset))
		var position := focus + offset
		cover = cover.expand(position)
		for x in [-1.0, 1.0]:
			for y in [-1.0, 1.0]:
				cover = cover.expand(position + basis * Vector3(x * half_view.x, y * half_view.y, -CLOUD_DEPTH))
	return cover.grow(24.0)

func _route_offset(travel: float) -> Vector3:
	if _route_curve:
		var position := _route_transform * _route_curve.sample_baked(travel * _route_length, true)
		return position - _route_focus
	var turn := deg_to_rad(settings.camera_sweep_degrees) * (1.0 - travel)
	var radial := _backward.rotated(Vector3.UP, turn)
	var side := _right.rotated(Vector3.UP, turn)
	var radius := Vector2(_base_offset.x, _base_offset.z).length() + settings.sky_extra_distance * (1.0 - travel)
	var weave := settings.sky_lateral_offset * (1.0 - travel) + sin(TAU * travel) * sin(PI * travel) * 12.0
	var offset := radial * radius + side * weave
	offset.y = _base_offset.y + settings.sky_extra_height * (1.0 - travel) + pow(sin(PI * travel), 2.0) * settings.sky_extra_height * 0.35
	return offset

func _flight_rotation(travel: float, offset: Vector3) -> Quaternion:
	if travel >= 1.0: return _normal_rotation
	var bank := deg_to_rad(clampf(settings.camera_bank_degrees, 0.0, 55.0)) * sin(TAU * travel) * sin(PI * travel)
	if _route_curve:
		# 沿真实路线向前看；终段本身沿正常视线推进，不再一边盯人物一边倒退归位。
		var ahead := _route_offset(minf(travel + 0.1, 1.0))
		var behind := _route_offset(maxf(travel - 0.1, 0.0))
		var forward := (ahead - behind).normalized()
		# 抬升不跟着仰头看天，保留雾中立面；推进方向仍来自路线的水平切线。
		var horizontal := Vector3(forward.x, 0.0, forward.z).normalized()
		var pitch := lerpf(deg_to_rad(settings.sky_view_pitch), asin(clampf(Basis(_normal_rotation).z.y, -1.0, 1.0)), smoothstep(0.5, 1.0, travel))
		forward = horizontal * cos(pitch) + Vector3.DOWN * sin(pitch)
		var heading := Basis.looking_at(forward, Vector3.UP).get_rotation_quaternion()
		var settle := _ease(clampf(inverse_lerp(0.84, 1.0, travel), 0.0, 1.0))
		bank *= 1.0 - smoothstep(0.5, 0.88, travel)
		return (Basis(heading.slerp(_normal_rotation, settle)) * Basis(Vector3.BACK, bank)).get_rotation_quaternion()
	var horizontal := Vector3(offset.x, 0.0, offset.z)
	var pitch := lerpf(deg_to_rad(settings.sky_view_pitch), atan2(offset.y, horizontal.length()), _ease(clampf(travel / 0.85, 0.0, 1.0)))
	var direction := -horizontal.normalized() * cos(pitch) + Vector3.DOWN * sin(pitch)
	return (Basis.looking_at(direction, Vector3.UP) * Basis(Vector3.BACK, bank)).get_rotation_quaternion()

func _ease(value: float) -> float:
	return value * value * value * (value * (value * 6.0 - 15.0) + 10.0)

func _create_wisps(focus: Vector3) -> void:
	_wisp_material = ShaderMaterial.new()
	_wisp_material.shader = WISP_SHADER
	_wisp_material.set_shader_parameter("mist_texture", WISP_TEXTURE)
	_wisp_material.set_shader_parameter("mist_color", settings.fog_color)
	_wisp_material.set_shader_parameter("curl_strength", settings.fog_curl_strength)
	_wisp_material.set_shader_parameter("light_response", settings.mist_light_response if settings.building_atmosphere_enabled else 0.0)
	_wisp_material.set_shader_parameter("light_threshold", settings.mist_light_threshold)
	_wisp_material.set_shader_parameter("depth_bulge", settings.wisp_depth_bulge)
	var quad := QuadMesh.new()
	quad.size = Vector2(16, 16)
	quad.subdivide_width = 6
	quad.subdivide_depth = 6
	# 每组云团面向此段真实运镜方向，并按视野放大；运动切线与镜头朝向并不相同。
	for index in 9:
		var along := index / 8.0
		var offset := _route_offset(along)
		var view_basis := Basis(_flight_rotation(along, offset))
		var depth := 18.0 + (index % 2) * 6.0
		var view := _view_size(depth)
		var plane_basis := view_basis.scaled(Vector3.ONE * view.y * 2.0 / quad.size.y)
		for side in [-1.0, 1.0]:
			var point: Vector3 = focus + offset - view_basis.z * (depth + side * 1.5) + view_basis.x * side * view.x * 0.2 + view_basis.y * side * view.y * 0.08
			_add_wisp(quad, point, plane_basis, side, index)
	# 固定在世界中的近、中、远景云片，落稳后仍有可辨认的云团掠过。
	for index in 3:
		var along := 0.24 + index * 0.22
		var depth := _base_offset.length() * (1.0 - along)
		var view := _view_size(depth)
		var view_height := view.y
		var view_width := view.x
		for side in [-1.0, 1.0]:
			var point: Vector3 = focus + _base_offset * along + _right * side * view_width * 0.22 + Basis(_normal_rotation).y * view_height * (index % 2 - 0.5) * 0.12
			var basis := Basis(_normal_rotation).scaled(Vector3.ONE * view_height * 1.25 / quad.size.y)
			_add_wisp(quad, point, basis, side, index + 6, view_width * 0.72 * settings.fog_retreat_distance / 42.0)

func _add_wisp(mesh: QuadMesh, point: Vector3, basis: Basis, side: float, index: int, retreat_distance := -1.0) -> void:
	var wisp := MeshInstance3D.new()
	wisp.name = "NearCloud%d_%s" % [index, "Left" if side < 0.0 else "Right"]
	wisp.mesh = mesh
	wisp.material_override = _wisp_material
	wisp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wisp.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_effects.add_child(wisp)
	wisp.global_transform = Transform3D(basis, point)
	wisp.set_instance_shader_parameter("flip", Vector2(side, -1.0 if index % 2 else 1.0))
	wisp.set_instance_shader_parameter("phase", index * 0.71 + side)
	_wisps.append(wisp)
	_wisp_origins.append(point)
	_wisp_bases.append(basis)
	_wisp_directions.append((_right * side + Vector3.UP * (0.2 + 0.06 * (index % 3))).normalized())
	_wisp_retreat_distances.append(retreat_distance if retreat_distance > 0.0 else settings.fog_retreat_distance * 0.22)

func _cloud_volume(label: String, size: Vector3) -> FogVolume:
	var material := ShaderMaterial.new()
	material.shader = VOLUME_FOG
	material.set_shader_parameter("fog_color", settings.fog_color)
	material.set_shader_parameter("noise_atlas", CLOUD_NOISE)
	material.set_shader_parameter("self_emission", settings.fog_self_emission)
	var cloud := FogVolume.new()
	cloud.name = label
	cloud.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
	cloud.size = size
	cloud.material = material
	_effects.add_child(cloud)
	return cloud

func _process(delta: float) -> void:
	if _prewarming:
		# 无界面测试使用相同状态机；实机只由真正绘制完成的信号推进。
		if DisplayServer.get_name() == "headless": _on_render_frame()
		return
	if _render_wait_frames > 0: return
	if _drop_next_delta:
		_drop_next_delta = false
		return
	# 只限制演出时钟的补时，世界和人物物理继续按原时间运行。
	advance(minf(maxf(delta, 0.0), 1.0 / 30.0))

func _on_render_frame() -> void:
	if not active: return
	if not is_instance_valid(camera) or not is_instance_valid(player) or not camera.is_inside_tree() or not player.is_inside_tree():
		_release()
		return
	_render_wait_frames = maxi(_render_wait_frames - 1, 0)
	if _prewarming:
		if _render_wait_frames > 0: return
		_prewarm_index += 1
		if _prewarm_index >= PREWARM_PROGRESS.size():
			skip()
		else:
			var progress: float = PREWARM_PROGRESS[_prewarm_index]
			_elapsed = progress * settings.duration_seconds
			_apply(progress)
			_render_wait_frames = 2
		return
	if _render_wait_frames == 0:
		_drop_next_delta = true
		if RenderingServer.frame_post_draw.is_connected(_on_render_frame): RenderingServer.frame_post_draw.disconnect(_on_render_frame)

func advance(delta: float) -> void:
	if not active or _prewarming: return
	if not is_instance_valid(camera) or not is_instance_valid(player) or not camera.is_inside_tree() or not player.is_inside_tree():
		_release()
		return
	_elapsed += maxf(delta, 0.0)
	var progress := clampf(_elapsed / maxf(settings.duration_seconds, 0.001), 0.0, 1.0)
	_apply(progress)
	_update_traversal_audio(progress)
	if progress >= 1.0: skip()

func _update_traversal_audio(progress: float) -> void:
	# 隐藏预热只加载素材；等首轮画面真正呈现后才播放可听入场。
	if not _audible_entry or not settings.traversal_audio_enabled or not settings.traversal_sound:
		if _traversal: _traversal.stop()
		return
	var flight_seconds := settings.duration_seconds * clampf(settings.arrival_ratio, 0.35, 0.85)
	var tail_seconds := minf(0.8, settings.duration_seconds - flight_seconds)
	var fade := smoothstep(0.0, 0.25, _elapsed) * (1.0 - smoothstep(flight_seconds - 0.3, flight_seconds + tail_seconds, _elapsed))
	if progress >= 1.0 or fade <= 0.0001:
		if _traversal: _traversal.stop()
		return
	if not _traversal:
		_traversal = AudioStreamPlayer.new()
		_traversal.name = "EntryMistTraversal"
		_traversal.stream = settings.traversal_sound
		_traversal.volume_db = -80.0
		_traversal.bus = &"Movement" if AudioServer.get_bus_index(&"Movement") >= 0 else &"Master"
		_traversal.pitch_scale = clampf(settings.traversal_sound.get_length() / maxf(flight_seconds + tail_seconds, 0.1), 0.65, 1.5)
		add_child(_traversal)
	if not _traversal.playing:
		var offset := _elapsed * _traversal.pitch_scale
		if offset >= settings.traversal_sound.get_length(): return
		_traversal.play(offset)
	var travel_time := clampf(_elapsed / maxf(flight_seconds, 0.001), 0.0, 1.0)
	# 五次平滑的速度包络：随推进渐强，落稳后留下短暂的散雾尾气。
	var speed := 16.0 * pow(travel_time * (1.0 - travel_time), 2.0)
	_traversal.volume_db = settings.traversal_volume_db + linear_to_db(maxf(fade * lerpf(0.22, 1.0, speed), 0.0001))

func _apply(progress: float) -> void:
	# 先完成有横移、绕转与侧倾的穿雾飞行，再固定取景缓慢散雾。
	var arrival := clampf(settings.arrival_ratio, 0.35, 0.85)
	var travel := _ease(clampf(progress / arrival, 0.0, 1.0))
	var reveal := _ease(clampf(inverse_lerp(arrival + 0.045, 1.0, progress), 0.0, 1.0))
	var point := player.get_global_transform_interpolated().origin
	var focus := point + Vector3.UP * camera.focus_height
	focus.x = clampf(focus.x, camera.bounds_min.x, camera.bounds_max.x)
	focus.z = clampf(focus.z, camera.bounds_min.y, camera.bounds_max.y)
	camera.anchor = focus
	camera.focus = focus
	var offset := _route_offset(travel)
	camera.global_position = focus + offset
	camera.global_basis = Basis(_flight_rotation(travel, offset))
	# 云团保持自身浓度，通过位移和密度场输运让出视野；仅最后清理残余。
	fog_amount = settings.fog_opacity * (1.0 - smoothstep(0.96, 1.0, progress))
	var retreat := reveal * settings.fog_retreat_distance
	for index in _bank_materials.size():
		var material := _bank_materials[index]
		material.set_shader_parameter("density", settings.volume_density * fog_amount * settings.cloud_bank_density_ratio)
		material.set_shader_parameter("flow_time", _elapsed * settings.fog_flow_speed * (0.8 + (index % 3) * 0.2))
		material.set_shader_parameter("reveal_origin", point)
		material.set_shader_parameter("reveal_progress", reveal)
		material.set_shader_parameter("retreat_distance", settings.fog_retreat_distance)
		material.set_shader_parameter("curl_strength", settings.fog_curl_strength)
		var outward := _bank_origins[index] - point
		outward.y = 0.0
		outward = outward.normalized()
		_fog_banks[index].global_position = _bank_origins[index] + outward * retreat + Vector3.UP * sin(PI * reveal) * 4.0
		_fog_banks[index].global_basis = Basis(outward.cross(Vector3.UP).normalized(), reveal * 1.3 * settings.fog_curl_strength)
	_volume_material.set_shader_parameter("density", settings.volume_density * fog_amount * 0.65)
	_volume_material.set_shader_parameter("flow_time", _elapsed * settings.fog_flow_speed)
	_volume_material.set_shader_parameter("reveal_origin", point)
	_volume_material.set_shader_parameter("reveal_progress", reveal)
	# 广域云层也须退出整个可见深度，不能在地图外留下雾墙直到最后一帧才消失。
	_volume_material.set_shader_parameter("retreat_distance", _cover_retreat_distance * settings.fog_retreat_distance / 42.0)
	_volume_material.set_shader_parameter("curl_strength", settings.fog_curl_strength)
	_wisp_material.set_shader_parameter("opacity", fog_amount * settings.wisp_opacity)
	_wisp_material.set_shader_parameter("flow_time", _elapsed * settings.fog_flow_speed)
	_wisp_material.set_shader_parameter("reveal_progress", reveal)
	_emission_fog.refresh(camera, player)
	_emission_fog.apply_weight(fog_amount * (1.0 - reveal))
	if _soft_focus_material:
		_soft_focus_material.set_shader_parameter("fog_weight", fog_amount / maxf(settings.fog_opacity, 0.001))
		_soft_focus_material.set_shader_parameter("reveal_origin", point)
		_soft_focus_material.set_shader_parameter("clear_radius", retreat)
	for material in _building_materials.values():
		material.set_shader_parameter("entry_weight", 1.0 - reveal)
	for index in _wisps.size():
		var direction := _wisp_directions[index]
		_wisps[index].global_position = _wisp_origins[index] + direction * reveal * _wisp_retreat_distances[index]
		_wisps[index].global_basis = _wisp_bases[index].rotated(_wisp_bases[index].z.normalized(), sin(PI * reveal) * direction.dot(_right) * 0.45 * settings.fog_curl_strength)
	# 临近收尾先回到场景原有空气与受光，恢复环境引用时不突然变色。
	if _scene_environment:
		var base_density := _scene_environment.volumetric_fog_density if _scene_environment.volumetric_fog_enabled else 0.0
		camera.environment.volumetric_fog_density = base_density * reveal
		camera.environment.volumetric_fog_length = lerpf(CLOUD_DEPTH, _scene_environment.volumetric_fog_length, reveal)
		camera.environment.volumetric_fog_sky_affect = lerpf(1.0, _scene_environment.volumetric_fog_sky_affect, reveal)
		camera.environment.volumetric_fog_ambient_inject = lerpf(0.18, _scene_environment.volumetric_fog_ambient_inject, reveal)
		camera.environment.volumetric_fog_albedo = settings.fog_color.lerp(_scene_environment.volumetric_fog_albedo, reveal)
	var emphasis := 1.0 - smoothstep(0.25, 1.0, reveal)
	_spotlight.light_energy = settings.spotlight_energy * emphasis
	_spotlight.light_volumetric_fog_energy = settings.spotlight_fog_energy * emphasis
	_spotlight.global_position = point + Vector3.UP * settings.spotlight_height + _right * 3.0 + _backward * 1.5
	_spotlight.look_at(point + Vector3.UP * 0.15, Vector3.UP)

func _input(event: InputEvent) -> void:
	if not active: return
	# 此按键只跳过入场，不继续传给人物跳跃、战斗或界面。
	get_viewport().set_input_as_handled()
	if settings.allow_skip and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		skip()

func skip() -> void:
	if not active: return
	_release()
	finished.emit()

func _release() -> void:
	if not active: return
	active = false
	_prewarming = false
	_prewarm_index = 0
	fog_amount = 0.0
	set_process(false)
	set_process_input(false)
	remove_from_group(&"gameplay_input_blockers")
	if RenderingServer.frame_post_draw.is_connected(_on_render_frame): RenderingServer.frame_post_draw.disconnect(_on_render_frame)
	_render_wait_frames = 0
	_drop_next_delta = false
	if is_instance_valid(camera):
		camera.environment = _original_environment
		if camera.is_inside_tree() and is_instance_valid(camera.target) and camera.target.is_inside_tree(): camera.snap_to_target()
		camera.set_process(_camera_was_processing)
	for hud in _hud_visibility:
		if is_instance_valid(hud): hud.visible = _hud_visibility[hud]
	_hud_visibility.clear()
	if is_instance_valid(_outline_sprite): _outline_sprite.occlusion_outline_enabled = _outline_was_enabled
	_outline_sprite = null
	_outline_was_enabled = false
	_restore_buildings()
	_emission_fog.clear()
	if is_instance_valid(_effects):
		_effects.hide()
		_effects.queue_free()
	_spotlight = null
	_fog = null
	_fog_banks.clear()
	_bank_materials.clear()
	_bank_origins.clear()
	_wisps.clear()
	_wisp_origins.clear()
	_wisp_bases.clear()
	_wisp_directions.clear()
	_wisp_retreat_distances.clear()
	_wisp_material = null
	_soft_focus = null
	_soft_focus_material = null
	_effects = null
	_volume_material = null
	_cover_retreat_distance = 0.0
	_original_environment = null
	_scene_environment = null
	_route_curve = null
	_route_transform = Transform3D.IDENTITY
	_route_focus = Vector3.ZERO
	_route_length = 0.0
	if is_instance_valid(_traversal):
		_traversal.stop()
		_traversal.queue_free()
	_traversal = null
	_audible_entry = true

func _exit_tree() -> void:
	_release()
