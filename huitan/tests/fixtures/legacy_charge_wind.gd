extends PlayerChargeWind

## Frozen before the presentation submission refactor.
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
	_material.set_shader_parameter("funnel_enabled", visuals.charge_wind_funnel_enabled)
	_material.set_shader_parameter("radius", radius)
	_material.set_shader_parameter("bottom_radius", bottom_radius)
	_material.set_shader_parameter("height", height)
	_material.set_shader_parameter("width", width)
	_material.set_shader_parameter("turns", visuals.charge_wind_turns)
	_material.set_shader_parameter("trail_span", visuals.charge_wind_trail_span)
	_material.set_shader_parameter("opacity", visuals.charge_wind_opacity * visuals.charge_effect_opacity)
	# Shader displacement stays within this local volume, including ribbon width.
	var padding := width * 0.5 + pixel
	var extent := radius + padding
	_wisps.custom_aabb = AABB(Vector3(-extent, -padding, -extent), Vector3(extent * 2.0, height + padding * 2.0, extent * 2.0))
	show()
