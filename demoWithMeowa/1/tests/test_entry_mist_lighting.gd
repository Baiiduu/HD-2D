extends "res://tests/test_world_entry.gd"

const CITY_SHADER = preload("res://shaders/environment/city_background_blend.gdshader")

func building(parent: Node, material: ShaderMaterial) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.material = material
	mesh.add_to_group(&"distant_city_geometry")
	parent.add_child(mesh)
	return mesh

func lighting_checks() -> void:
	var rules = SETTINGS.new()
	check("building_atmosphere_enabled" in rules, "Entry exposes an independent building atmosphere switch")
	if not "building_atmosphere_enabled" in rules: return
	check("building_edge_blur_strength" in rules, "Entry exposes silhouette blur separately from cloud density")
	if not "building_edge_blur_strength" in rules: return
	check(not rules.building_atmosphere_enabled, "Other maps retain their existing entry appearance by default")
	var world := fixture()
	var source := ShaderMaterial.new()
	source.shader = CITY_SHADER
	source.set_shader_parameter("emission_energy", 0.15)
	source.set_shader_parameter("emission_tint", Color(1.0, 0.6, 0.3))
	var a := building(world, source)
	var b := building(world, source)
	b.set_surface_override_material(0, source)
	b.set_instance_shader_parameter("blend_profile", Vector3(-0.2, 2.8, 0.12))
	var outside := building(root, source)
	var lamp := OmniLight3D.new()
	lamp.light_energy = 2.3
	lamp.light_volumetric_fog_energy = 0.45
	var lamp_state := [lamp.light_energy, lamp.light_volumetric_fog_energy]
	world.add_child(lamp)
	root.add_child(world)
	await frames()
	var entry = world.get_node("WorldEntry")
	entry.settings.building_atmosphere_enabled = true
	entry.settings.building_light_gain = 2.2
	entry.settings.fog_self_emission = 1.0
	entry.settings.mist_light_response = 0.28
	entry.settings.building_edge_softness_pixels = 2.5
	entry.settings.building_edge_blur_strength = 0.4
	entry.play(false)
	entry.set_process(false)
	var temporary := a.get_active_material(0) as ShaderMaterial
	check(temporary != source and temporary == b.get_active_material(0), "Entry copies each shared city material once, without editing its mesh")
	check(temporary.shader != CITY_SHADER and temporary.shader.get_shader_uniform_list().size() > 0, "Temporary building shader exposes valid native-fog material inputs")
	check(is_equal_approx(temporary.get_shader_parameter("emission_energy"), 0.15) and temporary.get_shader_parameter("emission_tint") == Color(1.0, 0.6, 0.3), "Existing light colors and emission regions survive the material switch")
	check(is_equal_approx(temporary.get_shader_parameter("entry_light_gain"), 2.2), "Only existing emissive surfaces receive the requested entry gain")
	check(outside.get_active_material(0) == source and a.mesh.surface_get_material(0) == source, "Entry leaves other scene instances and shared mesh resources untouched")
	check(b.get_instance_shader_parameter("blend_profile") == Vector3(-0.2, 2.8, 0.12), "Per-building lower-edge blending remains anchored to its original structure")
	check(is_equal_approx(entry._wisp_material.get_shader_parameter("light_response"), 0.28) and is_equal_approx(entry._soft_focus_material.get_shader_parameter("blur_radius_pixels"), 2.5), "Cloud lighting and silhouette blur keep separate controls")
	check(is_equal_approx(entry._soft_focus_material.get_shader_parameter("blur_strength"), 0.4) and entry._wisp_material.get_shader_parameter("edge_strength") == null, "Silhouette softness uses scene blur rather than extra edge fog")
	check(entry._soft_focus_material.render_priority < entry._wisp_material.render_priority and entry._soft_focus_material.shader.get_shader_uniform_list().size() > 0, "The valid blur pass runs before cloud sheets instead of repainting earlier fog layers")
	check(is_equal_approx(entry._volume_material.get_shader_parameter("self_emission"), 1.0) and is_equal_approx(entry._bank_materials[0].get_shader_parameter("self_emission"), 1.0), "Main fog cover and local banks share the restrained self-emission")
	entry._apply(0.98)
	check(temporary.get_shader_parameter("entry_weight") < 0.05 and entry._wisp_material.get_shader_parameter("opacity") < entry.settings.fog_opacity, "Building emphasis and mist recede before the camera handoff")
	check(entry._soft_focus_material.get_shader_parameter("clear_radius") > 0.0 and entry._soft_focus_material.get_shader_parameter("fog_weight") < 1.0, "Silhouette blur recedes with the real cloud opening and final fog fade")
	check([lamp.light_energy, lamp.light_volumetric_fog_energy] == lamp_state, "Real lamp energies and gameplay lighting stay unchanged")
	entry.skip()
	check(a.get_surface_override_material(0) == null and b.get_surface_override_material(0) == source and a.get_active_material(0) == source, "Skip restores both absent and authored surface overrides exactly")
	check(entry._soft_focus == null and entry._soft_focus_material == null, "Skip clears the temporary blur node and material references")
	check(source.shader == CITY_SHADER and source.get_shader_parameter("emission_energy") == 0.15, "Shared city materials remain unchanged after the entry")
	entry.settings.building_atmosphere_enabled = false
	entry.play(false)
	entry.set_process(false)
	check(a.get_active_material(0) == source and is_zero_approx(entry._wisp_material.get_shader_parameter("light_response")) and entry._soft_focus == null, "Disabling the atmosphere restores the old building and wisp behavior")
	entry.skip()
	entry.settings.building_atmosphere_enabled = true
	entry.settings.building_edge_blur_strength = 0.0
	entry.play(false)
	entry.set_process(false)
	check(entry._soft_focus == null and entry._wisp_material.get_shader_parameter("light_response") > 0.0, "Zero blur strength removes its render pass while retaining light-through fog")
	entry.skip()
	entry.settings.building_edge_blur_strength = 0.4
	entry.prewarm()
	entry.set_process(false)
	for draw in 8: entry._on_render_frame()
	check(not entry.active and a.get_active_material(0) == source and b.get_surface_override_material(0) == source, "Hidden prewarming restores the exact original building materials")
	entry.play(false)
	entry.set_process(false)
	b.free()
	entry.free()
	check(a.get_active_material(0) == source, "Removing the intro midway restores surviving surfaces even if another building was freed")
	outside.free()
	world.free()
	await frames()

