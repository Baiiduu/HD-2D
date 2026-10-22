extends EnemyDeathEffect

## Frozen before the presentation submission refactor.
func _display_impact(facing: Basis) -> void:
	if _age >= _impact_seconds or not _impact_source or not _impact_source.has_animation(&"bounce"):
		for index in range(1, 4): _pieces[index].hide()
		return
	var count := _impact_source.get_frame_count(&"bounce")
	if count == 0: return
	var frame := mini(count - 1, int(_age / _impact_seconds * count))
	var image := _impact_source.get_frame_texture(&"bounce", frame)
	if not image: return
	var size := image.get_size() * _pixel
	for index in 3:
		var slot := index + 1
		if frame != _impact_frame:
			var texture: Texture2D = image.atlas if image is AtlasTexture else image
			var rect: Rect2 = image.region if image is AtlasTexture else Rect2(Vector2.ZERO, image.get_size())
			var uv := Vector4(rect.position.x / texture.get_width(), rect.position.y / texture.get_height(), rect.size.x / texture.get_width(), rect.size.y / texture.get_height())
			_materials[slot] = MATERIALS.material(texture)
			_pieces[slot].material_override = _materials[slot]
			_pieces[slot].set_instance_shader_parameter(&"frame_rect", uv)
			_pieces[slot].set_instance_shader_parameter(&"tint", Color.WHITE)
			_pieces[slot].set_instance_shader_parameter(&"opacity", _impact_opacity)
			_pieces[slot].set_instance_shader_parameter(&"hit_flash", 0.0)
			_pieces[slot].set_instance_shader_parameter(&"death_energy", 1.2)
		var basis := facing * Basis(Vector3.BACK, _impact_angle + index * TAU / 3.0)
		# 原生 56×48 碰点的 (19,24) 是中心；三份原帧组成紧凑的放射爆点。
		var anchor := (image.get_size() * 0.5 - Vector2(19, 24)) * _pixel
		var spread := Vector3(_impact_radius * _age / _impact_seconds, 0, 0)
		_pieces[slot].global_position = _position + basis * (Vector3(anchor.x, -anchor.y, 0.0) + spread)
		_pieces[slot].global_basis = basis.scaled_local(Vector3(size.x, size.y, 1.0))
		_pieces[slot].show()
	_impact_frame = frame
