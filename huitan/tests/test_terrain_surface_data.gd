extends SceneTree

const SCRATCH := "D:/.codexfile/work/free-surface-painter/"
const TERRAIN_PATH := "res://data/world/world_terrain.tres"

var checks := 0
var failures: Array[String] = []
var regions: Array[Rect2] = []
var changes := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL: ", message)

func _run() -> void:
	var legacy := load(TERRAIN_PATH) as TerrainData
	var legacy_hash := FileAccess.get_sha256(TERRAIN_PATH)
	var legacy_arrays := [legacy.biomes.duplicate(), legacy.overlays.duplicate(),
		legacy.heights.duplicate(), legacy.paints.duplicate()]
	var surface := TerrainSurfaceData.new()
	surface.region_changed.connect(func(rect: Rect2): regions.append(rect))
	surface.changed.connect(func(): changes += 1)
	check(surface.chunk_meters() == 6.4, "256 native pixels cover 6.4m at 40px/m")
	check(surface.get_used_codes().is_empty() and not surface.get_bounds().has_area(), "An empty surface has no edits or bounds")
	var brush := TerrainPaintBrush.new()
	brush.paint_id = 12
	brush.texture_meters = Vector2(2.4, 2.4)
	check(TerrainSurfaceData.code_for_brush(brush) == 12, "Custom brush retains its fixed ID")
	brush.target = TerrainPaintBrush.Target.GRASS
	check(TerrainSurfaceData.code_for_brush(brush) == 256, "Grass has a distinct code beyond legacy byte IDs")
	brush.target = TerrainPaintBrush.Target.PATH
	check(TerrainSurfaceData.code_for_brush(brush) == 257, "Path has a distinct code beyond legacy byte IDs")
	var original := surface.paint_segment(Vector2.ZERO, Vector2.ZERO, 0.06, 12)
	check(original.size() == 4 and regions.size() == 1 and changes == 1, "One circular segment crosses signed chunks with one dirty/change event")
	check(surface.get_code(Vector2(-0.0125, -0.0125)) == 12, "Negative native pixel lies inside the stroke")
	check(surface.get_code(Vector2(0.0125, 0.0125)) == 12, "Positive native pixel lies inside the stroke")
	check(surface.get_code(Vector2(0.1, 0.1)) == 0, "A fine stroke does not fill an entire terrain cell")
	for key: Vector2i in original:
		check(original[key] == null, "New chunk undo records restore transparency")
	for image: Image in surface.chunks.values():
		check(image.get_format() == Image.FORMAT_RGBAH and image.get_size() == Vector2i(256, 256), "Mask keeps native half-float storage and chunk dimensions")
	var redo := {}
	for key: Vector2i in surface.chunks: redo[key] = surface.chunks[key].duplicate()
	check(surface.paint_segment(Vector2.ZERO, Vector2.ZERO, 0.06, 13, true).is_empty(), "Eraser ignores other brush codes")
	check(regions.size() == 1 and changes == 1, "A no-op eraser emits no change")
	surface.apply_chunk_patch(original)
	check(surface.chunks.is_empty() and surface.get_code(Vector2.ZERO) == 0, "Undo restores missing chunks")
	surface.apply_chunk_patch(redo)
	check(surface.get_code(Vector2.ZERO) == 12, "Redo restores independent image snapshots")
	surface.paint_segment(Vector2.ZERO, Vector2.ZERO, 0.06, 12, true)
	check(surface.chunks.is_empty(), "Erasing the last native pixel removes its sparse chunk")
	var crossed := surface.paint_segment(Vector2(6.3, -0.1), Vector2(6.5, 0.1), 0.08, 7)
	check(crossed.size() == 4, "A continuous segment crosses positive and negative chunk boundaries")
	check(surface.get_code(Vector2(6.39, -0.01)) == 7 and surface.get_code(Vector2(6.41, 0.01)) == 7, "Continuous coverage has no gap at a chunk boundary")
	check(surface.get_code(Vector2(6.1, 0.3)) == 0, "Segment bounds do not paint pixels outside the circular footprint")
	var old_key := Vector2i(0, -1)
	var copy := surface.chunks[old_key].duplicate() as Image
	surface.paint_segment(Vector2(6.39, -0.01), Vector2(6.39, -0.01), 0.02, 13)
	check(copy.get_data() != surface.chunks[old_key].get_data(), "Subsequent painting does not mutate saved undo images")
	check(not surface.has_grass_in_cell(Vector2i.ZERO, 1.6), "Absent grass does not grant grass eligibility")
	surface.paint_segment(Vector2.ZERO, Vector2.ZERO, 0.04, 256)
	check(surface.has_grass_in_cell(Vector2i.ZERO, 1.6), "Grass coverage invalidates the cached cell result")
	check(surface.get_code(Vector2.ZERO) == 256, "Half-float mask represents grass code exactly")
	check(surface.paint_segment(Vector2.ZERO, Vector2.ZERO, 0.04, 12, true).is_empty(), "Stone eraser preserves grass pixels")
	surface.paint_segment(Vector2.ZERO, Vector2.ZERO, 0.04, 256, true)
	check(not surface.has_grass_in_cell(Vector2i.ZERO, 1.6), "Grass erasing invalidates the cached cell result")
	var stamp := TerrainSurfaceStamp.new()
	stamp.code = 21
	stamp.position = Vector2(-4.7, 3.9)
	stamp.size_meters = Vector2(3.0, 1.7)
	for angle in [0.0, 90.0, 37.0, -123.0, 405.0]:
		stamp.rotation_degrees = angle
		for uv in [Vector2(0.1, 0.2), Vector2(0.5, 0.5), Vector2(0.9, 0.8)]:
			var point: Vector2 = stamp.position + ((uv - Vector2.ONE * 0.5) * stamp.size_meters).rotated(deg_to_rad(angle))
			check(stamp.uv_at(point).is_equal_approx(uv) and stamp.contains_point(point), "Arbitrary-angle stamp UV preserves the whole source coordinate range")
		var expected_uvs := [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]
		var corners := stamp.get_corners()
		for index in corners.size():
			check(stamp.get_rect().grow(0.0001).has_point(corners[index]), "Rotated stamp bounds contain every complete-image corner")
			check(stamp.uv_at(corners[index]).is_equal_approx(expected_uvs[index]), "Stamp corners map to native source-image corners")
	check(not stamp.contains_point(stamp.position + Vector2(10, 0)), "Stamp does not claim pixels outside its rotated rectangle")
	surface.replace_stamps([stamp])
	check(surface.get_used_codes().has(21), "Stamp assets appear in the used-code list")
	regions.clear()
	var previous := stamp.get_rect()
	stamp.position += Vector2(12, 3)
	check(regions.size() == 1 and regions[0].encloses(previous) and regions[0].encloses(stamp.get_rect()), "Moving a stamp dirties old and new bounds")
	var grass_stamp := TerrainSurfaceStamp.new()
	grass_stamp.code = 256
	grass_stamp.position = Vector2.ZERO
	grass_stamp.size_meters = Vector2(0.3, 0.3)
	surface.replace_stamps([grass_stamp])
	check(surface.has_grass_in_cell(Vector2i.ZERO, 1.6), "Replacing stamps invalidates grass eligibility cache")
	surface.replace_stamps([])
	check(not surface.has_grass_in_cell(Vector2i.ZERO, 1.6), "Removing stamps restores grass eligibility")
	surface.paint_segment(Vector2(-6.45, 0.1), Vector2(-6.35, 0.1), 0.04, 257)
	check(surface.get_code(Vector2(-6.41, 0.1)) == 257 and surface.get_code(Vector2(-6.39, 0.1)) == 257, "Path code survives a negative chunk boundary")
	check(brush.texture_meters == Vector2(2.4, 2.4), "Changing brush coverage leaves texture repetition scale independent")
	var shared := Image.create_empty(256, 256, false, Image.FORMAT_RGBAH)
	shared.fill(Color(12, 0, 0, 0))
	var shared_surface := TerrainSurfaceData.new()
	shared_surface.chunks = {Vector2i.ZERO: shared, Vector2i.RIGHT: shared}
	var shared_before := shared_surface.paint_segment(Vector2(0.1, 0.1), Vector2(0.1, 0.1), 0.04, 13)
	check(shared_surface.get_code(Vector2(0.1, 0.1)) == 13, "Editing a shared chunk writes its selected pixels")
	check(shared_surface.get_code(Vector2(6.5, 0.1)) == 12, "Copy-on-write preserves another chunk sharing the same serialized image")
	check(roundi(shared.get_pixel(4, 4).r) == 12, "Copy-on-write leaves the shared image template unchanged")
	check(shared_surface.chunks[Vector2i.ZERO] != shared_surface.chunks[Vector2i.RIGHT], "The modified chunk detaches its image resource")
	shared_surface.apply_chunk_patch(shared_before)
	check(shared_surface.get_code(Vector2(0.1, 0.1)) == 12 and shared_surface.get_code(Vector2(6.5, 0.1)) == 12, "Shared-image undo restores the edited chunk without affecting siblings")
	var serial_surface := TerrainSurfaceData.new()
	var first_order := serial_surface.reserve_order()
	serial_surface.paint_segment(Vector2.ZERO, Vector2.ZERO, 0.04, 12, false, first_order)
	var second_order := serial_surface.reserve_order()
	var rebrush := serial_surface.paint_segment(Vector2.ZERO, Vector2.ZERO, 0.04, 12, false, second_order)
	var serial_pixel := serial_surface.chunks[Vector2i.ZERO].get_pixel(0, 0)
	check(not rebrush.is_empty() and TerrainSurfaceData.pixel_order(serial_pixel) == second_order, "Repainting the same material advances ordering above earlier stamps")
	check(serial_surface.paint_segment(Vector2.ZERO, Vector2.ZERO, 0.04, 12, false, second_order).is_empty(), "Repeated samples in the same stroke do not rewrite identical order")
	var order_image := Image.create_empty(1, 1, false, Image.FORMAT_RGBAH)
	for order in [1, 1023, 1024, 1048575, 1048576, 2147483647]:
		order_image.set_pixel(0, 0, TerrainSurfaceData.pixel_record(12, order))
		check(TerrainSurfaceData.pixel_order(order_image.get_pixel(0, 0)) == order, "Ten-bit words preserve exact order in half-float mask storage")
	stamp.rotation_degrees = 37.0
	stamp.flip_h = true
	var flipped_point := stamp.position + ((Vector2(0.2, 0.7) - Vector2.ONE * 0.5) * stamp.size_meters).rotated(deg_to_rad(37.0))
	check(stamp.uv_at(flipped_point).is_equal_approx(Vector2(0.8, 0.7)), "Horizontal mirror reverses source X without flipping Y at arbitrary rotation")
	stamp.layer_order = serial_surface.reserve_order()
	check(stamp.layer_order > second_order, "New stamps can retain the editor's reserved drawing order")
	DirAccess.make_dir_recursive_absolute(SCRATCH)
	var path := SCRATCH + "data-roundtrip.tres"
	var saved := ResourceSaver.save(surface, path)
	check(saved == OK, "Independent surface data saves outside project sources")
	if saved == OK:
		var loaded := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as TerrainSurfaceData
		check(loaded != null, "Surface resource loads back")
		if loaded:
			check(loaded.get_code(Vector2(-6.41, 0.1)) == 257 and loaded.get_used_codes().has(257), "Path code remains exact after half-float serialization")
	check([legacy.biomes, legacy.overlays, legacy.heights, legacy.paints] == legacy_arrays, "Free-surface painting does not alter legacy grid arrays")
	check(FileAccess.get_sha256(TERRAIN_PATH) == legacy_hash, "Legacy terrain file remains byte-identical")
	print("Terrain surface data: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
