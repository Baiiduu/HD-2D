extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); print("FAIL: ", label)

func frames(count := 8) -> void:
	for index in count: await process_frame

func run() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	root.add_child(world)
	current_scene = world
	await frames(30)
	var dressing: Node3D = world.get_node("GroundDressing")
	var region: GroundDressingRegion = dressing.get_node("CourtyardForestSample")
	var terrain: Terrain = world.get_node("Homestead")
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	var sample: SpawnVisualSample = world.get_node("VisualSample")
	var dynamics: EnvironmentDynamics = world.get_node("EnvironmentDynamics")
	var weather: Node = world.get_node("MapEffects/Weather")
	var lens := [camera.fov, camera.distance, camera.pitch_degrees, camera.focus_height, camera.dof_amount]
	var terrain_state := [terrain.data.heights.duplicate(), terrain.data.overlays.duplicate(), terrain.data.paints.duplicate()]
	var inventory: Dictionary = world.get_node("LoadoutUI").state.export_state().duplicate(true)
	var geometry: Node = terrain._generated
	region.enabled = false
	await frames()
	var original: Array = dressing._placements()
	region.enabled = true
	await frames()
	var lush: Array = dressing._placements()
	var preserved := 0
	for item in lush:
		if preserved < original.size() and item == original[preserved]: preserved += 1
	check(preserved == original.size(), "Every original plant keeps its location, size, variant and relative order")
	check(lush == dressing._placements(), "The sample scatter is deterministic")
	var extras: Array = lush.filter(func(item): return int(String(item.asset).get_slice("_", 1)) > 6)
	check(extras.size() >= 60 and extras.size() <= 150, "A small courtyard patch forms dense vegetation")
	var ids := {}
	var anchored := true
	var courtyard_only := true
	var clear := true
	var central_size := 0.0
	var central_count := 0
	var fringe_size := 0.0
	var fringe_count := 0
	for item in extras:
		ids[item.asset] = true
		var point: Vector3 = dressing.to_global(item.point)
		var cell := terrain.data.world_to_cell(terrain.to_local(point))
		anchored = anchored and is_equal_approx(point.y, terrain.data.get_level(cell) * terrain.data.layer_height)
		var local := region.to_local(point)
		var radius := (Vector2(local.x, local.z) / (region.area_size * 0.5)).length()
		courtyard_only = courtyard_only and radius < 1.0 and point.z < 10.0
		if radius < 0.5: central_size += item.scale; central_count += 1
		if radius > 0.8: fringe_size += item.scale; fringe_count += 1
		for offset in [Vector3.ZERO, Vector3(0.4,0,0), Vector3(-0.4,0,0), Vector3(0,0,0.4), Vector3(0,0,-0.4)]:
			var neighbor := terrain.data.world_to_cell(terrain.to_local(point) + offset)
			clear = clear and dressing._paintable_cell(neighbor, terrain.data.get_level(cell))
	check(ids.size() == 8, "All eight new plant shapes occur in the patch")
	check(anchored, "Roots follow the actual flat terrace")
	check(courtyard_only, "Additional plants stay inside the small courtyard ellipse")
	check(clear, "Leaves retain clearance from roads, ramps and terrace edges")
	check(central_count > 0 and fringe_count > 0 and central_size / maxf(central_count,1) > fringe_size / maxf(fringe_count,1), "The patch becomes lower at its edges")
	var native_anchors := true
	var materials := {}
	for batch in dressing._generated.find_children("*", "MultiMeshInstance3D", true, false):
		var id := String(batch.name).get_slice("_",0) + "_" + String(batch.name).get_slice("_",1)
		if not ids.has(id): continue
		var material: ShaderMaterial = batch.multimesh.mesh.material
		materials[id] = material
		if DisplayServer.get_name() != "headless":
			for index in batch.multimesh.instance_count:
				var transform: Transform3D = batch.multimesh.get_instance_transform(index)
				var custom: Color = batch.multimesh.get_instance_custom_data(index)
				var found := false
				for item in extras:
					if item.asset == id and (transform.origin - Vector3.UP * custom.r).distance_to(item.point) < 0.0001: found = true; break
				native_anchors = native_anchors and found
	check(materials.size() == 8, "All new assets generate visible GPU batches")
	if DisplayServer.get_name() != "headless": check(native_anchors, "GPU cards keep their roots on the scatter anchors")
	for id in materials:
		var material: ShaderMaterial = materials[id]
		var texture: Texture2D = material.get_shader_parameter("sprite_texture")
		check(texture.get_size() == Vector2(32,32) and bool(material.get_shader_parameter("leaf_normal_available")), "%s preserves native pixels and matching normals" % id)
		check(dynamics._plants.has(material) and material.get_shader_parameter("ambient_dynamics_enabled") and weather._vegetation.has(material), "%s binds regional dynamics and weather wind" % id)
		check(int(material.get_shader_parameter("plant_palette_row")) == 0, "%s uses green leaf colours" % id)
	var layers: Node3D = dressing._generated
	for style in [0,1,2,3]:
		sample.style = style
		await frames()
		check(dressing._generated == layers and dressing._placements() == lush, "Style %d preserves the dense sample" % style)
	check(terrain._generated == geometry and terrain_state == [terrain.data.heights, terrain.data.overlays, terrain.data.paints], "Sample toggles preserve terrain, painting and collisions")
	check(lens == [camera.fov, camera.distance, camera.pitch_degrees, camera.focus_height, camera.dof_amount], "Sample and Style changes preserve the current camera")
	check(inventory == world.get_node("LoadoutUI").state.export_state(), "Inventory and save state are preserved")
	var catalog := preload("res://addons/parameter_hub/catalog.gd").new()
	var indexed := false
	for entry in catalog.collect(world):
		if entry.path == "GroundDressing/CourtyardForestSample" and entry.property == "extra_density":
			indexed = entry.category == "地图与地编" and entry.common
	check(indexed, "The sample density appears in the parameter hub")
	catalog.entries.clear()
	var mask := ImageTexture.create_from_image(Image.create(2,2,false,Image.FORMAT_R8))
	dressing.set_farming_mask(mask, Vector4(0,0,2,2))
	check(materials.values().all(func(material): return material.get_shader_parameter("farming_hide_enabled")), "New vegetation obeys the existing cultivation mask")
	dressing.set_farming_mask(null, Vector4.ZERO)
	region.extra_asset_ids = PackedStringArray(["grass_07"])
	await frames()
	var limited: Array = dressing._placements().filter(func(item): return int(String(item.asset).get_slice("_",1)) > 6)
	check(not limited.is_empty() and limited.all(func(item): return item.asset == "grass_07"), "The region can select individual new assets")
	region.extra_asset_ids = PackedStringArray()
	region.enabled = false
	await frames()
	check(dressing._placements() == original, "Disabling the sample exactly restores the original distribution")
	print(JSON.stringify({"checks":checks,"failures":failures,"added_plants":extras.size(),"native":DisplayServer.get_name() != "headless"}))
	world.queue_free()
	await frames(3)
	quit(0 if failures.is_empty() else 1)
