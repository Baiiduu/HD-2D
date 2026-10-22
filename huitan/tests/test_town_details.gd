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

func ray(prop: TownDetailProp, start: Vector3, end: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(prop.to_global(start), prop.to_global(end), 1)
	return world.get_world_3d().direct_space_state.intersect_ray(query)

func is_surface(hit: Dictionary, prop: TownDetailProp) -> bool:
	return hit.get("collider") == prop._collision_body

func probe(prop: TownDetailProp, point: Vector3, radius: float) -> Array[Dictionary]:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY, prop.to_global(point))
	return world.get_world_3d().direct_space_state.intersect_shape(query)

func run() -> void:
	var preview: Node3D = load("res://scenes/previews/town_details_preview.tscn").instantiate()
	preview.get_node("CurrentWorld/MapEffects/BGM").music_enabled = false
	root.add_child(preview)
	current_scene = preview
	await settle()
	world = preview.get_node("CurrentWorld")
	var samples: Node3D = world.get_node("TownDetailSamples")
	var terrain: Terrain = world.get_node("Homestead")
	var dressing: Node3D = world.get_node("GroundDressing")
	var ground_mesh := terrain._generated
	var dressing_mesh: Node3D = dressing._generated
	var paint_rid := terrain._map_texture.get_rid()
	var paint_data := terrain.data.to_image().get_data()
	var props: Array[TownDetailProp] = []
	var kinds := {}
	for node in samples.get_children():
		if not node is TownDetailProp: continue
		props.append(node)
		kinds[node.detail_kind] = true
		check(node._collision_body.collision_layer == 1 and node.is_in_group("ricochet_obstacles") and node._collision_body.is_in_group("ricochet_surfaces"), "Shared collision and bounce tags: " + node.name)
		var leafy: bool = node.detail_kind in [TownDetailProp.DetailKind.FLOWER_CART, TownDetailProp.DetailKind.FLOWER_POT]
		check(node.is_processing() == leafy, "Only flower props process weather: " + node.name)
	check(props.size() == 8 and kinds.size() == 8, "Eight distinct new kinds")
	check(not world.get_node("LoadoutUI").save_enabled and not world.has_node("Farming"), "Preview does not modify progression or planting")
	var bench: TownDetailProp = samples.get_node("ParkBench")
	check(ray(bench, Vector3(0, 0.23, 1), Vector3(0, 0.23, -1)).is_empty(), "Projectile can pass under the bench between its legs")
	check(is_surface(ray(bench, Vector3(0, 1.14, 1), Vector3(0, 1.14, -1)), bench), "Bench back slat exposes a physical face")
	check(ray(bench, Vector3(0, 0.887, 1), Vector3(0, 0.887, -1)).is_empty(), "Visible backrest gap has no invisible enclosing box")
	check(is_surface(ray(bench, Vector3(0, 2, 0), Vector3(0, 0.3, 0)), bench), "Seat slats receive downward projectiles")
	var cart: TownDetailProp = samples.get_node("FlowerCart")
	check(is_surface(ray(cart, Vector3(0, 0.9, 1.8), Vector3(0, 0.9, 0)), cart), "Flower cart front wall is solid")
	check(ray(cart, Vector3(0, 0.35, 1.8), Vector3(0, 0.35, -1)).is_empty(), "Cart underside stays open between stands and wheels")
	var hollow_wheels := 0
	for shape_node: CollisionShape3D in cart._collision_body.get_children():
		if shape_node.shape is ConcavePolygonShape3D: hollow_wheels += 1
	check(hollow_wheels == 2, "Two hollow wheel rims collide against their exact mesh surfaces")
	check(cart._plants.size() == 4, "Flower cart reuses four native plant materials")
	for material in cart._plants: check(material.get_shader_parameter("stable_shadows") == true, "Flowers retain soft shadows independent of camera orientation")
	var board: TownDetailProp = samples.get_node("NoticeBoard")
	var hit := ray(board, Vector3(0, 1.4, 1), Vector3(0, 1.4, -1))
	check(is_surface(hit, board) and absf(hit.get("normal", Vector3.ZERO).z) > 0.99, "Notice board exposes a flat reflection panel")
	check(ray(board, Vector3(0, 0.4, 1), Vector3(0, 0.4, -1)).is_empty(), "Notice board leaves the space between posts open")
	var pot: TownDetailProp = samples.get_node("FlowerPot")
	hit = ray(pot, Vector3(0.2, 0.45, 1), Vector3(0.2, 0.45, 0))
	check(is_surface(hit, pot) and absf(hit.get("normal", Vector3.ZERO).x) > 0.25, "Tapered pottery supplies a curved/sloped normal")
	check(pot._collision_body.get_child(0).shape is ConvexPolygonShape3D and pot._collision_body.get_child(1).shape is ConcavePolygonShape3D, "Pot preserves tapered body and hollow rim")
	var basin: TownDetailProp = samples.get_node("WaterBasin")
	check(probe(basin, Vector3(0.4, 1.0, 0), 0.025).is_empty(), "Space over recessed water is not filled by a cylinder collider")
	check(is_surface(ray(basin, Vector3(0.8, 0.988, 0), Vector3(1.4, 0.988, 0)), basin), "Water basin rim receives a ray from inside its opening")
	check(basin._materials["water"].shader == TownDetailProp.BASIN_SHADER and not basin.is_processing(), "Basin surface animates on GPU without a frame-processing script")
	var bin: TownDetailProp = samples.get_node("LitterBin")
	check(probe(bin, Vector3(0, 0.65, 0), 0.1).is_empty(), "Bin has an open hollow center")
	var gap := Vector3(sin(PI / 16), 0, cos(PI / 16))
	check(ray(bin, Vector3(0, 0.805, 0) + gap * 0.8, Vector3(0, 0.805, 0)).is_empty(), "Thin projectiles can pass between actual bin slats")
	check(is_surface(ray(bin, Vector3(0, 0.805, 0.8), Vector3(0, 0.805, 0)), bin), "Visible bin slat remains solid")
	var pallet: TownDetailProp = samples.get_node("CargoPallet")
	check(pallet._collision_body.get_child_count() == 11, "Pallet runners, planks, crate and sack use separate matching shapes")
	check(is_surface(ray(pallet, Vector3(-0.4, 0.55, 2), Vector3(-0.4, 0.55, 0)), pallet), "Pallet cargo provides a usable physical face")
	var sacks: TownDetailProp = samples.get_node("SackPile")
	check(sacks._collision_body.get_child_count() == 6, "Three sacks keep separate body and neck shapes")
	hit = ray(sacks, Vector3(-0.46, 0.5, 1), Vector3(-0.46, 0.5, -0.5))
	check(is_surface(hit, sacks), "Cloth sack curved body receives a physical ray")
	var bench_geometry := bench._generated
	bench.position += Vector3(0, 0, 0.5)
	bench.rotation_degrees.y = 30
	await settle()
	hit = ray(bench, Vector3(0, 1.14, 1), Vector3(0, 1.14, -1))
	check(bench._generated == bench_geometry and is_surface(hit, bench) and absf(hit.get("normal", Vector3.ZERO).dot(bench.global_basis.z)) > 0.99, "Moving and rotating carry both mesh and reflection normal without rebuilding")
	var other_geometry := pot._generated
	bench.dimensions.x = 3.1
	await settle()
	check(bench._generated != bench_geometry and pot._generated == other_geometry, "Dimension edit only rebuilds the selected object")
	cart.flowers_enabled = false
	pot.flowers_enabled = false
	await settle()
	check(cart._plants.is_empty() and not cart.is_processing() and pot._plants.is_empty() and not pot.is_processing(), "Disabling flowers stops all weather updates on those props")
	var holder := Node3D.new()
	root.add_child(holder)
	for original in props:
		var saved: TownDetailProp = load(original.scene_file_path).instantiate()
		saved.position = Vector3(4, 0.8, 6)
		saved.rotation_degrees.y = 35
		saved.flowers_enabled = false
		holder.add_child(saved)
		saved.owner = holder
	await settle()
	var packed := PackedScene.new()
	check(packed.pack(holder) == OK and packed.get_state().get_node_count() == 9, "Save persists only the eight prefab roots")
	var restored := packed.instantiate()
	root.add_child(restored)
	await settle()
	for saved: TownDetailProp in restored.get_children():
		check(saved.get_child_count() == 1 and saved.has_node("Geometry/RicochetCollision") and not saved.flowers_enabled and saved.position.is_equal_approx(Vector3(4, 0.8, 6)), "Reload restores kind, placement and options: " + saved.name)
	check(terrain._generated == ground_mesh and dressing._generated == dressing_mesh and terrain._map_texture.get_rid() == paint_rid, "Placement does not rebuild terrain or foliage")
	check(terrain.data.to_image().get_data() == paint_data, "Hand-painted ground data preserved")
	for prop in props: prop.collision_enabled = false
	await settle()
	for prop in props: check(not prop.has_node("Geometry/RicochetCollision"), "Optional collision can be disabled: " + prop.name)
	print("Town details: ", checks, " checks, ", failures, " failures")
	preview.queue_free()
	holder.queue_free()
	restored.queue_free()
	for frame in 3: await process_frame
	quit(1 if failures else 0)
