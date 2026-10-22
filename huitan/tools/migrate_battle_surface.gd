extends SceneTree

const OUTPUT := "D:/.codexfile/work/free-surface-painter/battle_surface.tres"
const BEFORE := "D:/.codexfile/work/free-surface-painter/before/"
const TERRAIN_PATH := "res://data/world/world_terrain.tres"
const SURFACE_PATH := "res://data/world/world_surface.res"
const PALETTE_PATH := "res://data/world/spawn_paint_palette.tres"
const SOURCE := "res://assets/meowa/city_plaza/fixed/"
const WORLD_RECT := Rect2(-15.2, 29.6, 30.4, 30.4)
const PPM := 40
const SIZE := 1216
const TILE_SIZE := 96

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(BEFORE)
	var terrain_hash := FileAccess.get_sha256(TERRAIN_PATH)
	var surface_hash := FileAccess.get_sha256(SURFACE_PATH)
	for path: String in [TERRAIN_PATH, SURFACE_PATH]:
		var backup := BEFORE + path.get_file()
		if not FileAccess.file_exists(backup):
			var copied := DirAccess.copy_absolute(ProjectSettings.globalize_path(path), backup)
			if copied != OK:
				push_error("无法备份迁移源：" + path)
				quit(1)
				return
	var terrain := load(TERRAIN_PATH) as TerrainData
	var current := load(SURFACE_PATH) as TerrainSurfaceData
	var palette := load(PALETTE_PATH) as TerrainPaintPalette
	var built := build_migrated(terrain, current, palette)
	if built.is_empty():
		quit(1)
		return
	if FileAccess.get_sha256(TERRAIN_PATH) != terrain_hash or FileAccess.get_sha256(SURFACE_PATH) != surface_hash:
		push_error("迁移期间原地图已改变，停止写出。")
		quit(1)
		return
	var surface: TerrainSurfaceData = built["data"]
	if ResourceSaver.save(surface, OUTPUT) != OK:
		push_error("无法保存迁移审阅资源：" + OUTPUT)
		quit(1)
		return
	print(JSON.stringify(built["stats"]))
	print("STAGED: ", OUTPUT, "; original terrain and surface SHA unchanged")
	quit()

