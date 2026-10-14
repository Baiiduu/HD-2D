class_name LightPierceEffect
extends Node3D

## 可复用的贯穿视觉组件；发射和命中由调用方传入，不结算伤害。
signal finished

const EFFECT_SHADER := preload("res://shaders/combat/light_pierce.gdshader")
const TRAIL_SEGMENTS := 20
static var _ribbon_mesh: ArrayMesh

@export_group("Meowa 美术")
@export var head_texture: Texture2D
@export var trail_texture: Texture2D
@export var impact_frames: SpriteFrames
@export var impact_animation: StringName = &"impact"
@export var effect_tint := Color.WHITE
@export_group("枪锋与飞行")
## 世界坐标中的飞行速度，视觉预览参数，不代表已确认的攻击数值。
@export_range(1.0, 30.0, 0.5, "suffix:m/s") var flight_speed := 14.0
## 发射位置相对于地面抬高的距离。
@export_range(0.05, 2.0, 0.05, "suffix:m") var flight_height := 0.65
@export_range(0.2, 4.0, 0.05, "suffix:m") var head_width := 2.45
## 雷刺前端在贴图中的水平位置；定位到真实弹道，转镜头时尖端不会漂移。
@export_range(0.0, 1.0, 0.01) var head_tip_anchor := 0.5
@export_group("光丝拖尾")
## 只保留枪锋后方这段轨迹，离开后逐渐消退。
@export_range(0.5, 8.0, 0.1, "suffix:m") var trail_length := 6.0
## 包含透明辉光的整体宽度；光丝主体比这个值细。
@export_range(0.1, 2.0, 0.05, "suffix:m") var trail_width := 1.25
@export_range(0.05, 0.8, 0.01, "suffix:s") var trail_fade_time := 0.28
## 原生像素尾迹按固定世界长度采样，起手时裁切已行进部分，不压缩整条贴图。
@export var preserve_trail_pixel_scale := false:
	set(value):
		preserve_trail_pixel_scale = value
		if is_node_ready(): _configure_pixel_sampling()
@export_group("命中星芒")
@export_range(0.2, 3.0, 0.05, "suffix:m") var impact_width := 2.7
@export_range(0.08, 0.8, 0.01, "suffix:s") var impact_duration := 0.4
@export_range(0.0, 1.5, 0.05, "suffix:m") var impact_height := 0.4
@export_group("辉光与映照")
@export_range(0.0, 1.0, 0.05) var effect_opacity := 0.85
@export_range(0.0, 4.0, 0.05) var effect_energy := 1.3
## 单独加强细尾迹的辉光，保留雷刺与命中闪光的亮度。
@export_range(0.0, 4.0, 0.05) var trail_energy_multiplier := 1.0
## 一盏无阴影的短时光源随枪锋移动，给近处草地少量映照。
@export var ground_light_enabled := true
@export var ground_light_color := Color(0.52, 0.81, 1.0)
@export_range(0.0, 2.0, 0.05) var ground_light_energy := 0.3
@export_range(0.5, 5.0, 0.1, "suffix:m") var ground_light_range := 2.4

var travelled := 0.0
var _origin := Vector3.ZERO
var _direction := Vector3.RIGHT
var _distance := 0.0
var _age := 0.0
var _flying := false
var _manual_flight := false
var _flight_ended := false
var _head: MeshInstance3D
var _trail: MeshInstance3D
var _light: OmniLight3D
var _head_material: ShaderMaterial
var _trail_material: ShaderMaterial
var _impacts: Array[Dictionary] = []
var _impact_pool: Array[Dictionary] = []

func _ready() -> void:
	_head_material = _material(head_texture)
	_trail_material = _material(trail_texture)
	_configure_pixel_sampling()
	_head = _quad(_head_material)
	_head.name = "CrystalHead"
	_trail = MeshInstance3D.new()
	_trail.name = "LightRibbons"
	_trail.mesh = _shared_ribbon_mesh()
	_trail.material_override = _trail_material
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_trail)
	_light = OmniLight3D.new()
	_light.name = "PassingLight"
	_light.shadow_enabled = false
	add_child(_light)
	stop()

func launch(origin: Vector3, direction: Vector3, distance: float, manual_flight := false) -> void:
	if not is_node_ready(): return
	stop()
	_origin = origin + Vector3.UP * flight_height
	_direction = direction.normalized() if not direction.is_zero_approx() else Vector3.RIGHT
	_distance = maxf(distance, 0.01)
	travelled = 0.0
	_age = 0.0
	_flying = true
	_manual_flight = manual_flight
	_flight_ended = false
	_head_material.set_shader_parameter("effect_texture", head_texture)
	_trail_material.set_shader_parameter("effect_texture", trail_texture)
	_head.visible = head_texture != null
	_trail.visible = trail_texture != null
	set_process(true)
	_update_flight(get_viewport().get_camera_3d())

