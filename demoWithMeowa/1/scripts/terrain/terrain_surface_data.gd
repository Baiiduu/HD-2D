@tool
class_name TerrainSurfaceData
extends Resource

## 表面编辑与原有 1.6 米地形格独立。R 保存代码，GB/A 由渲染缓存处理。
signal region_changed(rect: Rect2)

const PIXELS_PER_METER := 40
const CHUNK_PIXELS := 256
const BRICK_PIXELS := 32
const BRICK_METERS := 0.8
const GRASS_CODE := 256
const PATH_CODE := 257

@export var drawing_serial := 0
@export var brush_snap_enabled := true

@export var chunks: Dictionary[Vector2i, Image] = {}:
	set(value):
		chunks = value
		_cache_ready = false
		_grass_cell_cache.clear()
@export var stamps: Array[TerrainSurfaceStamp] = []:
	set(value):
		var old_bounds := _stamp_bounds(stamps)
		_disconnect_stamps()
		stamps = value.duplicate()
		_connect_stamps()
		_grass_cell_cache.clear()
		_notify(_merge_rect(old_bounds, _stamp_bounds(stamps)))
## 石板重复相位沿用当前南侧烘焙布局；不会改变源纹理像素。
@export var texture_origin := Vector2(-15.2, 29.6):
	set(value):
		if texture_origin == value: return
		texture_origin = value
		_notify(get_bounds())

var _cache_ready := false
var _known_codes: Dictionary[int, bool] = {}
var _chunk_counts: Dictionary[Vector2i, int] = {}
var _chunk_grass_counts: Dictionary[Vector2i, int] = {}
var _grass_cell_cache: Dictionary[Vector2i, bool] = {}
var _grass_cell_size := 0.0
var _connected_stamps: Array[TerrainSurfaceStamp] = []
var _stamp_rects: Dictionary[TerrainSurfaceStamp, Rect2] = {}

func chunk_meters() -> float:
	return float(CHUNK_PIXELS) / PIXELS_PER_METER

func reserve_order() -> int:
	drawing_serial += 1
	return drawing_serial

func brick_rect(cell: Vector2i) -> Rect2:
	return Rect2(texture_origin + Vector2(cell) * BRICK_METERS, Vector2.ONE * BRICK_METERS)

func snap_brush_point(point: Vector2) -> Vector2:
	var cell := Vector2i(((point - texture_origin) / BRICK_METERS).floor())
	return brick_rect(cell).get_center()

func snap_stamp_point(point: Vector2, size: Vector2, angle: float, pivot_offset := Vector2.ZERO) -> Vector2:
	var radians := deg_to_rad(angle)
	var extent := Vector2(absf(cos(radians)) * size.x + absf(sin(radians)) * size.y,
		absf(sin(radians)) * size.x + absf(cos(radians)) * size.y)
	var corner := texture_origin + ((point - texture_origin - extent * 0.5) / BRICK_METERS).round() * BRICK_METERS
	# Odd-width ports rotate about their central source pixel, preserving the same seam.
	return corner + extent * 0.5 + pivot_offset - pivot_offset.rotated(radians)

func covered_bricks(start: Vector2, end: Vector2, radius: float) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var first := Vector2i(((start.min(end) - Vector2.ONE * radius - texture_origin) / BRICK_METERS).floor())
	var last := Vector2i(((start.max(end) + Vector2.ONE * radius - texture_origin) / BRICK_METERS).floor())
	var delta := end - start
	var length_squared := delta.length_squared()
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, y)
			var point := brick_rect(cell).get_center()
			var amount := clampf((point - start).dot(delta) / length_squared, 0.0, 1.0) if length_squared > 0.0 else 0.0
			if point.distance_squared_to(start + delta * amount) <= radius * radius + 0.000001:
				cells.append(cell)
	return cells

static func pixel_order(pixel: Color) -> int:
	if pixel.a >= 0.0: return 0
	return ((roundi(-pixel.a) - 1) << 20) | (roundi(pixel.b) << 10) | roundi(pixel.g)

static func pixel_record(code: int, order: int) -> Color:
	if code == 0: return Color(0, 0, 0, 0)
	if order == 0: return Color(code, 0, 0, 0)
	return Color(code, order & 1023, (order >> 10) & 1023, -float((order >> 20) + 1))

static func code_for_brush(brush: TerrainPaintBrush) -> int:
	if not brush: return 0
	if brush.target == TerrainPaintBrush.Target.GRASS: return GRASS_CODE
	if brush.target == TerrainPaintBrush.Target.PATH: return PATH_CODE
	return brush.paint_id

func get_code(point: Vector2) -> int:
	var pixel := Vector2i((point * PIXELS_PER_METER).floor())
	var key := Vector2i((Vector2(pixel) / CHUNK_PIXELS).floor())
	var image: Image = chunks.get(key)
	if not image: return 0
	var local := pixel - key * CHUNK_PIXELS
	return roundi(image.get_pixel(local.x, local.y).r)

func get_used_codes() -> PackedInt32Array:
	_ensure_cache()
	var codes := _known_codes.duplicate()
	for stamp in stamps:
		if stamp and stamp.code > 0: codes[stamp.code] = true
	var result := PackedInt32Array(codes.keys())
	result.sort()
	return result

