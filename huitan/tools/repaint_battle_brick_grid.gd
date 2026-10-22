extends SceneTree

const SURFACE := "res://data/world/world_surface.res"
const PALETTE := "res://data/world/spawn_paint_palette.tres"
const RECT := Rect2(-15.2, 29.6, 30.4, 30.4)
const OUTPUT := "D:/.codexfile/work/battle-grid-repaint/world_surface.tres"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var input_hash := FileAccess.get_sha256(SURFACE)
	var current := load(SURFACE) as TerrainSurfaceData
	var palette := load(PALETTE) as TerrainPaintPalette
	var result := build(current, palette)
	if FileAccess.get_sha256(SURFACE) != input_hash:
		push_error("地图在重绘期间发生变化，未写出。")
		quit(1)
		return
	var error := ResourceSaver.save(result, OUTPUT)
	print("STAGED brick grid: 38x38 complete bricks, ", result.stamps.size(), " native brush stamps; source unchanged; ", OUTPUT)
	quit(0 if error == OK else 1)

static func build(current: TerrainSurfaceData, palette: TerrainPaintPalette) -> TerrainSurfaceData:
	var result := current.duplicate(true) as TerrainSurfaceData
	result.brush_snap_enabled = true
	var origin := Vector2i((RECT.position * TerrainSurfaceData.PIXELS_PER_METER).round())
	var writable := {}
	# Keep each painted region, with its boundary resolved to whole native stone bricks.
	for by in 38:
		for bx in 38:
			var pixel_start := origin + Vector2i(bx, by) * 32
			var counts := {}
			var last_order := -1
			for y in 32:
				for x in 32:
					var pixel := pixel_start + Vector2i(x, y)
					var key := Vector2i((Vector2(pixel) / 256).floor())
					var image: Image = current.chunks.get(key)
					if not image: continue
					var record := image.get_pixelv(pixel - key * 256)
					var code := roundi(record.r)
					if code == 0: continue
					var order := TerrainSurfaceData.pixel_order(record)
					if order > last_order:
						last_order = order
						counts.clear()
					if order == last_order: counts[code] = int(counts.get(code, 0)) + 1
			var chosen := 12
			var most := 0
			for code: int in counts:
				if counts[code] > most:
					chosen = code
					most = counts[code]
			var key := Vector2i((Vector2(pixel_start) / 256).floor())
			if not writable.has(key):
				var old: Image = result.chunks.get(key)
				result.chunks[key] = old.duplicate() if old else Image.create_empty(256, 256, false, Image.FORMAT_RGBAH)
				writable[key] = true
			# Both grid and chunks use multiples of 32 native pixels.
			result.chunks[key].fill_rect(Rect2i(pixel_start - key * 256, Vector2i(32,32)),
				TerrainSurfaceData.pixel_record(chosen, maxi(0, last_order)))
	var stamps: Array[TerrainSurfaceStamp] = []
	# 38 bricks wide: native 3-brick sections meet at full brick boundaries.
	for row in [0, 9, 28, 37]:
		for start in [0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 35]:
			_place(result, palette, stamps, 22, RECT.position + Vector2(start+1.5, row+0.5)*0.8)
	for column in [0, 9, 28, 37]:
		for start in [0, 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 35]:
			_place(result, palette, stamps, 23, RECT.position + Vector2(column+0.5, start+1.5)*0.8)
	for x in [9, 28]:
		for y in [9, 28]:
			_place(result, palette, stamps, 17, RECT.position + Vector2(x+0.5,y+0.5)*0.8)
	for corner in [Vector3(0,0,90), Vector3(37,0,180), Vector3(0,37,0), Vector3(37,37,-90)]:
		_place(result, palette, stamps, 18, RECT.position + Vector2(corner.x+0.5,corner.y+0.5)*0.8, corner.z)
	for column in [9, 28]:
		for row in [3, 18, 34]:
			_place(result, palette, stamps, 24, RECT.position + Vector2(column+0.5,row+0.5)*0.8)
	for row in [9, 28]:
		for column in [3, 18, 34]:
			_place(result, palette, stamps, 24, RECT.position + Vector2(column+0.5,row+0.5)*0.8)
	_place(result, palette, stamps, 21, RECT.get_center())
	_place(result, palette, stamps, 20, RECT.get_center()+Vector2(2.4,0))
	_place(result, palette, stamps, 20, RECT.get_center()-Vector2(2.4,0), 0, true)
	for old in current.stamps:
		if not old or (old.layer_order == 0 and old.code in [22,23,17,18,24,21,20]): continue
		var stamp := old.duplicate(true) as TerrainSurfaceStamp
		if RECT.has_point(stamp.position):
			stamp.rotation_degrees = roundf(stamp.rotation_degrees/90.0)*90.0
			stamp.size_meters = (stamp.size_meters/0.8).round().max(Vector2.ONE)*0.8
			var brush := palette.brush_for_id(stamp.code)
			stamp.position = result.snap_stamp_point(stamp.position,stamp.size_meters,stamp.rotation_degrees,
				brush.snap_pivot_offset if brush else Vector2.ZERO)
		stamps.append(stamp)
	result.replace_stamps(stamps)
	var images: Dictionary[String, Image] = {}
	for key: Vector2i in result.chunks:
		var image: Image = result.chunks[key]
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(image.get_data())
		var digest := hash.finish().hex_encode()
		if images.has(digest): result.chunks[key] = images[digest]
		else: images[digest] = image
	return result

static func _place(data: TerrainSurfaceData, palette: TerrainPaintPalette,
		stamps: Array[TerrainSurfaceStamp], code: int, point: Vector2, angle := 0.0, flip := false) -> void:
	var brush := palette.brush_for_id(code)
	var stamp := TerrainSurfaceStamp.new()
	stamp.code = code
	stamp.size_meters = brush.texture_meters
	stamp.rotation_degrees = angle
	stamp.flip_h = flip
	stamp.position = data.snap_stamp_point(point,stamp.size_meters,angle,brush.snap_pivot_offset)
	stamp.clip_rect = RECT
	stamps.append(stamp)