## 实战由物理扫掠传入位置；渲染只更新朝向、完整命中动画与末端消退。
func advance_flight(distance: float, ended := false) -> void:
	if not _flying or not _manual_flight or _flight_ended: return
	travelled = clampf(distance, 0.0, _distance)
	_age = travelled / maxf(flight_speed, 0.01)
	if ended:
		_distance = travelled
		_flight_ended = true
	_update_flight(get_viewport().get_camera_3d())

func show_hit(ground_position: Vector3) -> void:
	if not is_node_ready() or not impact_frames or not impact_frames.has_animation(impact_animation): return
	if impact_frames.get_frame_count(impact_animation) == 0: return
	var impact: Dictionary
	if _impact_pool.is_empty():
		var material := _material(null)
		var mesh := _quad(material)
		mesh.name = "ImpactStar"
		impact = {"mesh": mesh, "material": material}
	else:
		impact = _impact_pool.pop_back()
	impact.position = ground_position + Vector3.UP * impact_height
	impact.age = 0.0
	impact.mesh.global_position = impact.position
	var camera := get_viewport().get_camera_3d()
	if camera: impact.mesh.global_basis = camera.global_basis
	var texture := impact_frames.get_frame_texture(impact_animation, 0)
	if texture and (not texture is AtlasTexture or texture.atlas):
		_set_frame(impact.material, texture)
		_set_size(impact.mesh, impact_width, texture.get_size())
	_style(impact.material, 1.0)
	impact.mesh.visible = texture != null and (not texture is AtlasTexture or texture.atlas != null)
	_impacts.append(impact)
	set_process(true)

func stop() -> void:
	_flying = false
	for impact in _impacts: _recycle_impact(impact)
	_impacts.clear()
	if _head: _head.visible = false
	if _trail: _trail.visible = false
	if _light: _light.visible = false
	set_process(false)

func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if _flying:
		if not _manual_flight or _flight_ended: _age += delta
		if not _manual_flight: travelled = minf(_age * flight_speed, _distance)
		_update_flight(camera)
		if _age >= _distance / maxf(flight_speed, 0.01) + trail_fade_time:
			_flying = false
			_head.visible = false
			_trail.visible = false
			_light.visible = false
	for index in range(_impacts.size() - 1, -1, -1):
		var impact: Dictionary = _impacts[index]
		if not impact_frames or not impact_frames.has_animation(impact_animation) or impact_frames.get_frame_count(impact_animation) == 0:
			_recycle_impact(impact)
			_impacts.remove_at(index)
			continue
		impact.age += delta
		var progress := clampf(float(impact.age) / maxf(impact_duration, 0.01), 0.0, 1.0)
		if progress >= 1.0:
			_recycle_impact(impact)
			_impacts.remove_at(index)
			continue
		var frame_index := mini(int(progress * impact_frames.get_frame_count(impact_animation)),
			impact_frames.get_frame_count(impact_animation) - 1)
		var texture := impact_frames.get_frame_texture(impact_animation, frame_index)
		if not texture or (texture is AtlasTexture and not texture.atlas):
			impact.mesh.visible = false
			continue
		impact.mesh.visible = true
		_set_frame(impact.material, texture)
		_set_size(impact.mesh, impact_width, texture.get_size())
		impact.mesh.global_position = impact.position
		if camera: impact.mesh.global_basis = camera.global_basis
		_style(impact.material, 1.0 - smoothstep(0.55, 1.0, progress))
	if not _flying and _impacts.is_empty():
		set_process(false)
		finished.emit()

func _update_flight(camera: Camera3D) -> void:
	var position_on_path := _origin + _direction * travelled
	var flight_time := _distance / maxf(flight_speed, 0.01)
	var fade := 1.0 - clampf((_age - flight_time) / maxf(trail_fade_time, 0.01), 0.0, 1.0)
	_head.visible = head_texture != null and _age < flight_time
	if head_texture: _set_size(_head, head_width, head_texture.get_size())
	if camera:
		if preserve_trail_pixel_scale:
			# 长轴留在真实弹道上，Q/E 转到纵深方向时自然透视缩短。
			var side := camera.global_basis.z.cross(_direction).normalized()
			if side.is_zero_approx(): side = camera.global_basis.y
			_head.global_basis = Basis(_direction, side, _direction.cross(side))
		else:
			var right := camera.global_basis.x
			var up := camera.global_basis.y
			var angle := atan2(_direction.dot(up), _direction.dot(right))
			_head.global_basis = Basis(right * cos(angle) + up * sin(angle),
				up * cos(angle) - right * sin(angle), camera.global_basis.z)
	_head.global_position = position_on_path - _head.global_basis.x * (head_tip_anchor - 0.5) * head_width
	# 起手只露出真正行进过的雷刺，避免长贴图伸到人物后方。
	var projected_travel := travelled * maxf(_direction.dot(_head.global_basis.x), 0.0)
	_head_material.set_shader_parameter("clip_start", clampf(head_tip_anchor - projected_travel / maxf(head_width, 0.01), 0.0, head_tip_anchor) if preserve_trail_pixel_scale else 0.0)
	_style(_head_material, minf(_age / 0.035, 1.0))
	_style(_trail_material, fade * minf(travelled / 0.8, 1.0), trail_energy_multiplier)
	_update_trail(camera)
	_light.global_position = position_on_path
	_light.visible = ground_light_enabled and fade > 0.0
	_light.light_color = ground_light_color
	_light.light_energy = ground_light_energy * fade
	_light.omni_range = ground_light_range

