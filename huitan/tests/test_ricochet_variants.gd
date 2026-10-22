extends SceneTree

var checks := 0
var failures := 0
var world: Node3D

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

func ray(prop: RicochetProp, start: Vector3, end: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(prop.to_global(start), prop.to_global(end), 1)
	return world.get_world_3d().direct_space_state.intersect_ray(query)

func is_surface(hit: Dictionary, prop: RicochetProp) -> bool:
	return hit.get("collider") == prop._collision_body

func normal(prop: RicochetProp, hit: Dictionary) -> Vector3:
	return prop.global_basis.inverse() * hit.get("normal", Vector3.ZERO)

func probe(prop: RicochetProp, point: Vector3) -> Array[Dictionary]:
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY, prop.to_global(point))
	return world.get_world_3d().direct_space_state.intersect_shape(query)

func run() -> void:
	var preview: Node3D = load("res://scenes/previews/ricochet_variants_preview.tscn").instantiate()
	preview.get_node("CurrentWorld/MapEffects/BGM").music_enabled = false
	root.add_child(preview)
	current_scene = preview
	await settle()
	world = preview.get_node("CurrentWorld")
	var samples: Node3D = world.get_node("RicochetVariantSamples")
	var terrain: Terrain = world.get_node("Homestead")
	var dressing: Node3D = world.get_node("GroundDressing")
	var terrain_mesh := terrain._generated
	var dressing_mesh: Node3D = dressing._generated
	var paint_rid := terrain._map_texture.get_rid()
	var terrain_data := terrain.data.to_image().get_data()
	var props: Array[RicochetProp] = []
	var kinds := {}
	for node in samples.get_children():
		if not node is RicochetProp: continue
		props.append(node)
		kinds[Vector2i(node.kind, node.layout_variant)] = true
		check(node.is_in_group("ricochet_obstacles") and node._collision_body.is_in_group("ricochet_surfaces"), "Reflection tags: " + node.name)
		check(node._collision_body.collision_layer == 1 and not node.is_processing(), "World collision and no idle processing: " + node.name)
	check(props.size() == 12 and kinds.size() == 12, "Two functional variants of all six families")
	check(not world.get_node("LoadoutUI").save_enabled and not world.has_node("Farming"), "Preview cannot write player progression or planting")
	var fence: RicochetProp = samples.get_node("FencePassage")
	check(is_equal_approx(fence.passage_width, 2.2), "Opening defaults to a 2.2-metre passage")
	check(ray(fence, Vector3(0, 0.1, 1), Vector3(0, 0.1, -1)).is_empty(), "No hidden foundation across passage at ground height")
	var passage_clear := true
	for z: float in [-0.8, -0.4, 0.0, 0.4, 0.8]:
		for x: float in [-0.7, 0.0, 0.7]:
			passage_clear = passage_clear and probe(fence, Vector3(x, 0.55, z)).is_empty()
	check(passage_clear, "Player-width sphere traverses the opening including both sides")
	check(is_surface(ray(fence, Vector3(2, 0.2, 1), Vector3(2, 0.2, -1)), fence), "Side foundation remains a physical obstacle")
	var angled: RicochetProp = samples.get_node("AngledWall")
	var yaw := -deg_to_rad(angled.turn_angle_degrees)
	var basis := Basis(Vector3.UP, yaw)
	var point := Vector3(0, 0.7, -angled.dimensions.z * 0.2) + basis * Vector3(angled.dimensions.x * 0.25, 0, 0)
	var expected := basis * Vector3.BACK
	var hit := ray(angled, point + expected * 2, point - expected * 0.2)
	check(is_surface(hit, angled) and normal(angled, hit).dot(expected) > 0.99, "Angled wall supplies the actual 45-degree face normal")
	check(absf(Vector3.FORWARD.bounce(normal(angled, hit)).x) > 0.99, "Diagonal face redirects a forward projectile sideways")
	var folded: RicochetProp = samples.get_node("FoldedFence")
	var folded_normals: Array[Vector3] = []
	for side: float in [-1.0, 1.0]:
		var angle := side * deg_to_rad(folded.turn_angle_degrees) * 0.5
		var section_basis := Basis(Vector3.UP, angle)
		point = section_basis * Vector3(side * folded.dimensions.x * 0.25, 0.2, 0)
		expected = section_basis * Vector3.BACK
		hit = ray(folded, point + expected, point - expected * 0.2)
		check(is_surface(hit, folded), "Folded fence section has matching rotated collision")
		folded_normals.append(normal(folded, hit))
	check(is_equal_approx(folded_normals[0].dot(folded_normals[1]), cos(deg_to_rad(60.0))), "Fence sections differ by the configured 60 degrees")
	var crate: RicochetProp = samples.get_node("DiagonalCrate")
	hit = ray(crate, Vector3(0.25, 0.7, 2), Vector3(0.25, 0.7, 0))
	check(is_surface(hit, crate) and absf(normal(crate, hit).x) > 0.6, "Single crate exposes a diagonal solid face")
	check(samples.get_node("CrateRow")._collision_body.get_child_count() == 3, "Crate row consists of three separate rotated box surfaces")
	check(samples.get_node("SingleBarrel")._collision_body.get_child_count() == 3 and samples.get_node("BarrelRow")._collision_body.get_child_count() == 9, "Barrel variants keep tapered compound surfaces")
	var round_column: RicochetProp = samples.get_node("RoundPillar")
	var round_normals: Array[Vector3] = []
	for x: float in [0.08, 0.2]:
		hit = ray(round_column, Vector3(x, 0.7, 1), Vector3(x, 0.7, -0.1))
		check(is_surface(hit, round_column), "Round pillar receives a physical ray")
		round_normals.append(normal(round_column, hit))
	check(round_normals[0].distance_to(round_normals[1]) > 0.2, "Round pillar normals vary radially with impact position")
	var octagon: RicochetProp = samples.get_node("OctagonalPillar")
	var facet_normals: Array[Vector3] = []
	for x: float in [0.06, 0.15]:
		hit = ray(octagon, Vector3(x, 0.7, 1), Vector3(x, 0.7, -0.1))
		check(is_surface(hit, octagon), "Octagonal pillar receives a physical ray")
		facet_normals.append(normal(octagon, hit))
	check(facet_normals[0].dot(facet_normals[1]) > 0.999 and absf(facet_normals[0].x) > 0.3, "Octagonal collider preserves its planar facet instead of an enclosing cylinder")
	var pocket: RicochetProp = samples.get_node("UWall")
	check(probe(pocket, Vector3(0, 0.7, 0)).is_empty(), "U wall has an unfilled walkable interior")
	check(ray(pocket, Vector3(0, 0.7, 0), Vector3(0, 0.7, 2.1)).is_empty(), "U wall front stays open")
	for direction in [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD]:
		check(is_surface(ray(pocket, Vector3(0, 0.7, 0), Vector3(0, 0.7, 0) + direction * 2.4), pocket), "U wall exposes an interior reflection face")
	var incoming := Vector3(-1, 0, -0.75).normalized()
	var origin := Vector3(0, 0.7, 0)
	var reflected_faces := 0
	for bounce_index in 3:
		hit = ray(pocket, origin, origin + incoming * 12)
		if not is_surface(hit, pocket): break
		reflected_faces += 1
		var surface_normal := normal(pocket, hit)
		incoming = incoming.bounce(surface_normal)
		origin = pocket.to_local(hit.position) + surface_normal * 0.01
	check(reflected_faces == 3 and incoming.z > 0, "U pocket supports three successive reflections toward its open front")
	check(not is_surface(ray(pocket, origin, origin + incoming * 8), pocket), "Reflected path exits the U pocket through its opening")
	var obtuse: RicochetProp = samples.get_node("ObtuseWall")
	var side_shape: CollisionShape3D = obtuse._collision_body.get_child(3)
	expected = side_shape.basis.z
	hit = ray(obtuse, side_shape.position + expected * 1.3, side_shape.position - expected * 0.2)
	check(is_surface(hit, obtuse) and absf(normal(obtuse, hit).dot(Vector3.BACK) - cos(deg_to_rad(45.0))) < 0.01, "135-degree interior corner supplies its diagonal wall normal")
	check(probe(obtuse, Vector3(0, 0.7, 0)).is_empty(), "Obtuse corner interior is not filled with an invisible hull")
	var selected_geometry := fence._generated
	var untouched_geometry := folded._generated
	fence.passage_width = 2.8
	await settle()
	check(fence._generated != selected_geometry and folded._generated == untouched_geometry, "Gap edit rebuilds only the selected obstacle")
	check(probe(fence, Vector3(1.0, 0.55, 0)).is_empty(), "Widened opening updates physical clearance")
	selected_geometry = angled._generated
	angled.position += Vector3(0, 0, 0.5)
	angled.rotation_degrees.y = 25
	await settle()
	basis = Basis(Vector3.UP, -deg_to_rad(angled.turn_angle_degrees))
	point = Vector3(0, 0.7, -angled.dimensions.z * 0.2) + basis * Vector3(angled.dimensions.x * 0.25, 0, 0)
	expected = basis * Vector3.BACK
	hit = ray(angled, point + expected * 2, point - expected * 0.2)
	check(angled._generated == selected_geometry and is_surface(hit, angled), "Moving and rotating a variant carries geometry and collider without rebuilding")
	check(normal(angled, hit).dot(expected) > 0.99, "World-space reflection normal follows root rotation")
	var holder := Node3D.new()
	root.add_child(holder)
	for original in props:
		var saved: RicochetProp = load(original.scene_file_path).instantiate()
		saved.position = Vector3(4, 0.8, 6)
		saved.rotation_degrees.y = 35
		if saved.kind == RicochetProp.Kind.IRON_FENCE and saved.layout_variant == 1: saved.passage_width = 2.8
		if saved.kind == RicochetProp.Kind.LOW_WALL and saved.layout_variant == 2: saved.turn_angle_degrees = 60
		holder.add_child(saved)
		saved.owner = holder
	await settle()
	var packed := PackedScene.new()
	check(packed.pack(holder) == OK and packed.get_state().get_node_count() == 13, "Saving persists only the twelve prefab roots")
	var restored := packed.instantiate()
	root.add_child(restored)
	await settle()
	for saved: RicochetProp in restored.get_children():
		check(saved.has_node("Geometry/RicochetCollision") and saved.get_child_count() == 1 and saved.layout_variant > 0 and saved.position.is_equal_approx(Vector3(4, 0.8, 6)), "Reload retains variant and placement: " + saved.name)
	check(is_equal_approx(restored.get_node("FencePassage").passage_width, 2.8) and is_equal_approx(restored.get_node("AngledWall").turn_angle_degrees, 60), "Custom gap and deflection angle survive saving")
	check(terrain._generated == terrain_mesh and dressing._generated == dressing_mesh and terrain._map_texture.get_rid() == paint_rid, "Placing and editing props do not rebuild terrain or foliage")
	check(terrain.data.to_image().get_data() == terrain_data, "Hand-painted map remains unchanged")
	print("Ricochet variants: ", checks, " checks, ", failures, " failures")
	preview.queue_free()
	holder.queue_free()
	restored.queue_free()
	for frame in 3: await process_frame
	quit(1 if failures else 0)
