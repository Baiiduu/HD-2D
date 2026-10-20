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
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	world.get_node("WavePrototype").process_mode = Node.PROCESS_MODE_DISABLED
	world.get_node("MapEffects/BGM").music_enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	world.get_node("MapEffects/CoreFeedbackAudio").enabled = false
	root.add_child(world)
	current_scene = world
	await settle()
	var terrain: Terrain = world.get_node("Homestead")
	var dressing: Node3D = world.get_node("GroundDressing")
	var terrain_geometry := terrain._generated
	var vegetation_geometry: Node3D = dressing._generated
	var ground_material: ShaderMaterial = terrain.top_material
	var paint_map := terrain._map_texture.get_rid()
	var data_before := terrain.data.to_image().get_data()
	var prefab: PackedScene = load("res://scenes/buildings/tree_planter.tscn")
	var first: TreePlanter = prefab.instantiate()
	first.position = Vector3(14, 3.5, 44)
	world.add_child(first)
	first.snap_to_ground()
	await settle()
	var original_geometry := first._generated
	var tree: MeshInstance3D = first.get_node("PlanterGeometry/Tree")
	var tree_material: ShaderMaterial = tree.mesh.surface_get_material(0)
	var collision: StaticBody3D = first.get_node("PlanterGeometry/PlanterCollision")
	var body_rid := collision.get_rid()
	check(absf(first.position.y) < 0.001, "Battle planter snaps to actual ground")
	check(tree_material.get_shader_parameter("tree_texture").get_size() == Vector2(128, 128), "Native tree dimensions preserved")
	check(absf(tree.position.y - (first.height - 0.065 + (first.tree_anchor.y - 64.0) * first.tree_pixel_size)) < 0.001, "Tree root anchored to recessed soil")
	var image: Image = first.tree_texture.get_image()
	if image.is_compressed(): image.decompress()
	check(image.get_pixel(0, 0).a == 0.0 and image.get_pixel(63, 95).a > 0.5, "Transparent background and solid trunk")
	check(not first.lamp_enabled and not first.has_node("PlanterGeometry/Lamp"), "Planter prefab has no attached lamp or light by default")
	check(first.city_panel_texture != null, "Planter prefab selects the approved city panels")
	check(collision.get_child_count() == 3, "Metal body, stone cap and wooden bench have separate material regions")
	if collision.get_child_count() == 3:
		var lower := collision.get_child(0) as CollisionShape3D
		var upper := collision.get_child(1) as CollisionShape3D
		check(is_equal_approx(lower.shape.size.x, first.width + 0.06) and is_equal_approx(upper.shape.size.x, lower.shape.size.x) and is_equal_approx(lower.shape.size.z, first.depth + 0.06) and is_equal_approx(upper.shape.size.z, lower.shape.size.z), "City panels keep the original collision footprint")
		check(is_zero_approx(lower.position.y - lower.shape.size.y * 0.5) and is_equal_approx(lower.position.y + lower.shape.size.y * 0.5, upper.position.y - upper.shape.size.y * 0.5) and is_equal_approx(upper.position.y + upper.shape.size.y * 0.5, first.height + 0.07), "Material split keeps the original continuous solid height")
	check((first.get_node("PlanterGeometry/Plant00").mesh.surface_get_material(0) as ShaderMaterial).get_shader_parameter("stable_shadows"), "Planter vegetation uses stable soft clump shadows")
	first.position += Vector3(6, 0, 3)
	first.rotation_degrees.y = 90.0
	await settle()
	check(first._generated == original_geometry, "Moving and rotating do not rebuild prefab")
	check(collision.get_rid() == body_rid and collision.global_position.is_equal_approx(first.global_position), "Collider moves with root")
	var ray := PhysicsRayQueryParameters3D.create(first.global_position + Vector3(0, 4, 0), first.global_position + Vector3(0, -0.5, 0), 1)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(ray)
	check(hit.get("collider") == collision, "Moved collider blocks at new location")
	var second: TreePlanter = prefab.instantiate()
	second.position = Vector3(13, 0, 46)
	world.add_child(second)
	await settle()
	var second_geometry := second._generated
	var second_material: ShaderMaterial = second.get_node("PlanterGeometry/Tree").mesh.surface_get_material(0)
	check(second_material != tree_material, "Instances have independent wind/lighting materials")
	first.width = 4.0
	first.tree_anchor.x = 56.0
	first.lamp_enabled = false
	first.bench_enabled = false
	await settle()
	check(first._generated != original_geometry and second._generated == second_geometry and second.width == 3.2, "Parameter change rebuilds only selected instance")
	check(not first.has_node("PlanterGeometry/Lamp"), "Lamp toggle removes only prefab lamp")
	var shifted_tree: MeshInstance3D = first.get_node("PlanterGeometry/Tree")
	check(absf((shifted_tree.mesh as QuadMesh).center_offset.x - 0.2) < 0.001 and shifted_tree.position.x == first.tree_offset.x, "Off-center tree anchor stays at the root through camera rotation")
	check(first.get_node("PlanterGeometry/PlanterCollision").get_child_count() == 2, "Bench toggle keeps only the body and cap collision")
	var holder := Node3D.new()
	root.add_child(holder)
	var saved: TreePlanter = prefab.instantiate()
	saved.position = Vector3(7, 0.8, 9)
	saved.rotation_degrees.y = 35.0
	saved.width = 3.8
	saved.lamp_enabled = false
	holder.add_child(saved)
	saved.owner = holder
	await settle()
	var packed := PackedScene.new()
	check(packed.pack(holder) == OK, "Prefab can be saved inside a world scene")
	check(packed.get_state().get_node_count() == 2, "Generated meshes and collision are not serialized twice")
	var restored := packed.instantiate()
	root.add_child(restored)
	await settle()
	var restored_planter: TreePlanter = restored.get_child(0)
	check(restored_planter.width == 3.8 and restored_planter.position == Vector3(7, 0.8, 9), "Saved placement and instance parameters survive reload")
	check(restored_planter.get_child_count() == 1 and restored_planter.has_node("PlanterGeometry/Tree"), "Reload generates one complete assembly")
	check(terrain._generated == terrain_geometry and terrain.top_material == ground_material and terrain._map_texture.get_rid() == paint_map, "No terrain geometry or paint-map rebuild")
	check(dressing._generated == vegetation_geometry, "No full-map dressing rebuild")
	check(terrain.data.to_image().get_data() == data_before, "Hand-painted terrain remains unchanged")
	first.collision_enabled = false
	await settle()
	check(not first.has_node("PlanterGeometry/PlanterCollision"), "Collision switch removes all prefab blockers")
	second.city_panel_texture = null
	await settle()
	check(second.has_node("PlanterGeometry/Stone") and not second.has_node("PlanterGeometry/City") and not second.has_node("PlanterGeometry/Metal"), "Clearing city panels restores the original stone construction")
	check(second.get_node("PlanterGeometry/PlanterCollision").get_child_count() == 2, "Original stone construction keeps its body and bench collision")
	print("Tree planter: ", checks, " checks, ", failures, " failures")
	(world.get_node("MapEffects/GameAudio") as GameAudio).stop_all()
	world.queue_free()
	holder.queue_free()
	restored.queue_free()
	for frame in 3: await process_frame
	quit(1 if failures else 0)
