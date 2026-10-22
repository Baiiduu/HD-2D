extends SceneTree

var checks := 0
var failures: Array[String] = []
const SCRATCH := "D:/.codexfile/work/terrain-palette/"

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL: ",message)

func _run() -> void:
	var original: TerrainData = load("res://data/world/spawn_terrain.tres").duplicate(true)
	original.paints = PackedByteArray()
	check(original.paints.is_empty(),"Legacy terrain has no custom IDs")
	check(original.to_image().get_pixel(0,0).a == 0.0,"Old terrain defaults to legacy rendering")
	var palette: TerrainPaintPalette = load("res://data/world/spawn_paint_palette.tres").duplicate(true)
	# The user may already be adding further brushes in the live editor.
	palette.brushes = [palette.brushes[0],palette.brushes[1]]
	check(palette.validation_error().is_empty(),"Current grass/path palette is valid")
	var grass: Texture2D = load("res://assets/meowa/homestead/grass.png")
	check(palette.brushes[0].texture.resource_path == grass.resource_path,"Default grass source is preserved")
	var fixture := Image.create_empty(32,32,false,Image.FORMAT_RGBA8)
	fixture.fill(Color.BLUE)
	fixture.fill_rect(Rect2i(16,24,8,8),Color.RED)
	var tile := TerrainPaintBrush.new()
	tile.paint_id = 8
	tile.texture = ImageTexture.create_from_image(fixture)
	tile.mode = TerrainPaintBrush.Mode.ATLAS_TILE
	tile.atlas_tile = Vector2i(2,3)
	check(tile.validation_error().is_empty(),"Atlas tile configuration is accepted")
	check(tile.source_image().get_size() == Vector2i(8,8) and tile.source_image().get_pixel(4,4) == Color.RED,"Atlas tile selects the intended region")
	tile.atlas_tile = Vector2i(4,3)
	check(not tile.validation_error().is_empty(),"Out of range atlas tile is rejected")
	tile.atlas_tile = Vector2i(2,3)
	var plain := TerrainPaintBrush.new()
	plain.paint_id = 7
	plain.texture = load("res://assets/meowa/home/stone.png")
	var atlas := TerrainPaintBrush.new()
	atlas.paint_id = 9
	atlas.texture = palette.brushes[1].texture
	atlas.mode = TerrainPaintBrush.Mode.CORNER_ATLAS
	check(atlas.validation_error().is_empty(),"Meowa transition atlas is accepted")
	atlas.corner_tiles = PackedVector2Array([Vector2.ZERO])
	check(not atlas.validation_error().is_empty(),"Missing transition cases are rejected")
	atlas.corner_tiles = PackedVector2Array(TerrainPaintBrush.MEOWA_TILES)
	palette.brushes = [palette.brushes[0],palette.brushes[1],plain,tile,atlas]
	check(palette.validation_error().is_empty(),"Additional independent brushes are accepted")
	var unfinished := TerrainPaintBrush.new()
	unfinished.paint_id = 10
	palette.brushes = [palette.brushes[0],palette.brushes[1],plain,tile,atlas,unfinished]
	var partial_material: ShaderMaterial = load("res://materials/world/spawn_ground.tres").duplicate()
	var partial := palette.apply_to(partial_material)
	check(partial.paint_textures.get_layers() == 3,"Unfinished brushes leave configured brushes usable")
	palette.brushes = [palette.brushes[0],palette.brushes[1],plain,tile,atlas]
	tile.paint_id = 7
	check(not palette.validation_error().is_empty(),"Duplicate IDs are rejected")
	tile.paint_id = 8
	var material: ShaderMaterial = load("res://materials/world/spawn_ground.tres").duplicate()
	var textures := palette.apply_to(material)
	check(material.get_shader_parameter("paint_enabled"),"Additional texture layers are enabled")
	check(textures.paint_textures.get_layers() == 3,"Each custom brush gets a separate layer")
	if DisplayServer.get_name() != "headless":
		check(textures.paint_textures.get_layer_data(1).get_pixel(10,10) == Color.RED,"Atlas crop survives layer normalization")
	var settings: Image = textures.paint_settings.get_image()
	check(settings.get_pixel(9,19) == Color(2,1,0,0),"Transition case 15 uses the configured atlas tile")
	palette.brushes = [atlas,tile,plain,palette.brushes[1],palette.brushes[0]]
	textures = palette.apply_to(material)
	settings = textures.paint_settings.get_image()
	check(settings.get_pixel(7,0).r == 3.0 and palette.brush_for_id(7) == plain,"Reordering brushes preserves painted IDs")
	check(material.get_shader_parameter("paint_textures") == null,"Generated textures are not stored in saved materials")
	var changed := [false]
	palette.changed.connect(func(): changed[0] = true)
	plain.roughness = 0.8
	check(changed[0],"Editing a brush notifies its palette")
	var data := TerrainData.new()
	data.size = Vector2i.ZERO
	data.resize(Vector2i(-1,-1),Vector2i(3,3))
	data.biomes.fill(TerrainData.Biome.WILD)
	data.overlays[4] = TerrainData.OVERLAY_PATH | TerrainData.OVERLAY_WATER | TerrainData.OVERLAY_RAMP
	var old_heights := data.heights.duplicate()
	var before := plain.stamp(data,4,false)
	check(data.paints[4] == 7,"Custom brush stamps its fixed ID")
	check(data.overlays[4] == (TerrainData.OVERLAY_WATER | TerrainData.OVERLAY_RAMP),"Painting preserves water and ramp flags")
	check(data.heights == old_heights,"Painting preserves terrain height")
	tile.stamp(data,4,true)
	check(data.paints[4] == 7,"Erasing another brush leaves this surface intact")
	plain.stamp(data,4,true)
	check(data.paints[4] == 0,"Erasing the selected brush restores the base")
	var history := UndoRedo.new()
	history.create_action("paint")
	history.add_do_method(data.apply_surface_patch.bind(PackedInt32Array([4]),PackedByteArray([3]),PackedByteArray([20]),PackedByteArray([7])))
	history.add_undo_method(data.apply_surface_patch.bind(PackedInt32Array([4]),PackedByteArray([before.x]),PackedByteArray([before.y]),PackedByteArray([before.z])))
	history.commit_action()
	check(data.paints[4] == 7,"Redo patch applies the custom surface")
	history.undo()
	check(data.paints[4] == 0 and data.overlays[4] == 21,"Undo restores both previous surface and overlays")
	history.redo()
	check(data.paints[4] == 7,"Redo restores the brush")
	check(roundi(data.to_image().get_pixel(1,1).a * 255.0) == 7,"GPU map encodes the selected ID")
	data.resize(Vector2i(-2,-2),Vector2i(5,5))
	check(data.paint_at_index(12) == 7 and data.paint_at_index(0) == 0,"Map expansion preserves painted cells and initializes new cells")
	var stamp := str(OS.get_process_id())
	check(ResourceSaver.save(data,SCRATCH+"data-"+stamp+".tres") == OK,"Terrain data saves")
	var restored: TerrainData = load(SCRATCH+"data-"+stamp+".tres")
	check(restored.paint_at_index(12) == 7,"Terrain surface IDs survive reload")
	# Save the real-source brush instead of the generated fixture texture.
	palette.brushes = [plain,atlas]
	check(ResourceSaver.save(palette,SCRATCH+"palette-"+stamp+".tres") == OK,"Palette saves")
	var reloaded: TerrainPaintPalette = load(SCRATCH+"palette-"+stamp+".tres")
	check(reloaded.brush_for_id(9).corner_tiles == atlas.corner_tiles,"Atlas configuration survives reload")
	history.clear_history()
	history.free()
	print("Terrain palette: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
