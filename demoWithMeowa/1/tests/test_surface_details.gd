extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value: failures.append(label); print("FAIL: ",label)

func frames(count := 12) -> void:
	for index in count: await process_frame

func run() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("LoadoutUI").save_path = "D:/.codexfile/work/surface-integration/isolated-save.json"
	var sample: SpawnVisualSample = world.get_node("VisualSample")
	sample.follow_weather = false
	root.add_child(world)
	await frames(35)
	var terrain: Terrain = world.get_node("Homestead")
	var dressing: Node3D = world.get_node("GroundDressing")
	var sprite: Sprite3D = world.get_node("Player/Sprite")
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	var lens := [camera.fov,camera.distance,camera.pitch_degrees,camera.dof_amount]
	var heights := terrain.data.heights.duplicate()
	var overlays := terrain.data.overlays.duplicate()
	var paints := terrain.data.paints.duplicate()
	var terrain_mesh := terrain._generated
	var home_geometry := world.get_node("HouseSite/Home/Geometry")
	check(terrain.top_material.get_shader_parameter("wild_normal_enabled"),"Grass has matching normal data")
	check(terrain.top_material.get_shader_parameter("path_normal_enabled"),"Road atlas has matching normal data")
	check(terrain._paint_textures.has("paint_normals"),"Custom brush normals are bound as a separate array")
	check(terrain._paint_textures.paint_normals.get_width() == 64,"Unrelated 1024px colour brushes do not inflate normal arrays")
	check(sprite.get("normal_mapping_enabled") and sprite.get("_material").get_shader_parameter("normal_mapping_enabled"),"Player normal map is actually bound")
	check(terrain.wall_material.get_shader_parameter("wall_normal_enabled"),"Cliff has matching normal data")
	var settings: Image = terrain._paint_textures.paint_settings.get_image()
	check(settings.get_pixel(1,3).r > 0.5,"Existing cobble custom ID keeps its own normal map")
	var layered: Array = dressing._placements()
	dressing.layered_growth_strength = 0.0
	dressing.scale_variation = 0.0
	var original: Array = dressing._placements()
	check(original.size() == layered.size(),"Layering preserves the vegetation count")
	var unchanged_points := true
	var different_sizes := false
	for index in mini(original.size(),layered.size()):
		if original[index].point != layered[index].point: unchanged_points = false
		if not is_equal_approx(layered[index].scale,1.0): different_sizes = true
	check(unchanged_points,"Layering preserves every ground anchor and road exclusion")
	check(different_sizes,"Layering produces different clump sizes")
	dressing.layered_growth_strength = 0.8
	dressing.scale_variation = 0.16
	await frames()
	var anchor_points := {}
	for item in layered: anchor_points[Vector3(item.point).snapped(Vector3.ONE * 0.001)] = true
	var anchored := true
	for batch in dressing._generated.find_children("*","MultiMeshInstance3D",true,false):
		if DisplayServer.get_name() == "headless": break # Dummy renderer cannot read back instance buffers.
		for index in batch.multimesh.instance_count:
			var transform: Transform3D = batch.multimesh.get_instance_transform(index)
			var data: Color = batch.multimesh.get_instance_custom_data(index)
			var anchor := transform.origin-Vector3.UP*data.r
			if not anchor_points.has(anchor.snapped(Vector3.ONE*0.001)):
				var found := false
				for item in layered:
					if Vector3(item.point).distance_to(anchor) < 0.0001: found = true; break
				if not found: anchored = false; print("Unmatched root ",anchor," data ",data)
	if DisplayServer.get_name() != "headless": check(anchored,"Scaled cards keep their roots on the exact original terrace")
	var layers: Node3D = dressing._generated
	for style in [0,2,3,1]:
		sample.style = style
		await frames()
		check(dressing._generated == layers,"Style %d preserves layered placements" % style)
		check(terrain.top_material.get_shader_parameter("surface_normals_enabled") and sprite.get("normal_mapping_enabled"),"Style %d preserves independent normals" % style)
		check(terrain.wall_material.get_shader_parameter("grass_variation_strength") == sample.grass_variation_strength,"Style %d keeps the meadow variation on the rim" % style)
	for enabled in [false,true]:
		sample.edge_blending_enabled = enabled
		sample.surface_normals_enabled = enabled
		sample.character_normals_enabled = enabled
		await frames()
		check(terrain.top_material.get_shader_parameter("surface_normals_enabled") == enabled,"Normal toggle applies")
		check(terrain.top_material.get_shader_parameter("path_edge_blending_enabled") == enabled,"Edge toggle applies")
		check(sprite.get("normal_mapping_enabled") == enabled,"Player toggle applies")
		check(terrain._generated == terrain_mesh and world.get_node("HouseSite/Home/Geometry") == home_geometry,"Toggles preserve meshes and physical collisions")
		check(dressing._generated == layers,"Normal and edge toggles do not scatter plants")
	check(heights == terrain.data.heights and overlays == terrain.data.overlays and paints == terrain.data.paints,"Surface work preserves terrain and painted IDs")
	check(lens == [camera.fov,camera.distance,camera.pitch_degrees,camera.dof_amount],"All changes preserve the development camera")
	var frame := AtlasTexture.new()
	frame.atlas = load("res://assets/meowa/player/idle_00.png")
	frame.region = Rect2(16,8,16,24)
	sprite.texture = frame
	sprite.set("normal_mapping_enabled",true)
	sprite.call("apply_lighting")
	var expected := Vector4(16.0/frame.atlas.get_width(),8.0/frame.atlas.get_height(),16.0/frame.atlas.get_width(),24.0/frame.atlas.get_height())
	check(sprite.get("_material").get_shader_parameter("sprite_region") == expected,"Character normal sampling uses the actual atlas frame")
	var mirror := ShaderMaterial.new()
	mirror.shader = load("res://shaders/character_lighting.gdshader")
	sprite.call("apply_lighting_to",mirror,true)
	check(mirror.get_shader_parameter("normal_mapping_enabled") and mirror.get_shader_parameter("sprite_region") == expected,"Reflection receives the same frame and normal data")
	var brush := TerrainPaintBrush.new()
	brush.texture = frame
	check(brush.normal_image().get_size() == Vector2i(16,24),"Atlas brush crops its normal to the same frame")
	brush.normal_texture = load("res://assets/surface_normals/pixel_grass.png")
	check(not brush.validation_error().is_empty(),"Mismatched user normal dimensions are rejected")
	world.queue_free()
	await frames(3)
	print(JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)
