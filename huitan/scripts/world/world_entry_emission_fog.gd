extends RefCounted
## 入场专用的发光材质代理，只向体积雾散射，不照亮场景表面。
var _sources: Array[Dictionary] = []
var _lights: Array[OmniLight3D] = []
var _energies: Array[float] = []
var _geometry: Dictionary = {}
var _images: Dictionary = {}
var _settings: WorldEntrySettings
var _excluded: Array[RID] = []
var _next_refresh := 0

func prepare(scene: Node3D, effects: Node3D, settings: WorldEntrySettings) -> void:
	clear()
	_settings = settings
	if not settings.emission_fog_enabled: return
	for boundary in scene.get_tree().get_nodes_in_group(&"map_boundaries"):
		if boundary is CollisionObject3D and scene.is_ancestor_of(boundary): _excluded.append(boundary.get_rid())
	var meshes: Dictionary[MeshInstance3D, bool] = {}
	for group in [&"occlusion_buildings", &"ricochet_obstacles"]:
		for building in scene.get_tree().get_nodes_in_group(group):
			if not scene.is_ancestor_of(building): continue
			if building is MeshInstance3D: meshes[building as MeshInstance3D] = true
			for mesh: MeshInstance3D in building.find_children("*", "MeshInstance3D", true, false): meshes[mesh] = true
	for mesh in meshes:
		if not mesh.mesh: continue
		for surface in mesh.mesh.get_surface_count():
			var profile := _profile(mesh.get_active_material(surface))
			if profile.is_empty(): continue
			for patch in _patches(mesh.mesh, surface, profile):
				_sources.append({"mesh": weakref(mesh), "surface": surface, "patch": patch})
	for index in mini(settings.emission_fog_max_lights, _sources.size()):
		var light := OmniLight3D.new()
		light.name = "BuildingFogScatter%d" % index
		light.light_cull_mask = 0
		light.light_indirect_energy = 0.0
		light.light_specular = 0.0
		light.light_volumetric_fog_energy = 1.0
		light.light_bake_mode = Light3D.BAKE_DISABLED
		light.shadow_enabled = false
		light.omni_attenuation = 1.0
		light.omni_range = settings.emission_fog_radius
		light.hide()
		effects.add_child(light)
		_lights.append(light)
		_energies.append(0.0)

func _profile(material: Material) -> Dictionary:
	if material is BaseMaterial3D:
		if not material.emission_enabled and material.emission_texture == null: return {}
		return {"texture": material.emission_texture, "mask": null, "tint": material.emission,
			"energy": material.emission_energy_multiplier if material.emission_enabled else 0.0,
			"multiply": material.emission_operator == BaseMaterial3D.EMISSION_OP_MULTIPLY,
			"scale": Vector2(material.uv1_scale.x, material.uv1_scale.y), "offset": Vector2(material.uv1_offset.x, material.uv1_offset.y)}
	if material is ShaderMaterial and material.shader:
		var path: String = material.shader.resource_path
		if path == "res://shaders/environment/cyber_armillary.gdshader":
			return {"texture": material.get_shader_parameter("albedo_atlas"), "mask": material.get_shader_parameter("orm_atlas"),
				"tint": Color.WHITE, "energy": material.get_shader_parameter("emission_energy"), "multiply": true, "scale": Vector2.ONE, "offset": Vector2.ZERO}
	return {}

func _texel(texture: Texture2D, uv: Vector2) -> Color:
	if not texture: return Color.WHITE
	if not _images.has(texture):
		var image := texture.get_image()
		if image and image.is_compressed(): image.decompress()
		_images[texture] = image
	var image: Image = _images[texture]
	if not image or image.is_empty(): return Color.BLACK
	return image.get_pixel(clampi(int(uv.x * image.get_width()), 0, image.get_width() - 1), clampi(int(uv.y * image.get_height()), 0, image.get_height() - 1))

