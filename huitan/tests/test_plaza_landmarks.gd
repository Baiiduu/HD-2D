extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle() -> void:
	for frame in 8: await process_frame
	await physics_frame

func run() -> void:
	var preview: Node3D = load("res://scenes/previews/plaza_landmarks_preview.tscn").instantiate()
	preview.get_node("CurrentWorld/MapEffects/BGM").music_enabled = false
	root.add_child(preview)
	current_scene = preview
	await settle()
	var world: Node3D = preview.get_node("CurrentWorld")
	var samples: Node3D = world.get_node("LandmarkSamples")
	var terrain: Terrain = world.get_node("Homestead")
	var dressing: Node3D = world.get_node("GroundDressing")
	var terrain_geometry := terrain._generated
	var dressing_geometry: Node3D = dressing._generated
	var terrain_data := terrain.data.to_image().get_data()
	var lamp: PlazaStreetlamp = samples.get_node("StreetlampLeft")
	var other: PlazaStreetlamp = samples.get_node("StreetlampRight")
	var monument: ArmillaryMonument = samples.get_node("ArmillaryMonument")
	var state: SceneState = (load("res://scenes/world/world.tscn") as PackedScene).get_state()
	for index in state.get_node_count():
		if state.get_node_name(index) != &"TreePlanter": continue
		for property in state.get_node_property_count(index):
			if state.get_node_property_name(index, property) == &"transform":
				check(world.get_node("TreePlanter").transform == state.get_node_property_value(index, property), "User-placed tree is preserved beside separately named preview samples")
	var lamp_geometry := lamp._generated
	var other_geometry := other._generated
	var monument_geometry := monument._generated
	check(lamp._heads.size() == 2 and other._heads.size() == 2, "Two independently assembled lantern heads")
	var head := lamp._heads[0]
	check(head.is_in_group("environment_lanterns") and head.get_node("Dust").is_in_group("street_light_dust"), "Reuses common lantern and golden-particle configuration")
	check(head.get("beam_strength") == 0.0 and not head.get_node("Beam").visible, "No intrusive ground beam")
	check(head.get_node("WaterLight").light_cull_mask == Terrain.WATER_LIGHT_LAYER, "Dedicated water reflection light retained")
	check((head.get_node("Lamp").mesh as BoxMesh).size == Vector3(0.25, 0.39, 0.25), "Square lantern glass sized to frame")
	lamp.light_energy = 1.3
	lamp.light_color = Color(1, 0.65, 0.35)
	await settle()
	check(lamp._generated == lamp_geometry, "Lighting changes do not rebuild lamp mesh")
	check(is_equal_approx(head.get_node("Cone").light_energy, 1.3) and head.get_node("Light").light_color.is_equal_approx(lamp.light_color), "Inspector lighting parameters reach real lights")
	check(other._generated == other_geometry and other.light_energy == 2.1, "Second lamp's parameters remain independent")
	lamp.light_enabled = false
	await settle()
	check(head.get_node("Cone").light_energy == 0.0 and head.get_node("WaterLight").light_energy == 0.0, "Disabled fixture no longer illuminates land or water")
	lamp.light_enabled = true
	lamp.position += Vector3(1.6, 0, 1.6)
	lamp.rotation_degrees.y = 90.0
	monument.position += Vector3(8, 0, 3)
	monument.rotation_degrees.y = 35.0
	await settle()
	check(lamp._generated == lamp_geometry and monument._generated == monument_geometry, "Moving and rotating do not rebuild assemblies")
	for prop: PlazaProp in [lamp, monument]:
		var body: StaticBody3D = prop.get_node("Geometry/LampCollision" if prop == lamp else "Geometry/MonumentCollision")
		var query := PhysicsRayQueryParameters3D.create(prop.global_position + Vector3(0, 5, 0), prop.global_position + Vector3(0, -0.1, 0), 1)
		check(world.get_world_3d().direct_space_state.intersect_ray(query).get("collider") == body, "Moved %s collider blocks at new position" % prop.name)
	check(monument.get_node("Geometry/Brass").mesh.get_aabb().size.x > monument.globe_radius * 2.0, "Orbit geometry surrounds a real 3D globe")
	check(monument._materials["globe"] != lamp._materials["metal"], "Metal shading parameters are per prop")
	monument.flowers_enabled = false
	monument.garden_lights_enabled = false
	await settle()
	check(monument._plants.is_empty() and not monument.is_processing(), "No idle vegetation work when flowers are disabled")
	check(not monument.has_node("Geometry/GardenLeft") and not monument.has_node("Geometry/GardenRight"), "Garden light switch removes only local lights")
	var holder := Node3D.new()
	root.add_child(holder)
	for path in ["res://scenes/buildings/plaza_streetlamp.tscn", "res://scenes/buildings/armillary_monument.tscn"]:
		var prop: PlazaProp = load(path).instantiate()
		prop.position = Vector3(4, 0.8, 6)
		prop.rotation_degrees.y = 45.0
		holder.add_child(prop)
		prop.owner = holder
	await settle()
	var packed := PackedScene.new()
	check(packed.pack(holder) == OK and packed.get_state().get_node_count() == 3, "Saving stores prefab roots, not generated meshes")
	var restored := packed.instantiate()
	root.add_child(restored)
	await settle()
	for prop: PlazaProp in restored.get_children():
		check(prop.get_child_count() == 1 and prop.has_node("Geometry") and prop.position == Vector3(4, 0.8, 6), "Saved %s placement reloads with one assembly" % prop.name)
	check(terrain._generated == terrain_geometry and dressing._generated == dressing_geometry, "No full terrain or vegetation rebuild")
	check(terrain.data.to_image().get_data() == terrain_data, "Terrain painting preserved")
	lamp.collision_enabled = false
	monument.collision_enabled = false
	await settle()
	check(not lamp.has_node("Geometry/LampCollision") and not monument.has_node("Geometry/MonumentCollision"), "Collision switches remove corresponding bodies")
	print("Plaza landmarks: ", checks, " checks, ", failures, " failures")
	preview.queue_free()
	holder.queue_free()
	restored.queue_free()
	for frame in 3: await process_frame
	quit(1 if failures else 0)
