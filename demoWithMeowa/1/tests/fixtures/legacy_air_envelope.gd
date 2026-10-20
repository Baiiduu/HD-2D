extends PlayerAirEnvelope

## Frozen before the presentation submission refactor.
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
	_material.set_shader_parameter(&"flow_brush", settings.speed_flow_texture)
	var region := settings.speed_flow_texture_region
	_material.set_shader_parameter(&"brush_region", Vector4(region.position.x, region.position.y, region.size.x, region.size.y))
	var radius := settings.speed_flow_radius
	var length := settings.speed_flow_length
	var padding := radius * 0.6
	custom_aabb = AABB(Vector3(-radius - padding, -radius - padding, -length - padding), Vector3((radius + padding) * 2.0, (radius + padding) * 2.0, length * 1.22 + padding * 2.0))
	show()
	_sync_body_mask(source)
