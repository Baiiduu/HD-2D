class_name PlayerChargeWind
extends Node3D
const BODY_LAYOUT := preload("res://scripts/rendering/sprite_body_layout.gd")

## 原生 Meowa 风纹沿立体螺旋运动；地图可选下窄上宽的向上风旋。
## 由蓄力组件统一推进，无独立处理，不查询场景或改写人物运动。
const WISP_COUNT := 6
const SEGMENTS := 24
var _wisps: MultiMeshInstance3D
var _material: ShaderMaterial
var _phase := 0.0
var _texture: Texture2D
var _shape_profile: Array = []

func _ready() -> void:
	_wisps = MultiMeshInstance3D.new()
	_wisps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.use_custom_data = true
	mesh.mesh = _ribbon()
	_wisps.multimesh = mesh
	_set_layers(1)
	_material = ShaderMaterial.new()
	_material.shader = preload("res://shaders/combat/player_charge_wind.gdshader")
	_wisps.material_override = _material
	add_child(_wisps)
	stop()

func _set_layers(layers: int) -> void:
	var mesh := _wisps.multimesh
	var count := WISP_COUNT * layers
	if mesh.instance_count == count: return
	mesh.instance_count = count
	for layer in layers:
		var parameters := layer_parameters(layer, layers)
		for wisp in WISP_COUNT:
			var index := layer * WISP_COUNT + wisp
			mesh.set_instance_transform(index, Transform3D.IDENTITY)
			mesh.set_instance_custom_data(index, Color(float(wisp) / WISP_COUNT, parameters.x, parameters.y, parameters.z))

## 每层一次计算方位、收径与不透明度，同层风带共用；不依赖渲染后端回读。
static func layer_parameters(layer: int, layers: int) -> Vector3:
	return Vector3(float(layer) / layers, 1.0 - layer * 0.06, pow(0.72, layer))

func _ribbon() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for index in SEGMENTS + 1:
		var u := float(index) / SEGMENTS
		vertices.append(Vector3(u, -0.5, 0.0))
		vertices.append(Vector3(u, 0.5, 0.0))
		uvs.append(Vector2(u, 1.0))
		uvs.append(Vector2(u, 0.0))
		if index < SEGMENTS:
			var start := index * 2
			indices.append_array(PackedInt32Array([start, start + 1, start + 2, start + 1, start + 3, start + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func synchronize(visuals: PlayerActionVisuals, pixel: float, fraction: float, delta: float) -> void:
	if not visuals.charge_wind_enabled or not visuals.charge_wind_texture:
		stop()
		return
	if _texture != visuals.charge_wind_texture:
		_texture = visuals.charge_wind_texture
		_material.set_shader_parameter("airflow_texture", _texture)
	_set_layers(clampi(visuals.charge_wind_layers, 1, 5) if visuals.charge_wind_funnel_enabled else 1)
	_phase = fposmod(_phase + delta / maxf(visuals.charge_wind_cycle_seconds, 0.01) * lerpf(0.65, visuals.charge_wind_full_speed_multiplier, fraction), 1.0)
	var radius := visuals.charge_wind_radius_pixels * pixel
	var bottom_radius := minf(visuals.charge_wind_bottom_radius_pixels * pixel, radius)
	var height := visuals.charge_wind_height_pixels * pixel
	var width := visuals.charge_wind_width_pixels * pixel if visuals.charge_wind_funnel_enabled else _texture.get_height() * pixel * 0.65
	_material.set_shader_parameter("phase", _phase)
	_material.set_shader_parameter("charge", fraction)
	var opacity := visuals.charge_wind_opacity * visuals.charge_effect_opacity
	# 只复用本节点已提交的形状配置；数值、像素尺度变化立即生效，不缓存相位或人物遮罩。
	var profile: Array = [visuals.charge_wind_funnel_enabled, radius, bottom_radius, height, width, visuals.charge_wind_turns, visuals.charge_wind_trail_span, opacity, pixel]
	if profile != _shape_profile:
		_shape_profile = profile
		_material.set_shader_parameter("funnel_enabled", visuals.charge_wind_funnel_enabled)
		_material.set_shader_parameter("radius", radius)
		_material.set_shader_parameter("bottom_radius", bottom_radius)
		_material.set_shader_parameter("height", height)
		_material.set_shader_parameter("width", width)
		_material.set_shader_parameter("turns", visuals.charge_wind_turns)
		_material.set_shader_parameter("trail_span", visuals.charge_wind_trail_span)
		_material.set_shader_parameter("opacity", opacity)
		# Shader displacement stays within this local volume, including ribbon width.
		var padding := width * 0.5 + pixel
		var extent := radius + padding
		_wisps.custom_aabb = AABB(Vector3(-extent, -padding, -extent), Vector3(extent * 2.0, height + padding * 2.0, extent * 2.0))
	show()

func stop() -> void:
	_phase = 0.0
	if _material: _material.set_shader_parameter("body_mask_enabled", false)
	hide()

## 与人形残影使用同一真实帧投影规则，保护 Q/E 后仍可见的头发、双剑和身体。
func sync_body_mask(source: Sprite3D, clearance: float) -> void:
	_material.set_shader_parameter("body_mask_margin_pixels", maxf(0.0, clearance))
	var enabled := visible and clearance > 0.0 and is_instance_valid(source) and source.texture != null and source.is_visible_in_tree() and source.modulate.a > 0.01 and DisplayServer.get_name() != "headless"
	_material.set_shader_parameter("body_mask_enabled", enabled)
	if not enabled: return
	var layout: Array = BODY_LAYOUT.sample(source)
	_material.set_shader_parameter("body_texture", source.texture)
	_material.set_shader_parameter("body_transform", source.get_global_transform_interpolated())
	_material.set_shader_parameter("body_motion_lean", source.get_meta("motion_lean", Vector3.ZERO))
	_material.set_shader_parameter("body_motion_pivot", source.get_meta("motion_pivot", Vector3.ZERO))
	_material.set_shader_parameter("body_billboard_mode", source.billboard)
	_material.set_shader_parameter("body_origin", layout[0])
	_material.set_shader_parameter("body_edge_u", layout[1])
	_material.set_shader_parameter("body_edge_v", layout[2])
	_material.set_shader_parameter("body_uv_origin", layout[3])
	_material.set_shader_parameter("body_uv_u", layout[4])
	_material.set_shader_parameter("body_uv_v", layout[5])
