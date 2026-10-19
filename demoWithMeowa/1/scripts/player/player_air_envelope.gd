class_name PlayerAirEnvelope
extends MeshInstance3D

## 连续的空气绕流表面；只消费真实速度，不生成独立风条或改动人物。
var phase := 0.0
var amount := 0.0
var _material: ShaderMaterial
var _body_layouts: Dictionary = {}

func _ready() -> void:
	_material = material_override.duplicate() as ShaderMaterial
	material_override = _material
	stop()

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
	_material.set_shader_parameter(&"opacity", settings.speed_flow_opacity)
	_material.set_shader_parameter(&"flow_radius", settings.speed_flow_radius)
	_material.set_shader_parameter(&"flow_length", settings.speed_flow_length)
	_material.set_shader_parameter(&"distortion_pixels", settings.speed_air_distortion_pixels)
	var radius := settings.speed_flow_radius + 0.08
	var length := settings.speed_flow_length
	custom_aabb = AABB(Vector3(-radius, -radius * 1.6, -length * 0.8 - 0.1), Vector3(radius * 2.0, radius * 3.2, length + 0.2))
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
	var key: Array = [source.texture, source.texture.get_rid(), source.texture.get_size(), source.get_item_rect(), source.pixel_size,
		source.axis, source.hframes, source.vframes, source.frame, source.region_enabled, source.region_rect, source.flip_h, source.flip_v]
	var texture := source.texture
	while texture is AtlasTexture:
		var atlas := texture as AtlasTexture
		key.append_array([atlas.region, atlas.margin, atlas.atlas, atlas.atlas.get_size() if atlas.atlas else Vector2.ZERO])
		texture = atlas.atlas
	if not _body_layouts.has(key):
		var arrays := RenderingServer.mesh_surface_get_arrays(source.get_base(), 0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		if _body_layouts.size() >= 64: _body_layouts.clear()
		_body_layouts[key] = [vertices[0], vertices[1] - vertices[0], vertices[3] - vertices[0],
			uvs[0], uvs[1] - uvs[0], uvs[3] - uvs[0]]
	var layout: Array = _body_layouts[key]
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