func head_tip_position() -> Vector3:
	return _head.global_position + _head.global_basis.x * (head_tip_anchor - 0.5) * head_width

func _update_trail(camera: Camera3D) -> void:
	# 像素残影从雷刺后缘开始，保留三段间隙，避免最亮的一段被主体盖住。
	var trail_travelled := maxf(travelled - head_tip_anchor * head_width, 0.0) if preserve_trail_pixel_scale and head_texture else travelled
	var length := minf(trail_length, trail_travelled)
	if length < 0.01:
		_trail.visible = false
		return
	_trail.visible = trail_texture != null
	var side := Vector3.UP
	if camera:
		side = camera.global_basis.z.cross(_direction).normalized()
		if side.is_zero_approx(): side = camera.global_basis.y
	# 顶点与 UV 固定；长度、宽度、镜头朝向只改变实例变换。
	_trail.global_position = _origin + _direction * (trail_travelled - length)
	_trail.global_basis = Basis(_direction * length, side * trail_width, _direction.cross(side))
	if preserve_trail_pixel_scale:
		var visible_fraction := length / maxf(trail_length, 0.01)
		_trail_material.set_shader_parameter("frame_rect", Vector4(1.0 - visible_fraction, 0, visible_fraction, 1))

func _configure_pixel_sampling() -> void:
	if not _head_material or not _trail_material: return
	var edge := 0.0 if preserve_trail_pixel_scale else 0.06
	_head_material.set_shader_parameter("edge_fade", edge)
	_trail_material.set_shader_parameter("edge_fade", edge)
	_trail_material.set_shader_parameter("frame_rect", Vector4(0, 0, 1, 1))

static func _shared_ribbon_mesh() -> ArrayMesh:
	if _ribbon_mesh: return _ribbon_mesh
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for index in TRAIL_SEGMENTS + 1:
		var progress := float(index) / TRAIL_SEGMENTS
		var half_width := 0.5 * lerpf(0.3, 1.0, progress)
		vertices.append(Vector3(progress, half_width, 0))
		vertices.append(Vector3(progress, -half_width, 0))
		uvs.append(Vector2(progress, 0.0))
		uvs.append(Vector2(progress, 1.0))
		if index < TRAIL_SEGMENTS:
			var vertex := index * 2
			indices.append_array(PackedInt32Array([vertex, vertex + 1, vertex + 2, vertex + 1, vertex + 3, vertex + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_ribbon_mesh = ArrayMesh.new()
	_ribbon_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _ribbon_mesh

func _recycle_impact(impact: Dictionary) -> void:
	impact.mesh.visible = false
	_impact_pool.append(impact)

func _material(texture: Texture2D) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = EFFECT_SHADER
	material.set_shader_parameter("effect_texture", texture)
	return material

func _quad(material: ShaderMaterial) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = QuadMesh.new()
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh)
	return mesh

func _set_size(mesh: MeshInstance3D, width: float, texture_size: Vector2) -> void:
	var size := Vector2(width, width * texture_size.y / maxf(texture_size.x, 1.0))
	if (mesh.mesh as QuadMesh).size != size: (mesh.mesh as QuadMesh).size = size

func _style(material: ShaderMaterial, fade: float, energy_multiplier := 1.0) -> void:
	material.set_shader_parameter("opacity", effect_opacity * fade)
	material.set_shader_parameter("energy", effect_energy * energy_multiplier)
	material.set_shader_parameter("tint", effect_tint)

func _set_frame(material: ShaderMaterial, texture: Texture2D) -> void:
	if texture is AtlasTexture:
		material.set_shader_parameter("effect_texture", texture.atlas)
		var size: Vector2 = texture.atlas.get_size()
		material.set_shader_parameter("frame_rect", Vector4(texture.region.position.x / size.x,
			texture.region.position.y / size.y, texture.region.size.x / size.x, texture.region.size.y / size.y))
	else:
		material.set_shader_parameter("effect_texture", texture)
		material.set_shader_parameter("frame_rect", Vector4(0, 0, 1, 1))
