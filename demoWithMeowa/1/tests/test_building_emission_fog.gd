extends "res://tests/test_world_entry.gd"

func glow_surface(parent: Node, material: Material, point: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = QuadMesh.new()
	mesh.mesh.material = material
	mesh.position = point
	parent.add_child(mesh)
	return mesh

func emission_checks() -> void:
	var rules = SETTINGS.new()
	check("emission_fog_enabled" in rules, "Entry offers material-driven building fog scattering")
	if not "emission_fog_enabled" in rules: return
	check(not rules.emission_fog_enabled, "Other maps retain their existing fog-light configuration")
	var world := fixture()
	var building := Node3D.new()
	building.add_to_group(&"occlusion_buildings")
	world.add_child(building)
	var warm := StandardMaterial3D.new()
	warm.emission_enabled = true
	warm.emission = Color(1, 0.4, 0.1)
	warm.emission_energy_multiplier = 2.0
	var cool := StandardMaterial3D.new()
	cool.emission_enabled = true
	cool.emission = Color(0.1, 0.5, 1.0)
	cool.emission_energy_multiplier = 0.0
	var warm_mesh := glow_surface(building, warm, Vector3(0, 2, 0))
	glow_surface(building, cool, Vector3(3, 2, 0))
	root.add_child(world)
	await frames()
	var entry = world.get_node("WorldEntry")
	entry.settings.emission_fog_enabled = true
	entry.settings.emission_fog_max_lights = 2
	entry.play(false)
	entry.set_process(false)
	entry._emission_fog.refresh(entry.camera, entry.player, true)
	entry._emission_fog.apply_weight(1.0)
	var lights: Array = entry._emission_fog._lights
	var active: Array = lights.filter(func(light): return light.visible)
	check(active.size() == 1, "Only the independently enabled emissive surface scatters into entry fog")
	if not active.is_empty():
		var light: OmniLight3D = active[0]
		check(light.light_color.r > light.light_color.b * 3.0 and light.light_energy > 0.0, "Fog receives the material's warm emission color and strength")
		check(light.light_cull_mask == 0 and light.light_indirect_energy == 0.0 and not light.shadow_enabled, "Temporary scattering cannot illuminate geometry, reflections or GI")
		var energy := light.light_energy
		warm.emission_energy_multiplier = 1.0
		entry._emission_fog.refresh(entry.camera, entry.player, true)
		entry._emission_fog.apply_weight(1.0)
		check(is_equal_approx(light.light_energy, energy * 0.5), "Building emission strength scales fog scattering without a brightness threshold")
	warm.emission_energy_multiplier = 0.0
	cool.emission_energy_multiplier = 3.0
	entry._emission_fog.refresh(entry.camera, entry.player, true)
	entry._emission_fog.apply_weight(1.0)
	active = lights.filter(func(light): return light.visible)
	check(active.size() == 1 and active[0].light_color.b > active[0].light_color.r * 3.0, "Turning one source off and another on follows their independent controls")
	entry._emission_fog.apply_weight(0.0)
	check(lights.all(func(light): return not light.visible), "Cleared fog leaves no floating light halo")
	entry.skip()
	check(entry._emission_fog._lights.is_empty() and warm_mesh.get_active_material(0) == warm and warm.emission_energy_multiplier == 0.0 and cool.emission_energy_multiplier == 3.0, "Skipping removes scattering without restoring over the user's live emission changes")
	entry.prewarm()
	entry.set_process(false)
	for draw in 8: entry._on_render_frame()
	check(not entry.active and entry._emission_fog._lights.is_empty(), "Menu prewarming releases every temporary scattering light")
	entry.settings.emission_fog_enabled = false
	entry.play(false)
	entry.set_process(false)
	check(entry._emission_fog._lights.is_empty(), "Scattering can be disabled independently of cloud shapes and silhouette blur")
	entry.skip()
	world.free()
	await frames()

func run() -> void:
	await emission_checks()
	await texture_checks()
	await actual_building_checks()
	await actual_world_checks()
	await frames()
	print(JSON.stringify({"suite":"building_emission_fog", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)

func texture_checks() -> void:
	if not "emission_fog_enabled" in SETTINGS.new(): return
	var material := ORMMaterial3D.new()
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 2.0
	material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.9, 0.35, 0.05))
	material.emission_texture = ImageTexture.create_from_image(image)
	var world := fixture()
	var building := Node3D.new()
	building.add_to_group(&"occlusion_buildings")
	world.add_child(building)
	glow_surface(building, material, Vector3.ZERO)
	root.add_child(world)
	await frames()
	var entry = world.get_node("WorldEntry")
	entry.settings.emission_fog_enabled = true
	entry.settings.emission_fog_max_lights = 1
	entry.play(false)
	entry.set_process(false)
	entry._emission_fog.refresh(entry.camera, entry.player, true)
	entry._emission_fog.apply_weight(1.0)
	var light: OmniLight3D = entry._emission_fog._lights[0]
	check(light.visible and light.light_color.r > light.light_color.b * 5.0, "Emission texture supplies its real warm color to ORM materials")
	check(entry._emission_fog._lights.size() == 1, "Fog scattering obeys its light-pool budget")
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 20, 0.2)
	collider.shape = box
	wall.add_child(collider)
	world.add_child(wall)
	wall.global_position = entry.camera.global_position.lerp(light.global_position, 0.5)
	wall.look_at(light.global_position)
	for tick in 3: await physics_frame
	entry._emission_fog.refresh(entry.camera, entry.player, true)
	entry._emission_fog.apply_weight(1.0)
	check(not light.visible, "An actual opaque obstacle prevents an occluded emitter from producing a visible fog halo")
	entry.skip()
	wall.add_to_group(&"map_boundaries")
	entry.play(false)
	entry.set_process(false)
	entry._emission_fog.refresh(entry.camera, entry.player, true)
	entry._emission_fog.apply_weight(1.0)
	check(entry._emission_fog._lights[0].visible, "Invisible activity-boundary walls never block visual fog emission")
	entry.skip()
	world.free()
	await frames()

