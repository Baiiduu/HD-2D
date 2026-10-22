extends SceneTree

const WORLD := "res://scenes/world/world.tscn"
const GRASS := "res://assets/ground/grass_smooth_v1/"
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(35.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		printerr("FAIL: ", label)

func frames(count := 6) -> void:
	for index in count: await process_frame

func run() -> void:
	var protected := {}
	for path in ["res://data/world/world_terrain.tres", "res://data/world/world_surface.res"]:
		protected[path] = FileAccess.get_sha256(path)
	var world: Node = load(WORLD).instantiate()
	var terrain := world.get_node("Homestead") as Terrain
	var palette := terrain.paint_palette
	check(palette.validation_error().is_empty(), "Saved World palette has unique targets and valid fixed brush IDs")
	for id in range(1, 25):
		check(palette.brush_for_id(id) != null, "Saved World retains custom brush %d" % id)
	var water_cells := 0
	var layout_matches := true
	for z in range(terrain.data.origin.y, terrain.data.origin.y + terrain.data.size.y):
		for x in range(terrain.data.origin.x, terrain.data.origin.x + terrain.data.size.x):
			var cell := Vector2i(x, z)
			var expected := x >= 6 and x <= 9 and z >= 19 and z <= 21 and cell != Vector2i(6, 21)
			var wet := terrain.data.has_overlay(cell, TerrainData.OVERLAY_WATER)
			if wet: water_cells += 1
			layout_matches = layout_matches and wet == expected and terrain.data.get_level(cell) == (-1 if expected else 0)
	check(water_cells == 11 and layout_matches, "The authored notched pond and flat surrounding land are saved in World")
	check(terrain.water_material != null and terrain.water_boundary_reflection_enabled, "Pond material and body reflection are connected")
	check(world.has_node("WorldDetails/WaterGarden/ShoreLamp") and world.has_node("WorldDetails/WaterGarden/ShoreLamp2"), "Both authored shore lamps remain placed")
	if not failures.is_empty():
		world.free()
		finish()
		return
	world.get_node("WorldMainMenu").show_on_world_start = false
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("GameSettingsUI").save_graphics_settings = false
	world.get_node("MapEffects/BGM").music_enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	world.get_node("MapEffects/CoreFeedbackAudio").enabled = false
	root.add_child(world)
	current_scene = world
	await frames(16)
	var visual: SpawnVisualSample = world.get_node("VisualSample")
	var snapshot := terrain.data.to_image().get_data()
	for style in 4:
		visual.style = style
		visual.apply_style()
		await frames()
		check(terrain.paint_palette.validation_error().is_empty(), "Style %d preserves a valid palette" % style)
		var albedo: Texture2D = terrain._paint_textures.get("wild_texture")
		check(albedo != null and albedo.resource_path == GRASS + "grass_albedo.png", "Style %d binds the latest grass albedo" % style)
		var grass_brush: TerrainPaintBrush
		for brush in terrain.paint_palette.brushes:
			if brush.target == TerrainPaintBrush.Target.GRASS: grass_brush = brush
		check(grass_brush != null and grass_brush.normal_texture != null and grass_brush.normal_texture.resource_path == GRASS + "grass_normal_gl.png", "Style %d preserves matching grass normals" % style)
		check(terrain.data.to_image().get_data() == snapshot and terrain._generated.has_node("Water"), "Style %d preserves the actual pond mesh and terrain" % style)
	for path in protected:
		check(FileAccess.get_sha256(path) == protected[path], "Running World does not overwrite the authored map: " + path)
	world.free()
	await frames()
	finish()

func finish() -> void:
	print("WORLD_VISUAL_RESOURCES: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