func formal_lighting_checks() -> void:
	var settings = load("res://data/visual/world_entry.tres")
	if not "building_edge_blur_strength" in settings: return
	check(settings.building_atmosphere_enabled and settings.fog_self_emission < SETTINGS.new().fog_self_emission, "World explicitly enables light-through fog with less neutral self-light")
	var world := fixture()
	world.get_node("WorldEntry").settings = settings
	world.get_node("WorldEntry").owner = world
	var catalog = load("res://addons/parameter_hub/catalog.gd").new()
	var entries: Array[Dictionary] = catalog.collect(world)
	for property in ["building_atmosphere_enabled", "building_light_gain", "mist_light_response", "building_edge_softness_pixels", "building_edge_blur_strength", "fog_self_emission", "cloud_bank_scale", "cloud_bank_density_ratio", "wisp_opacity", "wisp_depth_bulge"]:
		check(entries.any(func(item): return item.property == property and item.category == "视觉" and item.common), "Entry atmosphere control is indexed: " + property)
	world.free()

func world_lighting_checks() -> void:
	var world: Node = load("res://scenes/world/world.tscn").instantiate()
	quiet_map(world)
	var entry = world.get_node("WorldEntry")
	entry.preview_on_direct_run = false
	root.add_child(world)
	await frames(6)
	var original: Array[Array] = []
	for mesh: MeshInstance3D in world.get_node("CitySurroundings").find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			original.append([mesh, surface, mesh.get_active_material(surface)])
	check(entry.play(false), "The actual World can start its building-light entry")
	entry.set_process(false)
	check(not original.is_empty() and entry._building_surfaces.size() == original.size() and entry._building_materials.size() <= 16, "All actual city surfaces participate through their small shared material set")
	check(entry._effects.find_children("EntrySilhouetteBlur", "MeshInstance3D", true, false).size() == 1, "World uses a single silhouette blur pass")
	var defaults := SETTINGS.new()
	check(entry.settings.cloud_bank_scale < defaults.cloud_bank_scale and entry.settings.cloud_bank_density_ratio < defaults.cloud_bank_density_ratio, "World separates local cloud banks instead of stacking full-size dense volumes")
	check(entry.settings.wisp_opacity < 0.4 and defaults.wisp_opacity == 1.0, "World keeps cloud sheets subordinate to volumetric fog without changing other maps' sheet intensity")
	check(entry._fog_banks[0].size.is_equal_approx(Vector3(48, 32, 48) * entry.settings.cloud_bank_scale), "The local volume size follows the map's selected layer scale")
	var wisp: MeshInstance3D = entry._wisps[0]
	check(wisp.mesh.subdivide_width >= 4 and wisp.mesh.subdivide_depth >= 4 and entry._wisp_material.get_shader_parameter("depth_bulge") > 0.0, "Thin mist has enough geometry for a curved surface rather than an undeformed quad")
	check(is_equal_approx(entry._wisp_material.get_shader_parameter("opacity"), entry.fog_amount * entry.settings.wisp_opacity), "The independent thin-mist control reaches the actual material")
	var density: float = entry._bank_materials[0].get_shader_parameter("density")
	var bank_origin: Vector3 = entry._fog_banks[0].global_position
	entry._apply(0.86)
	check(is_equal_approx(entry._bank_materials[0].get_shader_parameter("density"), density) and entry._fog_banks[0].global_position.distance_to(bank_origin) > 5.0, "Layered fog retains real outward movement rather than fading every volume together")
	entry.advance(entry.settings.duration_seconds)
	check(original.all(func(item): return item[0].get_active_material(item[1]) == item[2]), "Normal completion restores every actual city surface exactly")
	check(entry._building_surfaces.is_empty() and entry._building_materials.is_empty() and not entry.is_processing(), "Normal gameplay retains no entry material work")
	world.free()
	await frames()

func run() -> void:
	await lighting_checks()
	formal_lighting_checks()
	await world_lighting_checks()
	await frames()
	print(JSON.stringify({"suite":"entry_mist_lighting", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