func actual_world_checks() -> void:
	if not "emission_fog_enabled" in SETTINGS.new(): return
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	quiet_map(world)
	var entry = world.get_node("WorldEntry")
	entry.preview_on_direct_run = false
	root.add_child(world)
	await frames(6)
	check(entry.settings.emission_fog_enabled, "World explicitly enables material-driven emission scattering")
	entry.play(false)
	entry.set_process(false)
	entry._emission_fog.refresh(entry.camera, entry.player, true)
	entry._emission_fog.apply_weight(1.0)
	check(entry._emission_fog._lights.size() <= entry.settings.emission_fog_max_lights and entry._emission_fog._lights.any(func(light): return light.visible), "Real World opening has visible material-driven fog lights within its budget")
	entry.advance(entry.settings.duration_seconds)
	check(not entry.active and entry._emission_fog._lights.is_empty(), "Normal World handoff removes every added fog scattering source")
	var catalog = load("res://addons/parameter_hub/catalog.gd").new()
	var entries: Array[Dictionary] = catalog.collect(world)
	for property in ["emission_fog_enabled", "emission_fog_strength", "emission_fog_radius", "emission_fog_max_lights"]:
		check(entries.any(func(item): return item.property == property and item.common and item.category == "视觉"), "Scattering control is indexed: " + property)
	world.free()
	await frames()

func actual_building_checks() -> void:
	if not "emission_fog_enabled" in SETTINGS.new(): return
	var world := fixture()
	var shop := load("res://scenes/buildings/convenience_24.tscn").instantiate() as Node3D
	world.add_child(shop)
	root.add_child(world)
	await frames()
	var entry = world.get_node("WorldEntry")
	entry.settings.emission_fog_enabled = true
	shop.window_energy = 4.0
	shop.sign_energy = 0.0
	entry.play(false)
	entry.set_process(false)
	entry._emission_fog.refresh(entry.camera, entry.player, true)
	entry._emission_fog.apply_weight(1.0)
	check(not entry._emission_fog._sources.is_empty(), "The actual convenience-store window/sign materials are discovered automatically")
	check(entry._emission_fog._lights.any(func(light): return light.visible), "The actual enabled store windows drive fog scattering")
	shop.window_energy = 0.0
	shop.sign_energy = 0.0
	entry._emission_fog.refresh(entry.camera, entry.player, true)
	entry._emission_fog.apply_weight(1.0)
	check(entry._emission_fog._lights.all(func(light): return not light.visible), "The store's original independent switches fully remove its fog scattering")
	entry.skip()
	check(shop.window_energy == 0.0 and shop.sign_energy == 0.0, "Finishing entry preserves the store's own control values")
	world.free()
	await frames()