func get_bounds() -> Rect2:
	var result := Rect2()
	for key: Vector2i in chunks:
		result = _merge_rect(result, _chunk_rect(key))
	return _merge_rect(result, _stamp_bounds(stamps))

## 每段仅检测段包围盒内的原生像素。返回的图片与现数据独立，供整笔撤销。
func paint_segment(start: Vector2, end: Vector2, radius: float, code: int, erase := false, order := 0, grid_snap := false) -> Dictionary:
	var before := {}
	if radius <= 0.0 or code < 1 or code > PATH_CODE or order < 0: return before
	var stroke_order := reserve_order() if order == 0 else order
	drawing_serial = maxi(drawing_serial, stroke_order)
	_ensure_cache()
	var margin := Vector2.ONE * radius
	var first := Vector2i(((start.min(end) - margin) * PIXELS_PER_METER).floor())
	var last := Vector2i(((start.max(end) + margin) * PIXELS_PER_METER).ceil()) - Vector2i.ONE
	var grid_cells := {}
	var grid_origin := Vector2i((texture_origin * PIXELS_PER_METER).round())
	if grid_snap:
		var cells := covered_bricks(start, end, radius)
		if cells.is_empty(): return before
		var minimum := cells[0]
		var maximum := cells[0]
		for cell in cells:
			grid_cells[cell] = true
			minimum = minimum.min(cell)
			maximum = maximum.max(cell)
		first = grid_origin + minimum * BRICK_PIXELS
		last = grid_origin + (maximum + Vector2i.ONE) * BRICK_PIXELS - Vector2i.ONE
	var first_chunk := Vector2i((Vector2(first) / CHUNK_PIXELS).floor())
	var last_chunk := Vector2i((Vector2(last) / CHUNK_PIXELS).floor())
	var delta := end - start
	var length_squared := delta.length_squared()
	var radius_squared := radius * radius
	var dirty := Rect2()
	for cz in range(first_chunk.y, last_chunk.y + 1):
		for cx in range(first_chunk.x, last_chunk.x + 1):
			var key := Vector2i(cx, cz)
			var image: Image = chunks.get(key)
			if erase and not image: continue
			var origin := key * CHUNK_PIXELS
			var minimum := first.max(origin)
			var maximum := last.min(origin + Vector2i.ONE * (CHUNK_PIXELS - 1))
			var touched := false
			var count := int(_chunk_counts.get(key, 0))
			var grass_count := int(_chunk_grass_counts.get(key, 0))
			for py in range(minimum.y, maximum.y + 1):
				for px in range(minimum.x, maximum.x + 1):
					if grid_snap:
						var cell := Vector2i((Vector2(Vector2i(px, py) - grid_origin) / BRICK_PIXELS).floor())
						if not grid_cells.has(cell): continue
					else:
						var point := (Vector2(px, py) + Vector2.ONE * 0.5) / PIXELS_PER_METER
						var amount := clampf((point - start).dot(delta) / length_squared, 0.0, 1.0) if length_squared > 0.0 else 0.0
						if point.distance_squared_to(start + delta * amount) > radius_squared: continue
					var local := Vector2i(px, py) - origin
					var previous_pixel := image.get_pixel(local.x, local.y) if image else Color(0, 0, 0, 0)
					var previous := roundi(previous_pixel.r)
					if erase and previous != code: continue
					if not erase and previous == code and pixel_order(previous_pixel) == stroke_order: continue
					if not touched:
						before[key] = image.duplicate() if image else null
						# Serialized masks may share identical Images across chunks.
						# Detach on the first actual write, preserving siblings and undo.
						image = image.duplicate() if image else Image.create_empty(CHUNK_PIXELS, CHUNK_PIXELS, false, Image.FORMAT_RGBAH)
						chunks[key] = image
						touched = true
					var next := 0 if erase else code
					image.set_pixel(local.x, local.y, pixel_record(next, stroke_order))
					if previous == 0: count += 1
					if next == 0: count -= 1
					if previous == GRASS_CODE: grass_count -= 1
					if next == GRASS_CODE: grass_count += 1
			if not touched: continue
			if count == 0:
				chunks.erase(key)
				_chunk_counts.erase(key)
				_chunk_grass_counts.erase(key)
			else:
				_chunk_counts[key] = count
				_chunk_grass_counts[key] = grass_count
			dirty = _merge_rect(dirty, _chunk_rect(key))
	if before.is_empty(): return before
	if not erase: _known_codes[code] = true
	_grass_cell_cache.clear()
	_notify(dirty)
	return before

func apply_chunk_patch(patch: Dictionary) -> void:
	_ensure_cache()
	var dirty := Rect2()
	for key: Vector2i in patch:
		var image: Image = patch[key]
		if image:
			assert(image.get_size() == Vector2i(CHUNK_PIXELS, CHUNK_PIXELS) and image.get_format() == Image.FORMAT_RGBAH)
			chunks[key] = image.duplicate() as Image
			_cache_chunk(key, chunks[key])
		else:
			chunks.erase(key)
			_chunk_counts.erase(key)
			_chunk_grass_counts.erase(key)
		dirty = _merge_rect(dirty, _chunk_rect(key))
	if patch.is_empty(): return
	_grass_cell_cache.clear()
	_notify(dirty)

