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
	for index in 12: await process_frame

func run() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	var terrain: Terrain = world.get_node("Homestead")
	terrain.data = terrain.data.duplicate(true)
	root.add_child(world)
	current_scene = world
	await settle()
	var dressing: Node3D = world.get_node("GroundDressing")
	var geometry: Node3D = terrain._generated
	var layers: Node3D = dressing._generated
	var root_map: ImageTexture = dressing._root_map
	var roots: PackedByteArray = dressing._root_image.get_data()
	var map_rid := terrain._map_texture.get_rid()
	var palette := terrain.paint_palette
	check(palette.validation_error().is_empty(), "Formal map palette is valid")
	var visible_count := 0
	for brush in palette.brushes:
		if brush.show_in_painter: visible_count += 1
	check(visible_count == 17, "Painter offers ten modules, three band slices and four used legacy choices")
	for id in range(2, 11):
		check(palette.brush_for_id(id) != null and not palette.brush_for_id(id).show_in_painter, "Unused legacy ID stays reserved and hidden")
	for id in range(12, 22):
		var brush := palette.brush_for_id(id)
		check(brush != null and brush.show_in_painter, "New module is available")
		var source: Texture2D = brush.texture.atlas if brush.texture is AtlasTexture else brush.texture
		check(source.resource_path.begins_with("res://assets/meowa/city_plaza/fixed/"), "New modules use approved repaired art")
		check(brush.normal_image().get_size() == brush.source_image().get_size(), "New module normal matches its original canvas")
		check(brush.texture_meters.is_equal_approx(brush.texture.get_size() / 40.0), "Native pixel density remains forty per metre")
		check(brush.underlay_paint_id == (12 if id >= 15 else 0), "Transparent ornaments have their stone underlay")
	var settings: Image = terrain._paint_textures["paint_settings"].get_image()
	check(is_equal_approx(settings.get_pixel(12, 0).b, 2.4) and is_equal_approx(settings.get_pixel(12, 0).a, 2.4), "GPU settings encode continuous world repeat")
	check(settings.get_pixel(15, 3).b == 12.0, "GPU settings encode the ornament underlay")
	var cells: Array = dressing._surface_instances.keys()
	check(not cells.is_empty(), "Placement cache contains original vegetation")
	var cell: Vector2i = cells[0]
	var indices := PackedInt32Array([terrain.data._index(cell)])
	var original_biomes := PackedByteArray([terrain.data.biomes[indices[0]]])
	var original_overlays := PackedByteArray([terrain.data.overlays[indices[0]]])
	var original_paints := PackedByteArray([terrain.data.paint_at_index(indices[0])])
	var outside: Array[Dictionary] = []
	for other: Vector2i in cells:
		if (other - cell).length_squared() > 2:
			for entry: Dictionary in dressing._surface_instances[other]: outside.append(entry)
	var surface_events := [0]
	terrain.data.surface_changed.connect(func(_patch: PackedInt32Array): surface_events[0] += 1)
	var history := UndoRedo.new()
	history.create_action("paint")
	history.add_do_method(terrain.data.apply_surface_patch.bind(indices, original_biomes, original_overlays, PackedByteArray([12])))
	history.add_undo_method(terrain.data.apply_surface_patch.bind(indices, original_biomes, original_overlays, original_paints))
	var started := Time.get_ticks_usec()
	history.commit_action()
	print("Surface patch CPU: %.3f ms" % (float(Time.get_ticks_usec() - started) / 1000.0))
	await settle()
	check(terrain._generated == geometry, "Painting preserves terrain meshes and collision")
	check(terrain._map_texture.get_rid() == map_rid, "Painting updates the existing terrain texture")
	check(dressing._generated == layers and dressing._root_map == root_map, "Painting preserves all dressing nodes and its root texture")
	for entry: Dictionary in dressing._surface_instances[cell]:
		check(not entry.visible, "Painting stone hides vegetation in the edited cell")
		if DisplayServer.get_name() != "headless":
			check(entry.multimesh.get_instance_transform(entry.index).basis.determinant() == 0.0, "Native GPU instance is collapsed")
	for entry in outside:
		check(entry.visible and entry.multimesh.get_instance_transform(entry.index) == entry.transform, "Distant vegetation retains every original transform")
	check(dressing._root_image.get_data() != roots, "Hidden grass also loses its local root shadow")
	history.undo()
	await settle()
	check(terrain._generated == geometry and dressing._generated == layers, "Undo also uses the surface-only path")
	for entry: Dictionary in dressing._surface_instances[cell]:
		check(entry.visible and entry.multimesh.get_instance_transform(entry.index) == entry.transform, "Undo restores exact vegetation transforms")
	check(dressing._root_image.get_data() == roots, "Undo restores the original root shadow bytes")
	history.redo()
	await settle()
	check(terrain._generated == geometry and dressing._generated == layers and surface_events[0] == 3, "Redo stays local and each action emits one patch")
	history.undo()
	await settle()
	var wide_indices := PackedInt32Array()
	var wide_biomes := PackedByteArray()
	var wide_overlays := PackedByteArray()
	var wide_original := PackedByteArray()
	var wide_paints := PackedByteArray()
	for z in range(-4, 5):
		for x in range(-4, 5):
			var target := cell + Vector2i(x, z)
			if not terrain.data.has_cell(target): continue
			var index := terrain.data._index(target)
			wide_indices.append(index)
			wide_biomes.append(terrain.data.biomes[index])
			wide_overlays.append(terrain.data.overlays[index])
			wide_original.append(terrain.data.paint_at_index(index))
			wide_paints.append(12)
	started = Time.get_ticks_usec()
	terrain.data.apply_surface_patch(wide_indices, wide_biomes, wide_overlays, wide_paints)
	print("Wide surface patch (%d cells) CPU: %.3f ms" % [wide_indices.size(), float(Time.get_ticks_usec() - started) / 1000.0])
	await settle()
	check(terrain._generated == geometry and dressing._generated == layers, "Nine-cell brush also preserves all geometry nodes")
	terrain.data.apply_surface_patch(wide_indices, wide_biomes, wide_overlays, wide_original)
	await settle()
	check(dressing._root_image.get_data() == roots, "Restoring a wide stroke restores every root shadow byte")
	var overlay: int = terrain.data.overlays[indices[0]]
	terrain.data.apply_surface_patch(indices, original_biomes, PackedByteArray([overlay | TerrainData.OVERLAY_WATER]), original_paints)
	await settle()
	check(terrain._generated != geometry and dressing._generated != layers, "Geometry-changing water patches still rebuild normally")
	history.clear_history()
	history.free()
	world.queue_free()
	await settle()
	print("Terrain paint refresh: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
