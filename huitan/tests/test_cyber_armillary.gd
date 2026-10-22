extends SceneTree

const SCENE := "res://scenes/buildings/cyber_armillary_monument.tscn"
var failures := 0
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	if not ResourceLoader.exists(SCENE):
		push_error("Approved cyber armillary scene has not been built")
		quit(1)
		return
	run.call_deferred()

func run() -> void:
	var node := load(SCENE).instantiate() as Node3D
	root.add_child(node)
	var bounds := AABB()
	var first := true
	var materials := {}
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var box := mesh.transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		for surface in mesh.mesh.get_surface_count():
			materials[mesh.get_active_material(surface)] = true
			var arrays := mesh.mesh.surface_get_arrays(surface)
			for coord: Vector2 in arrays[Mesh.ARRAY_TEX_UV]:
				check(coord.x >= 0 and coord.y >= 0 and coord.x <= 1 and coord.y <= 1, "UV remains inside the shared atlas")
	# The existing octagon has a 3.05 m circumradius and a 22.5 degree vertex offset.
	var span := 6.1 * cos(PI / 8.0)
	check(is_equal_approx(bounds.size.x, span) and is_equal_approx(bounds.size.z, span), "Local footprint matches the existing 0.5 scale World slot")
	check(bounds.end.y < 5.4 and bounds.end.y > 4.8 and bounds.position.y >= -0.001, "At World scale the landmark stays below 2.7m and its foundation touches ground")
	check(materials.size() == 2, "The native shared atlas and high-resolution globe use two opaque materials")
	check(node.get_meta("orbit_count") == 2, "Only two full orbit rails")
	check(node.is_in_group(&"ricochet_obstacles"), "The new static asset retains building bounce-animation recognition")
	check(node.find_children("*", "Light3D", true, false).is_empty(), "No new local lights")
	check(node.find_children("*", "GPUParticles3D", true, false).is_empty(), "No particles or flower effects")
	check(node.get_script() == null, "Baked static landmark needs no per-frame script")
	var material := node.get_node("Model/Base").get_active_material(0) as ShaderMaterial
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.name != &"Globe":
			check(mesh.get_active_material(0) == material, "Non-globe parts retain their shared material: " + mesh.name)
	for key in ["albedo_atlas", "orm_atlas"]:
		var texture: Texture2D = material.get_shader_parameter(key)
		check(texture != null and texture.get_size() == Vector2(512,512), "Native 512px shared " + key)
	var properties := (material.get_shader_parameter("orm_atlas") as Texture2D).get_image()
	if properties.is_compressed(): properties.decompress()
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/cyber_armillary/uv_layout.json"))
	var globe: MeshInstance3D = node.get_node("Model/Globe")
	var globe_material := globe.get_active_material(0) as ShaderMaterial
	check(globe_material != material and globe_material.shader.resource_path == "res://shaders/environment/cyber_armillary_globe.gdshader", "Only the sphere receives the aurora surface")
	var surface: Dictionary = layout.globe_surface
	var globe_color: Texture2D = globe_material.get_shader_parameter("albedo_atlas")
	var globe_properties: Texture2D = globe_material.get_shader_parameter("orm_atlas")
	check(globe_color.get_size() == Vector2(surface.size[0], surface.size[1]), "Native high-resolution globe color matches its recorded crop")
	check(globe_color.get_width() == globe_color.get_height() * 2 and globe_color.get_width() >= 512, "The complete globe uses a higher-resolution 2:1 unwrap")
	check(globe_properties.get_size() == globe_color.get_size(), "Globe color, roughness and emission share the same native mapping")
	var image := globe_color.get_image()
	var source := Image.load_from_file("res://assets/models/cyber_armillary/" + surface.source)
	var crop: Array = surface.native_crop
	var original := source.get_region(Rect2i(crop[0], crop[1], crop[2], crop[3]))
	original.convert(image.get_format())
	check(image.get_data() == original.get_data(), "The installed color is a native crop of Meowa output with no resampling or repainting")
	var uv_rect: Vector4 = globe_material.get_shader_parameter("original_uv_rect")
	var coords: PackedVector2Array = globe.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var uv_min := Vector2.ONE
	var uv_max := Vector2.ZERO
	for coord in coords:
		var mapped := (coord - Vector2(uv_rect.x, uv_rect.y)) / Vector2(uv_rect.z, uv_rect.w)
		uv_min = uv_min.min(mapped)
		uv_max = uv_max.max(mapped)
	check(uv_min.is_equal_approx(Vector2.ZERO) and uv_max.is_equal_approx(Vector2.ONE), "The untouched original mesh UVs cover the whole new surface")
	var globe_finish := globe_properties.get_image()
	var dark := 0
	var luminous := 0
	var twinkling := 0
	var flowing := 0
	var stars_pinned := true
	for y in range(0, globe_finish.get_height(), 8):
		for x in range(0, globe_finish.get_width(), 8):
			var pixel := globe_finish.get_pixel(x, y)
			if is_zero_approx(pixel.a): dark += 1
			else: luminous += 1
			if pixel.r > 0.0:
				twinkling += 1
				stars_pinned = stars_pinned and is_zero_approx(pixel.b)
			if pixel.b > 0.0: flowing += 1
	check(dark > 0 and luminous > 0, "Star and aurora emission is selective, with unlit dark areas")
	check(twinkling > 0 and flowing > 0, "The existing packed property texture also contains star phases and aurora motion")
	check(stars_pinned, "Twinkling star texels stay outside the flow mask")
	check(globe_finish.get_pixel(0, 0).b == 0.0, "The dark polar cap stays outside the flow mask")
	for key in ["base_top", "stone_edge"]:
		var rect: Array = layout.regions[key]
		var finish := properties.get_pixel(rect[0] + rect[2] / 2, rect[1] + rect[3] / 2)
		if key == "base_top":
			check(finish.b >= 0.6, "Recessed titanium panels retain a metal finish")
			check(finish.g >= 0.55 and finish.g <= 0.75, "Broad top panels have the approved restrained matte reflections")
		else:
			check(finish.b >= 0.8, "The narrow outer rim retains its metal finish")
			check(finish.g <= 0.4, "The narrow rim preserves its sharper metal reflection")
	var body := node.get_node("MonumentCollision") as StaticBody3D
	for part: CollisionShape3D in body.get_children():
		check(not String(part.get_meta("collision_surface", "")).is_empty(), "Real collision has surface semantics: " + part.name)
	for i in 3: await physics_frame
	for label: String in ["OrbitA", "OrbitB"]:
		var ring: MeshInstance3D = node.get_node("Model/" + label)
		var arrays := ring.mesh.surface_get_arrays(0)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var center := (points[0] + points[1] + points[2]) / 3.0
		var normal := (normals[0] + normals[1] + normals[2]).normalized()
		var query := PhysicsRayQueryParameters3D.create(center + normal * 0.12, center - normal * 0.12, 1)
		var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty(), "Ray hits the actual visible outer face of " + label)
		if not hit.is_empty():
			var part := body.shape_owner_get_owner(body.shape_find_owner(hit.shape)) as Node
			check(part.name == label, "Orbit contact uses its own triangle collider")
	for height in [0.2, 0.44]:
		var query := PhysicsRayQueryParameters3D.create(Vector3(0,height,4), Vector3(0,height,2), 1)
		var hit := body.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty(), "Base has no old empty flower-bed collision gap")
		if not hit.is_empty():
			var actual := hit.position.z as float
			check(absf(actual - (3.05 if height > 0.4 else 3.0) * cos(PI/8.0)) < 0.02, "Visible octagon and ricochet boundary coincide")
			var part := body.shape_owner_get_owner(body.shape_find_owner(hit.shape)) as Node
			check(part.get_meta("collision_surface") == &"metal", "Both base wall and top cap retain metal contact semantics")
	var world := (load("res://scenes/world/world.tscn") as PackedScene).get_state()
	var linked := false
	for i in world.get_node_count():
		if String(world.get_node_path(i)).trim_prefix("./") != "WorldDetails/BattleCourts/ArmillaryMonument": continue
		linked = world.get_node_instance(i).resource_path == SCENE
		for j in world.get_node_property_count(i):
			if world.get_node_property_name(i,j) != &"transform": continue
			var saved: Transform3D = world.get_node_property_value(i,j)
			check(saved.basis.get_scale().is_equal_approx(Vector3.ONE * 0.5), "World keeps the original 0.5 instance scale")
			check(saved.origin.distance_to(Vector3(-0.0009602308,0,44.78542)) < 0.001, "World keeps the original landmark position")
	check(linked, "The formal map references the completed independent asset")
	node.queue_free()
	await process_frame
	print("Cyber armillary: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