func _patches(mesh: Mesh, surface: int, profile: Dictionary) -> Array:
	var key := [mesh, surface, profile.texture, profile.mask, profile.scale, profile.offset]
	if _geometry.has(key): return _geometry[key]
	var arrays := mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if indices.is_empty(): indices = PackedInt32Array(range(vertices.size()))
	var groups: Dictionary = {}
	for index in range(0, indices.size() - 2, 3):
		var a := indices[index]
		var b := indices[index + 1]
		var c := indices[index + 2]
		var cross := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
		var area := cross.length() * 0.5
		if area < 0.000001: continue
		var normal := normals[a] if not normals.is_empty() else cross.normalized()
		var axis := normal.abs().max_axis_index()
		var side := axis * 2 + int(normal[axis] < 0.0)
		if not groups.has(side): groups[side] = {"point": Vector3.ZERO, "normal": Vector3.ZERO, "color": Color(0, 0, 0, 0), "area": 0.0, "weight": 0.0}
		var color := Color(0, 0, 0, 0)
		for bary in [Vector3(0.6, 0.2, 0.2), Vector3(0.2, 0.6, 0.2), Vector3(0.2, 0.2, 0.6)]:
			var uv: Vector2 = (uvs[a] * bary.x + uvs[b] * bary.y + uvs[c] * bary.z) * profile.scale + profile.offset if not uvs.is_empty() else Vector2.ZERO
			var sample := _texel(profile.texture, uv)
			if profile.mask: sample *= _texel(profile.mask, uv).a
			color += sample / 3.0
		var weight := area * maxf(maxf(color.r, maxf(color.g, color.b)), 0.001)
		var group: Dictionary = groups[side]
		group.point += (vertices[a] + vertices[b] + vertices[c]) / 3.0 * weight
		group.normal += normal * weight
		group.color += color * area
		group.area += area
		group.weight += weight
	var result: Array = []
	for group: Dictionary in groups.values():
		result.append({"point": group.point / group.weight, "normal": group.normal.normalized(), "color": group.color / group.area})
	_geometry[key] = result
	return result

func refresh(camera: Camera3D, player: Node3D, force := false) -> void:
	if _lights.is_empty(): return
	var now := Time.get_ticks_msec()
	if not force and now < _next_refresh: return
	_next_refresh = now + int(_settings.emission_fog_refresh_seconds * 1000.0)
	var candidates: Array[Dictionary] = []
	var excluded: Array[RID] = _excluded.duplicate()
	if player is CollisionObject3D: excluded.append(player.get_rid())
	for source in _sources:
		var mesh: MeshInstance3D = source.mesh.get_ref()
		if not mesh or not mesh.is_inside_tree() or not mesh.is_visible_in_tree(): continue
		var profile := _profile(mesh.get_active_material(source.surface))
		if profile.is_empty() or profile.energy <= 0.0: continue
		var color: Color = profile.tint
		if profile.texture: color = color * source.patch.color if profile.multiply else color + source.patch.color
		if profile.mask and not profile.texture: color *= source.patch.color.a
		var peak := maxf(color.r, maxf(color.g, color.b))
		if peak <= 0.0001: continue
		var normal: Vector3 = (mesh.global_basis.inverse().transposed() * source.patch.normal).normalized()
		var point: Vector3 = mesh.global_transform * source.patch.point + normal * 0.2
		if camera.is_position_behind(point): continue
		candidates.append({"point": point, "color": Color(color.r / peak, color.g / peak, color.b / peak), "energy": profile.energy * peak * _settings.emission_fog_strength,
			"score": profile.energy * peak / (1.0 + camera.global_position.distance_squared_to(point))})
	candidates.sort_custom(func(a, b): return a.score > b.score)
	_energies.fill(0.0)
	var slot := 0
	var space := camera.get_world_3d().direct_space_state
	for candidate in candidates:
		if slot >= _lights.size(): break
		var ray := PhysicsRayQueryParameters3D.create(camera.global_position, candidate.point, 1, excluded)
		if not space.intersect_ray(ray).is_empty(): continue
		_lights[slot].global_position = candidate.point
		_lights[slot].light_color = candidate.color
		_energies[slot] = candidate.energy
		slot += 1

func apply_weight(weight: float) -> void:
	for index in _lights.size():
		_lights[index].light_energy = _energies[index] * weight
		_lights[index].visible = _lights[index].light_energy > 0.0001

func clear() -> void:
	for light in _lights:
		if is_instance_valid(light):
			light.hide()
			light.queue_free()
	_lights.clear()
	_energies.clear()
	_sources.clear()
	_excluded.clear()
	_next_refresh = 0