## 独立可审查的配方基线。与 NumPy seed 13102026 的现有 base_tiles 对应，
## 不使用 Godot 的另一种 RNG，也不读取任何已绘制表面作为烘焙底图。
static func generate_template() -> TerrainSurfaceData:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE + "battle/layout.json"))
	assert(parsed is Dictionary and parsed.has("base_tiles"))
	var layout: Dictionary = parsed
	assert(layout.base_tiles.size() == 169 and int(layout.seed) == 13102026)
	var mask := Image.create_empty(SIZE, SIZE, false, Image.FORMAT_RGBAH)
	var patterns: Array[Vector2i] = []
	for entry in layout.base_tiles:
		var x := int(entry[0])
		var y := int(entry[1])
		var code := int(entry[2])
		assert(code in [12, 13, 14])
		if code == 14:
			if not _pattern_allowed(x, y): code = 12
			else: patterns.append(Vector2i(x, y))
		mask.fill_rect(Rect2i(x, y, mini(TILE_SIZE, SIZE - x), mini(TILE_SIZE, SIZE - y)),
			TerrainSurfaceData.pixel_record(code, 0))
	assert(patterns == [Vector2i(480, 96), Vector2i(1056, 96)])
	var surface := TerrainSurfaceData.new()
	surface.texture_origin = WORLD_RECT.position
	var world_origin := Vector2i((WORLD_RECT.position * PPM).round())
	var world_pixels := Rect2i(world_origin, Vector2i(SIZE, SIZE))
	var first := Vector2i((Vector2(world_origin) / TerrainSurfaceData.CHUNK_PIXELS).floor())
	var last := Vector2i((Vector2(world_pixels.end - Vector2i.ONE) / TerrainSurfaceData.CHUNK_PIXELS).floor())
	for cy in range(first.y, last.y + 1):
		for cx in range(first.x, last.x + 1):
			var key := Vector2i(cx, cy)
			var chunk_origin := key * TerrainSurfaceData.CHUNK_PIXELS
			var overlap := Rect2i(chunk_origin, Vector2i.ONE * TerrainSurfaceData.CHUNK_PIXELS).intersection(world_pixels)
			var image := Image.create_empty(256, 256, false, Image.FORMAT_RGBAH)
			image.blit_rect(mask, Rect2i(overlap.position - world_origin, overlap.size), overlap.position - chunk_origin)
			surface.chunks[key] = image
	var stamps: Array[TerrainSurfaceStamp] = []
	var low := 12
	var high := SIZE - 13
	for x in [288, 928]: _line(stamps, x, low, x, high)
	for y in [288, 928]: _line(stamps, low, y, high, y)
	for x in [288, 928]:
		for y in [288, 928]: _place(stamps, 17, Vector2(x - 48, y - 48), Vector2(96, 96))
	_line(stamps, low, low, high, low)
	_line(stamps, low, high, high, high)
	_line(stamps, low, low, low, high)
	_line(stamps, high, low, high, high)
	# Native UP/RIGHT corner. Match Pillow's rotations and odd-width port shifts.
	_place(stamps, 18, Vector2(low - 48, high - 48), Vector2(96, 96))
	_place(stamps, 18, Vector2(low - 48, low - 48 + 1), Vector2(96, 96), 90.0)
	_place(stamps, 18, Vector2(high - 48 + 1, low - 48 + 1), Vector2(96, 96), 180.0)
	_place(stamps, 18, Vector2(high - 48 + 1, high - 48), Vector2(96, 96), -90.0)
	for x in [288, 928]:
		for y in [96, 608, 1120]: _place(stamps, 24, Vector2(x - 12, y - 12), Vector2(25, 25))
	for y in [288, 928]:
		for x in [96, 608, 1120]: _place(stamps, 24, Vector2(x - 12, y - 12), Vector2(25, 25))
	var octagon := Image.load_from_file(ProjectSettings.globalize_path(SOURCE + "octagon_cutout.png"))
	var octagon_size := Vector2(octagon.get_size())
	_place(stamps, 21, Vector2.ONE * (SIZE * 0.5) - octagon_size * 0.5, octagon_size)
	var arrow := Image.load_from_file(ProjectSettings.globalize_path(SOURCE + "10-arrow.png"))
	var arrow_size := Vector2(arrow.get_size())
	var alpha_bounds := arrow.get_used_rect()
	var center := SIZE / 2
	var right := center + 56 + 8 - alpha_bounds.position.x
	var left := center - 56 - 8 - (arrow.get_width() - alpha_bounds.position.x)
	_place(stamps, 20, Vector2(right, center - arrow_size.y * 0.5), arrow_size)
	_place(stamps, 20, Vector2(left, center - arrow_size.y * 0.5), arrow_size, 0.0, true)
	surface.replace_stamps(stamps)
	_deduplicate_images(surface)
	return surface