func replace_stamps(values: Array[TerrainSurfaceStamp]) -> void:
	stamps = values

## 保守的可铺草查询；实际透明图块覆盖应由渲染层结合纹理 alpha 判断。
func has_grass_in_cell(cell: Vector2i, cell_size: float) -> bool:
	if cell_size <= 0.0: return false
	_ensure_cache()
	if not is_equal_approx(_grass_cell_size, cell_size):
		_grass_cell_cache.clear()
		_grass_cell_size = cell_size
	if _grass_cell_cache.has(cell): return _grass_cell_cache[cell]
	var rect := Rect2((Vector2(cell) - Vector2.ONE * 0.5) * cell_size, Vector2.ONE * cell_size)
	var first := Vector2i((rect.position * PIXELS_PER_METER).floor())
	var last := Vector2i((rect.end * PIXELS_PER_METER).ceil()) - Vector2i.ONE
	var first_chunk := Vector2i((Vector2(first) / CHUNK_PIXELS).floor())
	var last_chunk := Vector2i((Vector2(last) / CHUNK_PIXELS).floor())
	for cz in range(first_chunk.y, last_chunk.y + 1):
		for cx in range(first_chunk.x, last_chunk.x + 1):
			var key := Vector2i(cx, cz)
			if int(_chunk_grass_counts.get(key, 0)) == 0: continue
			var origin := key * CHUNK_PIXELS
			var minimum := first.max(origin) - origin
			var maximum := last.min(origin + Vector2i.ONE * (CHUNK_PIXELS - 1)) - origin
			var image: Image = chunks[key]
			for py in range(minimum.y, maximum.y + 1):
				for px in range(minimum.x, maximum.x + 1):
					if roundi(image.get_pixel(px, py).r) == GRASS_CODE:
						_grass_cell_cache[cell] = true
						return true
	for stamp in stamps:
		if not stamp or stamp.code != GRASS_CODE or not rect.intersects(stamp.get_rect()): continue
		var cell_polygon := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
			rect.end, Vector2(rect.position.x, rect.end.y)])
		if not Geometry2D.intersect_polygons(cell_polygon, stamp.get_corners()).is_empty():
			_grass_cell_cache[cell] = true
			return true
	_grass_cell_cache[cell] = false
	return false

func _ensure_cache() -> void:
	if _cache_ready: return
	_known_codes.clear()
	_chunk_counts.clear()
	_chunk_grass_counts.clear()
	var counted: Dictionary[Image, Vector2i] = {}
	for key: Vector2i in chunks:
		var image: Image = chunks[key]
		if counted.has(image):
			_chunk_counts[key] = counted[image].x
			_chunk_grass_counts[key] = counted[image].y
		else:
			_cache_chunk(key, image)
			counted[image] = Vector2i(_chunk_counts[key], _chunk_grass_counts[key])
	_cache_ready = true

func _cache_chunk(key: Vector2i, image: Image) -> void:
	var count := 0
	var grass := 0
	for y in image.get_height():
		for x in image.get_width():
			var code := roundi(image.get_pixel(x, y).r)
			if code == 0: continue
			_known_codes[code] = true
			count += 1
			if code == GRASS_CODE: grass += 1
	_chunk_counts[key] = count
	_chunk_grass_counts[key] = grass

func _chunk_rect(key: Vector2i) -> Rect2:
	return Rect2(Vector2(key) * chunk_meters(), Vector2.ONE * chunk_meters())

func _stamp_bounds(values: Array[TerrainSurfaceStamp]) -> Rect2:
	var result := Rect2()
	for stamp in values:
		if stamp: result = _merge_rect(result, stamp.get_rect())
	return result

func _merge_rect(first: Rect2, second: Rect2) -> Rect2:
	if not first.has_area(): return second
	if not second.has_area(): return first
	return first.merge(second)

func _notify(rect: Rect2) -> void:
	if rect.has_area(): region_changed.emit(rect)
	emit_changed()

func _disconnect_stamps() -> void:
	for stamp in _connected_stamps:
		var callback := _on_stamp_changed.bind(stamp)
		if stamp.changed.is_connected(callback): stamp.changed.disconnect(callback)
	_connected_stamps.clear()
	_stamp_rects.clear()

func _connect_stamps() -> void:
	for stamp in stamps:
		if not stamp or _connected_stamps.has(stamp): continue
		stamp.changed.connect(_on_stamp_changed.bind(stamp))
		_connected_stamps.append(stamp)
		_stamp_rects[stamp] = stamp.get_rect()

func _on_stamp_changed(stamp: TerrainSurfaceStamp) -> void:
	var previous: Rect2 = _stamp_rects.get(stamp, Rect2())
	var current := stamp.get_rect()
	_stamp_rects[stamp] = current
	_grass_cell_cache.clear()
	_notify(_merge_rect(previous, current))
