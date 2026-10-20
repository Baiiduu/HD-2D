extends SceneTree

const BATCH = preload("res://scripts/rendering/static_geometry_batch.gd")
const SHADER = preload("res://shaders/environment/plaza_metal.gdshader")
var checks := 0
var failures: Array[String] = []
var world: Node3D
var batch: Node3D

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label)

func settle() -> void:
	for step in 3: await process_frame

func owner_at(point: Vector3, tint := Color.WHITE) -> Node3D:
	var owner := Node3D.new()
	world.add_child(owner)
	owner.position = point
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("tint", tint)
	var stream := SurfaceTool.new()
	stream.begin(Mesh.PRIMITIVE_TRIANGLES)
	stream.append_from(BoxMesh.new(), 0, Transform3D.IDENTITY)
	var mesh := stream.commit()
	mesh.surface_set_material(0, material)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	owner.add_child(visual)
	batch.register_owner(owner, owner)
	return owner

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	batch = BATCH.new()
	batch.name = "StaticGeometryBatch"
	world.add_child(batch)
	var a := owner_at(Vector3(1, 0, 1))
	var b := owner_at(Vector3(2, 0, 1))
	await settle()
	check(batch.get_batch_stats().sources == 2 and batch.get_batch_stats().batches == 1, "equal surfaces from independent owners share a batch")
	check(a.get_child(0).visible and b.get_child(0).visible, "source visibility remains available to reflection and scene logic")
	var merged: MeshInstance3D = batch._batches[0]
	check(merged.mesh.get_faces().size() == 72, "all original triangles are retained")
	var bounds := merged.global_transform * merged.get_aabb()
	check(bounds.position.is_equal_approx(Vector3(0.5, -0.5, 0.5)) and bounds.size.is_equal_approx(Vector3(2, 1, 1)), "merged transform preserves both world footprints")
	var extra := owner_at(Vector3(3, 0, 1))
	await settle()
	var record = load("res://scripts/rendering/building_occlusion.gd").Building.new(a, true)
	record.refresh_bounds()
	record.blocked = true
	record.advance(0.03, 0.25, 0.12, 0.25, 0.18)
	await settle()
	check(a.get_child(0) not in batch._sources and b.get_child(0) in batch._sources and extra.get_child(0) in batch._sources, "fading a prop releases only its contribution while other props remain batched")
	var fading_batch: MeshInstance3D = batch._batches[0]
	record.advance(0.03, 0.25, 0.12, 0.25, 0.18)
	await settle()
	check(batch._batches[0] == fading_batch and a.get_child(0).transparency > 0.3, "fade progress changes original geometry without rebuilding batches every frame")
	a.add_child(Node3D.new())
	record.refresh_bounds()
	record.advance(0.0, 0.25, 0.12, 0.25, 0.18)
	await settle()
	check(batch._batches[0] == fading_batch and is_equal_approx(record.amount, 0.5), "refreshing geometry retains the fade and batch exclusion")
	extra.reparent(a, true)
	batch.request_rebuild()
	await settle()
	check(batch._sources.is_empty(), "a planter fade also releases geometry registered by its nested lamp")
	extra.reparent(world, true)
	batch.request_rebuild()
	await settle()
	record.blocked = false
	record.advance(1.0, 0.25, 0.12, 0.25, 0.18)
	await settle()
	check(a.get_child(0) in batch._sources and is_zero_approx(a.get_child(0).transparency), "fully restored props return to shared batches")
	record.release()
	record = null
	extra.free()
	await settle()
	b.position.x = 20.0
	b.force_update_transform()
	await settle()
	check(batch.get_batch_stats().sources == 0, "moving an owner revokes the previous cell batch")
	b.position.x = 2.0
	b.force_update_transform()
	await settle()
	check(batch.get_batch_stats().sources == 2, "returning an owner rebuilds its cell")
	b.hide()
	await settle()
	check(batch.get_batch_stats().sources == 0, "parent visibility immediately removes its geometry")
	b.show()
	await settle()
	check(batch.get_batch_stats().sources == 2, "showing the owner restores eligibility")
	batch.request_rebuild()
	b.get_child(0).mesh.surface_get_material(0).set_shader_parameter("roughness", 0.123)
	await settle()
	check(batch.get_batch_stats().sources == 0, "explicit material revocation keeps unequal shader parameters separate")
	batch.request_rebuild()
	b.get_child(0).mesh.surface_get_material(0).set_shader_parameter("roughness", null)
	await settle()
	check(batch.get_batch_stats().sources == 2, "equal material parameters can be combined again")
	batch.enabled = false
	await settle()
	check(batch.get_batch_stats().sources == 0 and batch._sources.is_empty(), "disabled mode releases replacement draws")
	batch.enabled = true
	await settle()
	check(batch.get_batch_stats().sources == 2, "enabling rebuilds registered owners")
	b.queue_free()
	await settle()
	check(batch.get_batch_stats().sources == 0, "deletion removes stale contributions")
	var c := owner_at(Vector3(2, 0, 1), Color.RED)
	await settle()
	check(batch.get_batch_stats().sources == 0, "material variants remain independent")
	var d := owner_at(Vector3(2, 0, 1))
	await settle()
	check(batch.get_batch_stats().sources == 2, "a new matching owner joins the remaining source")
	d.get_child(0).queue_free()
	await settle()
	check(batch.get_batch_stats().sources == 0, "deleting a generated surface removes its contribution while its owner survives")
	d.queue_free()
	c.queue_free()
	a.queue_free()
	await settle()
	check(batch._owners.is_empty(), "all owner registrations are released")
	world.queue_free()
	await settle()
	await formal_world()
	print("STATIC_GEOMETRY_BATCH ", JSON.stringify({"checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)

func formal_world() -> void:
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("WorldMainMenu").show_on_world_start = false
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("GameSettingsUI").save_graphics_settings = false
	world.get_node("BuildingOcclusion").enabled = false
	world.get_node("WavePrototype").process_mode = Node.PROCESS_MODE_DISABLED
	world.get_node("MapEffects/BGM").music_enabled = false
	world.get_node("MapEffects/CoreFeedbackAudio").enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	batch = world.get_node("StaticGeometryBatch")
	batch.enabled = true
	root.add_child(world)
	current_scene = world
	for frame in 12: await process_frame
	check(batch.get_batch_stats().sources > batch.get_batch_stats().batches and batch.get_batch_stats().batches > 0, "formal scene combines independently generated props")
	var original_faces := 0
	var merged_faces := 0
	for source in batch._sources: original_faces += source.mesh.get_faces().size()
	for replacement in batch._batches: merged_faces += replacement.mesh.get_faces().size()
	check(original_faces == merged_faces, "formal batches preserve every source triangle")
	var planter: TreePlanter
	for prop in world.get_node("WorldDetails/BattleCourts").get_children():
		if prop is TreePlanter:
			planter = prop
			break
	check(planter != null, "formal scene includes a real planter for collision and reflection checks")
	if planter == null:
		world.queue_free()
		await settle()
		return
	var collider := planter.get_node("PlanterGeometry/PlanterCollision") as StaticBody3D
	var collider_rid := collider.get_rid()
	var tree := planter.get_node("PlanterGeometry/Tree") as MeshInstance3D
	check(tree not in batch._sources and tree.visible, "animated tree stays independent")
	var reflection: PlanarWaterReflection = world.get_node("MapEffects/WaterReflection")
	var mirror_count := reflection.get_child_count()
	reflection.rebuild()
	for frame in 8: await process_frame
	check(reflection.get_child_count() == mirror_count, "reflection rebuild does not duplicate merged geometry")
	check(batch.get_batch_stats().sources > 0, "reflection layer changes rebuild the batch")
	batch.enabled = false
	await settle()
	batch.enabled = true
	await settle()
	check(collider.get_rid() == collider_rid and collider.collision_layer == 1, "batch toggles preserve real collision bodies")
	(world.get_node("MapEffects/GameAudio") as GameAudio).stop_all()
	world.queue_free()
	await settle()