static func build_migrated(terrain: TerrainData, current: TerrainSurfaceData,
		palette: TerrainPaintPalette) -> Dictionary:
	var surface := generate_template()
	var writable := {}
	var hand_cells: Array[Vector3i] = []
	for z in range(19, 38):
		for x in range(-9, 10):
			var cell := Vector2i(x, z)
			if not terrain.has_cell(cell):
				push_error("南侧迁移覆盖范围超出原地图。")
				return {}
			var index := (z - terrain.origin.y) * terrain.size.x + x - terrain.origin.x
			var id := terrain.paint_at_index(index)
			if id == 11: continue
			var brush := palette.brush_for_id(id)
			if id == 0 or not brush:
				push_error("旧手绘格 %s 编号 %d 无明确素材映射，停止迁移以保留原图。" % [cell, id])
				return {}
			hand_cells.append(Vector3i(x, z, id))
			var start := Vector2i(((Vector2(cell) - Vector2.ONE * 0.5) * terrain.cell_size * PPM).round())
			var span := roundi(terrain.cell_size * PPM)
			for py in range(start.y, start.y + span):
				for px in range(start.x, start.x + span):
					var key := Vector2i((Vector2(px, py) / TerrainSurfaceData.CHUNK_PIXELS).floor())
					var image := _writable_chunk(surface, key, writable)
					var local := Vector2i(px, py) - key * TerrainSurfaceData.CHUNK_PIXELS
					image.set_pixelv(local, TerrainSurfaceData.pixel_record(id, 1))
	var kept_pixels := 0
	var largest_order := 1
	if current:
		for key: Vector2i in current.chunks:
			var source: Image = current.chunks[key]
			var destination: Image
			for y in source.get_height():
				for x in source.get_width():
					var pixel := source.get_pixel(x, y)
					var code := roundi(pixel.r)
					if code == 0: continue
					if not destination: destination = _writable_chunk(surface, key, writable)
					var order := maxi(1, TerrainSurfaceData.pixel_order(pixel) + 1)
					destination.set_pixel(x, y, TerrainSurfaceData.pixel_record(code, order))
					largest_order = maxi(largest_order, order)
					kept_pixels += 1
		var combined: Array[TerrainSurfaceStamp] = surface.stamps.duplicate()
		for source_stamp in current.stamps:
			if not source_stamp: continue
			var stamp := source_stamp.duplicate(true) as TerrainSurfaceStamp
			stamp.layer_order = maxi(2, source_stamp.layer_order + 1)
			largest_order = maxi(largest_order, stamp.layer_order)
			combined.append(stamp)
		surface.replace_stamps(combined)
		largest_order = maxi(largest_order, current.drawing_serial + 1)
	surface.drawing_serial = largest_order
	var unique := _deduplicate_images(surface)
	var stamp_counts := {}
	for stamp in surface.stamps:
		stamp_counts[stamp.code] = int(stamp_counts.get(stamp.code, 0)) + 1
	var stats := {"world_rect": [-15.2, 29.6, 30.4, 30.4], "seed": 13102026,
		"base_tiles": 169, "pattern_tiles": [[480, 96], [1056, 96]],
		"chunks": surface.chunks.size(), "unique_images": unique,
		"template_stamps": 31, "total_stamps": surface.stamps.size(), "stamp_counts": stamp_counts,
		"preserved_legacy_cells": hand_cells, "preserved_free_pixels": kept_pixels,
		"drawing_serial": surface.drawing_serial, "independent_diamond_enabled": false}
	return {"data": surface, "stats": stats}

static func _pattern_allowed(x: int, y: int) -> bool:
	if mini(x, y) < 57 or maxi(x + 96, y + 96) > 1159: return false
	for band in [288, 928]:
		var start: int = band - 12 - 32
		var finish: int = band + 13 + 32
		if (x < finish and x + 96 > start) or (y < finish and y + 96 > start): return false
	return not (x < 768 and x + 96 > 448 and y < 700 and y + 96 > 516)

static func _line(stamps: Array[TerrainSurfaceStamp], x0: int, y0: int, x1: int, y1: int) -> void:
	if y0 == y1:
		_place(stamps, 22, Vector2(x0, y0 - 12), Vector2(x1 - x0 + 1, 25))
	else:
		_place(stamps, 23, Vector2(x0 - 12, y0), Vector2(25, y1 - y0 + 1))

static func _place(stamps: Array[TerrainSurfaceStamp], code: int, origin: Vector2,
		size: Vector2, rotation := 0.0, flip_h := false) -> void:
	var stamp := TerrainSurfaceStamp.new()
	stamp.code = code
	stamp.position = WORLD_RECT.position + (origin + size * 0.5) / PPM
	stamp.size_meters = size / PPM
	stamp.rotation_degrees = rotation
	stamp.flip_h = flip_h
	stamp.layer_order = 0
	stamp.clip_rect = WORLD_RECT
	stamps.append(stamp)

static func _writable_chunk(surface: TerrainSurfaceData, key: Vector2i, writable: Dictionary) -> Image:
	if not writable.has(key):
		var existing: Image = surface.chunks.get(key)
		surface.chunks[key] = existing.duplicate() if existing else Image.create_empty(256, 256, false, Image.FORMAT_RGBAH)
		writable[key] = true
	return surface.chunks[key]

static func _deduplicate_images(surface: TerrainSurfaceData) -> int:
	var images: Dictionary[String, Image] = {}
	for key: Vector2i in surface.chunks:
		var image: Image = surface.chunks[key]
		var hashing := HashingContext.new()
		hashing.start(HashingContext.HASH_SHA256)
		hashing.update(image.get_data())
		var digest := hashing.finish().hex_encode()
		if images.has(digest): surface.chunks[key] = images[digest]
		else: images[digest] = image
	return images.size()
