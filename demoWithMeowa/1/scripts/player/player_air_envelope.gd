class_name PlayerAirEnvelope
extends MeshInstance3D
const BODY_LAYOUT := preload("res://scripts/rendering/sprite_body_layout.gd")

## 开放曲面上的薄风纹，只消费真实速度，不折射背景或改动人物。
static var _wind_mesh: ArrayMesh
var phase := 0.0
var amount := 0.0
var _material: ShaderMaterial
var _shape_profile: Array = []

func _ready() -> void:
	if not _wind_mesh: _wind_mesh = _build_wind_mesh()
	mesh = _wind_mesh
	_material = material_override.duplicate() as ShaderMaterial
	material_override = _material
	stop()

static func _build_wind_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var sides := PackedVector2Array()
	var indices := PackedInt32Array()
	# Independent open surfaces have no seam or faces spanning the body.
	for side in [-1.0, 1.0]:
		var first := vertices.size()
		for index in 25:
			var u := float(index) / 24.0
			for v in [0.0, 1.0]:
				vertices.append(Vector3(u, v - 0.5, side))
				uvs.append(Vector2(u, v))
				sides.append(Vector2(side, 0.0))
			if index < 24:
				var a := first + index * 2
				indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = sides
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

func synchronize(source: Sprite3D, heading: Vector3, strength: float, delta: float, settings: PlayerActionVisuals) -> void:
	amount = strength
	if amount < 0.002:
		stop()
		return
	phase += maxf(0.0, delta) * lerpf(0.65, 2.2, strength)
	var forward := heading.normalized()
	var side := Vector3.UP.cross(forward).normalized()
	global_transform = Transform3D(Basis(side, Vector3.UP, forward), source.get_global_transform_interpolated().origin)
	_material.set_shader_parameter(&"flow_phase", phase)
	_material.set_shader_parameter(&"flow_amount", amount)
	var region := settings.speed_flow_texture_region
	var radius := settings.speed_flow_radius
	var length := settings.speed_flow_length
	var brush_region := Vector4(region.position.x, region.position.y, region.size.x, region.size.y)
	# 热调资源按实际值比较；方向、余速、位置与当前帧遮罩仍逐帧更新。
	var profile: Array = [settings.speed_flow_opacity, radius, length, settings.speed_flow_texture, brush_region]
	if profile != _shape_profile:
		_shape_profile = profile
		_material.set_shader_parameter(&"opacity", settings.speed_flow_opacity)
		_material.set_shader_parameter(&"flow_radius", radius)
		_material.set_shader_parameter(&"flow_length", length)
		_material.set_shader_parameter(&"flow_brush", settings.speed_flow_texture)
		_material.set_shader_parameter(&"brush_region", brush_region)
		var padding := radius * 0.6
		custom_aabb = AABB(Vector3(-radius - padding, -radius - padding, -length - padding), Vector3((radius + padding) * 2.0, (radius + padding) * 2.0, length * 1.22 + padding * 2.0))
	show()
	_sync_body_mask(source)

func stop() -> void:
	amount = 0.0
	phase = 0.0
	if _material:
		_material.set_shader_parameter(&"flow_amount", 0.0)
		_material.set_shader_parameter(&"body_mask_enabled", false)
	hide()

## 与蓄力风和人形残影共用实际 Sprite 网格与原生帧投影约定。
func _sync_body_mask(source: Sprite3D) -> void:
	var enabled := visible and source.texture != null and source.is_visible_in_tree() and source.modulate.a > 0.01 and DisplayServer.get_name() != "headless"
	_material.set_shader_parameter(&"body_mask_enabled", enabled)
	_material.set_shader_parameter(&"body_mask_margin_pixels", 1.0)
	if not enabled: return
	var layout: Array = BODY_LAYOUT.sample(source)
	_material.set_shader_parameter(&"body_texture", source.texture)
	_material.set_shader_parameter(&"body_transform", source.get_global_transform_interpolated())
	_material.set_shader_parameter(&"body_motion_lean", source.get_meta("motion_lean", Vector3.ZERO))
	_material.set_shader_parameter(&"body_motion_pivot", source.get_meta("motion_pivot", Vector3.ZERO))
	_material.set_shader_parameter(&"body_billboard_mode", source.billboard)
	_material.set_shader_parameter(&"body_origin", layout[0])
	_material.set_shader_parameter(&"body_edge_u", layout[1])
	_material.set_shader_parameter(&"body_edge_v", layout[2])
	_material.set_shader_parameter(&"body_uv_origin", layout[3])
	_material.set_shader_parameter(&"body_uv_u", layout[4])
	_material.set_shader_parameter(&"body_uv_v", layout[5])
