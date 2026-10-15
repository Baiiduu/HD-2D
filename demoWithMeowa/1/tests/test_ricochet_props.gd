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

func run() -> void:
	var preview: Node3D = load("res://scenes/previews/ricochet_props_preview.tscn").instantiate()
	preview.get_node("CurrentWorld/MapEffects/BGM").music_enabled = false
	root.add_child(preview)
	current_scene = preview
	await settle()
	world = preview.get_node("CurrentWorld")
	var samples: Node3D = world.get_node("RicochetSamples")
	var terrain: Terrain = world.get_node("Homestead")
	var dressing: Node3D = world.get_node("GroundDressing")
	var ground_mesh := terrain._generated
	var dressing_mesh: Node3D = dressing._generated
	var paint_rid := terrain._map_texture.get_rid()
	var terrain_before := terrain.data.to_image().get_data()
	var props: Array[RicochetProp] = []
	for node in samples.get_children():
		if not node is RicochetProp: continue
		props.append(node)
		check(node.is_in_group("ricochet_obstacles") and node._collision_body.is_in_group("ricochet_surfaces"), "Obstacle and surface tags available: " + node.name)
		check(node._collision_body.collision_layer == 1 and node._collision_body.get_child_count() > 0, "Existing world-collision layer: " + node.name)
		check(not node.is_processing(), "Static asset has no idle frame updates: " + node.name)
	check(props.size() == 6, "Six distinct non-house prefab types")
	var wall: RicochetProp = samples.get_node("LowStoneWall")
	var fence: RicochetProp = samples.get_node("IronFence")
	var crates: RicochetProp = samples.get_node("CrateStack")
	var barrels: RicochetProp = samples.get_node("BarrelCluster")
	var pillar: RicochetProp = samples.get_node("StonePillar")
	var corner: RicochetProp = samples.get_node("CornerWall")
	var hit := ray(wall, Vector3(0, 0.7, 2), Vector3(0, 0.7, -2))
	check(is_surface(hit, wall), "Solid wall stops physical ray")
	if not hit.is_empty():
		var incoming := Vector3(0.6, 0, -0.8)
		var outgoing: Vector3 = incoming.bounce(hit.normal)
		check(outgoing.is_equal_approx(Vector3(0.6, 0, 0.8)), "Flat wall preserves tangent and reverses normal direction")
	var bar: CollisionShape3D
	var next_bar: CollisionShape3D
	for node in fence._collision_body.get_children():
		if not String(node.name).begins_with("FenceBar"): continue
		if not bar: bar = node
		elif not next_bar: next_bar = node
	var gap_x := (bar.position.x + next_bar.position.x) * 0.5
	var fence_y := fence.dimensions.y * 0.72
	check(ray(fence, Vector3(gap_x, fence_y, 1), Vector3(gap_x, fence_y, -1)).is_empty(), "Fence opening has no invisible solid panel")
	check(is_surface(ray(fence, Vector3(bar.position.x, fence_y, 1), Vector3(bar.position.x, fence_y, -1)), fence), "Fence picket blocks exactly at visible bar")
	check(is_surface(ray(fence, Vector3(0, 0.2, 1), Vector3(0, 0.2, -1)), fence), "Fence's stone foundation remains solid")
	var body: CollisionShape3D = barrels._collision_body.get_child(0)
	var radius: float = (body.shape as CylinderShape3D).radius
	var barrel_x := body.position.x - radius * 0.5
	hit = ray(barrels, Vector3(barrel_x, body.position.y, body.position.z + 1.5), Vector3(barrel_x, body.position.y, body.position.z - 0.2))
	check(is_surface(hit, barrels), "Curved barrel surface receives ray")
	if not hit.is_empty():
		var normal: Vector3 = barrels.global_basis.inverse() * hit.normal
		check(normal.x < -0.25 and normal.z > 0.5, "Cylinder supplies radial normal, not an enclosing box normal")
		var outgoing: Vector3 = Vector3(0, 0, -1).bounce(normal)
		check(absf(outgoing.x) > 0.4 and is_equal_approx(outgoing.length(), 1.0), "Round barrel changes bounce heading without changing speed")
	var cap_x := body.position.x - radius * 0.96
	check(ray(barrels, Vector3(cap_x, barrels.dimensions.y * 0.98, body.position.z + 1.5), Vector3(cap_x, barrels.dimensions.y * 0.98, body.position.z - 0.2)).is_empty(), "Tapered barrel top does not leave an invisible full-radius cylinder")
	var first_crate: CollisionShape3D = crates._collision_body.get_child(0)
	var box_size: Vector3 = (first_crate.shape as BoxShape3D).size
	hit = ray(crates, first_crate.position + Vector3(0, 0, box_size.z * 0.5 + 1), first_crate.position - Vector3(0, 0, 0.2))
	check(is_surface(hit, crates), "Crate stack exposes solid box faces")
	hit = ray(pillar, Vector3(0, 1.1, 2), Vector3(0, 1.1, -2))
	check(is_surface(hit, pillar) and absf(hit.get("normal", Vector3.ZERO).z) > 0.99, "Square pillar exposes a planar face")
	var query := PhysicsShapeQueryParameters3D.new()
	var probe := SphereShape3D.new()
	probe.radius = 0.08
	query.shape = probe
	query.collision_mask = 1
	query.transform = Transform3D(Basis.IDENTITY, corner.to_global(Vector3(0.2, 0.75, 0.2)))
	check(world.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(), "L-shaped wall leaves its inside walkable and unfilled")
	var start := Vector3(0.4, 0.75, 0.3)
	var direction := Vector3(-1, 0, -1).normalized()
	var first := ray(corner, start, start + direction * 6)
	check(is_surface(first, corner), "Corner catches first ray")
	if not first.is_empty():
		var first_normal: Vector3 = corner.global_basis.inverse() * first.normal
		var outgoing := direction.bounce(first_normal)
		var next_start := corner.to_local(first.position) + first_normal * 0.01
		var second := ray(corner, next_start, next_start + outgoing * 6)
		check(is_surface(second, corner), "First reflection reaches second inside wall")
		if not second.is_empty():
			var second_normal: Vector3 = corner.global_basis.inverse() * second.normal
			var result := outgoing.bounce(second_normal)
			check(absf(first_normal.dot(second_normal)) < 0.01 and result.x > 0 and result.z > 0, "Two perpendicular surfaces reflect the ray back into open space")
	var geometry := wall._generated
	wall.position += Vector3(0, 0, 1.0)
	wall.rotation_degrees.y = 45.0
	await settle()
	hit = ray(wall, Vector3(0, 0.7, 2), Vector3(0, 0.7, -2))
	check(is_surface(hit, wall) and wall._generated == geometry, "Moving and rotating carry collider without regenerating mesh")
	if not hit.is_empty():
		check(absf(hit.normal.dot(wall.global_basis.z)) > 0.99, "Rotated wall supplies rotated reflection normal")
	var duplicate: RicochetProp = load("res://scenes/buildings/ricochet/low_wall.tscn").instantiate()
	duplicate.position = Vector3(49, 0, 35.5)
	samples.add_child(duplicate)
	await settle()
	var other_geometry := duplicate._generated
	wall.dimensions.x = 4.2
	await settle()
	check(wall._generated != geometry and duplicate._generated == other_geometry and is_equal_approx(duplicate.dimensions.x, 3.6), "Inspector changes only the selected prefab")
	check(wall._materials["stone"] != duplicate._materials["stone"], "Instances have independent materials")
	var holder := Node3D.new()
	root.add_child(holder)
	for original in props:
		var saved: RicochetProp = load(original.scene_file_path).instantiate()
		saved.position = Vector3(4, 0.8, 6)
		saved.rotation_degrees.y = 35
		holder.add_child(saved)
		saved.owner = holder
	await settle()
	var packed := PackedScene.new()
	check(packed.pack(holder) == OK and packed.get_state().get_node_count() == 7, "Saving persists six prefab roots without generated geometry")
	var restored := packed.instantiate()
	root.add_child(restored)
	await settle()
	for saved: RicochetProp in restored.get_children():
		check(saved.has_node("Geometry/RicochetCollision") and saved.get_child_count() == 1 and saved.position == Vector3(4, 0.8, 6), "Reload restores placement and a single complete assembly: " + saved.name)
	check(terrain._generated == ground_mesh and dressing._generated == dressing_mesh and terrain._map_texture.get_rid() == paint_rid, "No full terrain or dressing rebuild during placement")
	check(terrain.data.to_image().get_data() == terrain_before, "Hand-painted terrain data preserved")
	for prop in props: prop.collision_enabled = false
	await settle()
	for prop in props: check(not prop.has_node("Geometry/RicochetCollision"), "Optional collision removes blockers: " + prop.name)
	print("Ricochet props: ", checks, " checks, ", failures, " failures")
	preview.queue_free()
	holder.queue_free()
	restored.queue_free()
	for frame in 3: await process_frame
	quit(1 if failures else 0)
