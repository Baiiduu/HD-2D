@tool
class_name TerrainSurfaceCanvas
extends Node

## Runtime-only sparse surface textures; generated GPU resources never enter materials on disk.
const CHUNK_PIXELS := 256
const PIXELS_PER_METER := 40.0
const CHUNK_METERS := CHUNK_PIXELS / PIXELS_PER_METER
const GRASS_CODE := 256
const PATH_CODE := 257
const FIRST_CAPACITY := 16

var _terrain: Terrain
var _data: TerrainSurfaceData
var _bound_materials: Array[ShaderMaterial] = []
var _source_images: Dictionary[int, Image] = {}
var _source_pixels: Dictionary[int, PackedByteArray] = {}
var _source_brushes: Dictionary[int, TerrainPaintBrush] = {}
var _grass_codes: Dictionary[int, bool] = {}
var _has_grass_source := false
var _used_codes := PackedInt32Array()
var _ordered_stamps: Array[TerrainSurfaceStamp] = []
var _sources_dirty := true
var _composition_sources: Dictionary = {}
var _albedo: Texture2DArray
var _normal: Texture2DArray
var _material: Texture2DArray
var _meta: ImageTexture
var _layers: Texture2DArray
var _layer_images: Array[Image] = []
var _layer_by_chunk: Dictionary[Vector2i, int] = {}
var _lookup: ImageTexture
var _lookup_origin := Vector2i.ZERO
var _lookup_size := Vector2i.ZERO
var _blank: Image
var _dirty_chunks: Dictionary[Vector2i, bool] = {}
var _full_refresh := true
var _refresh_queued := false
var _grass_cells: Dictionary[Vector2i, bool] = {}


func configure(terrain: Terrain) -> void:
	if _terrain and _terrain.paint_palette_applied.is_connected(_on_palette_applied):
		_terrain.paint_palette_applied.disconnect(_on_palette_applied)
	if _data and _data.region_changed.is_connected(queue_region_refresh):
		_data.region_changed.disconnect(queue_region_refresh)
	_disable_materials()
	_terrain = terrain
	_data = terrain.surface_data if terrain else null
	if _terrain:
		_terrain.paint_palette_applied.connect(_on_palette_applied)
	if _data:
		_data.region_changed.connect(queue_region_refresh)
	_sources_dirty = true
	_source_images.clear()
	_source_pixels.clear()
	_source_brushes.clear()
	rebuild()


func rebuild() -> void:
	_full_refresh = true
	_grass_cells.clear()
	_queue_refresh()


func queue_region_refresh(rect: Rect2) -> void:
	for key in _keys_for_rect(rect):
		_dirty_chunks[key] = true
	_grass_cells.clear()
	_queue_refresh()


func queue_dirty(rect: Rect2) -> void:
	queue_region_refresh(rect)


func _queue_refresh() -> void:
	if _refresh_queued: return
	_refresh_queued = true
	_flush.call_deferred()


func _on_palette_applied() -> void:
	_sources_dirty = true
	_source_images.clear()
	_source_pixels.clear()
	_source_brushes.clear()
	_grass_cells.clear()
	_queue_refresh()


func _flush() -> void:
	if not _refresh_queued: return
	_refresh_queued = false
	if not is_instance_valid(_terrain) or not _data:
		_disable()
		return
	if _data.chunks.is_empty() and _data.stamps.is_empty():
		_disable()
		return
	var codes := _data.get_used_codes()
	if codes.is_empty():
		_disable()
		return
	if _sources_dirty or codes != _used_codes:
		_prepare_sources(codes)
	_sort_stamps()
	var keys := _active_keys()
	if keys.is_empty():
		_disable()
		return
	var changed_keys: Dictionary[Vector2i, bool] = {}
	for key in _layer_by_chunk.keys():
		if not keys.has(key):
			var previous: int = _layer_by_chunk[key]
			if previous < _layer_images.size(): _layer_images[previous] = _blank_image()
			_layer_by_chunk.erase(key)
	for key in keys:
		if not _layer_by_chunk.has(key):
			_layer_by_chunk[key] = _free_layer()
			changed_keys[key] = true
		if _full_refresh or _dirty_chunks.has(key):
			changed_keys[key] = true
	var needed := 0
	for layer in _layer_by_chunk.values():
		needed = maxi(needed, layer + 1)
	var grow := needed > _layer_images.size() or not _layers
	if grow:
		var capacity := maxi(FIRST_CAPACITY, _layer_images.size())
		while capacity < needed: capacity *= 2
		while _layer_images.size() < capacity:
			_layer_images.append(_blank_image())
	for key in changed_keys:
		var layer: int = _layer_by_chunk[key]
		var image := _compose_chunk(key)
		_layer_images[layer] = image
		if not grow: _layers.update_layer(image, layer)
	if grow:
		_layers = Texture2DArray.new()
		if _layers.create_from_images(_layer_images) != OK:
			push_error("无法创建自由地表纹理数组。")
			_disable()
			return
	_update_lookup(keys)
	_bind()
	_dirty_chunks.clear()
	_full_refresh = false

func _free_layer() -> int:
	var occupied := {}
	for layer in _layer_by_chunk.values(): occupied[layer] = true
	var result := 0
	while occupied.has(result): result += 1
	return result


func _blank_image() -> Image:
	if not _blank:
		_blank = Image.create_empty(CHUNK_PIXELS, CHUNK_PIXELS, false, Image.FORMAT_RGBAH)
		_blank.fill(Color(0, 0, 0, 0))
	return _blank


func _active_keys() -> Dictionary[Vector2i, bool]:
	var result: Dictionary[Vector2i, bool] = {}
	var bounds := _terrain.data.get_world_rect()
	for key in _data.chunks:
		if Rect2(Vector2(key) * CHUNK_METERS, Vector2.ONE * CHUNK_METERS).intersects(bounds): result[key] = true
	for stamp in _data.stamps:
		if not stamp: continue
		for key in _keys_for_rect(stamp.get_rect().intersection(bounds)): result[key] = true
	return result


func _sort_stamps() -> void:
	var indices: Array[int] = []
	for index in _data.stamps.size():
		if _data.stamps[index]: indices.append(index)
	indices.sort_custom(func(one: int, two: int) -> bool:
		var first := _data.stamps[one].layer_order
		var second := _data.stamps[two].layer_order
		return first < second if first != second else one < two)
	_ordered_stamps.clear()
	for index in indices: _ordered_stamps.append(_data.stamps[index])


func _keys_for_rect(rect: Rect2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not rect.has_area(): return result
	var start := Vector2i((rect.position / CHUNK_METERS).floor())
	var finish := Vector2i((rect.end / CHUNK_METERS).ceil())
	for y in range(start.y, finish.y):
		for x in range(start.x, finish.x): result.append(Vector2i(x, y))
	return result


func _compose_chunk(key: Vector2i) -> Image:
	var base: Image = _data.chunks.get(key)
	var image: Image = base.duplicate() if base else _blank_image().duplicate()
	var origin := Vector2(key) * CHUNK_METERS
	var chunk_rect := Rect2(origin, Vector2.ONE * CHUNK_METERS)
	for stamp in _ordered_stamps:
		if not stamp or not _source_images.has(stamp.code): continue
		var rect := stamp.get_rect().intersection(chunk_rect)
		if not rect.has_area(): continue
		var source: Image = _source_images[stamp.code]
		var source_pixels: PackedByteArray = _source_pixels[stamp.code]
		var source_size := Vector2(source.get_size())
		var source_width := source.get_width()
		var first := Vector2i(((rect.position - origin) * PIXELS_PER_METER).floor())
		var last := Vector2i(((rect.end - origin) * PIXELS_PER_METER).ceil())
		first = first.clamp(Vector2i.ZERO, Vector2i.ONE * CHUNK_PIXELS)
		last = last.clamp(Vector2i.ZERO, Vector2i.ONE * CHUNK_PIXELS)
		# The affine UV steps preserve rotation and reflection without trigonometry per pixel.
		var start_point := origin + (Vector2(first) + Vector2.ONE * 0.5) / PIXELS_PER_METER
		var start_uv := stamp.uv_at(start_point)
		var step_x := stamp.uv_at(start_point + Vector2(1.0 / PIXELS_PER_METER, 0.0)) - start_uv
		var step_y := stamp.uv_at(start_point + Vector2(0.0, 1.0 / PIXELS_PER_METER)) - start_uv
		for y in range(first.y, last.y):
			var row_uv := start_uv + step_y * (y - first.y)
			for x in range(first.x, last.x):
				var uv := row_uv + step_x * (x - first.x)
				if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0: continue
				var pixel := Vector2i((uv * source_size).floor())
				if source_pixels[(pixel.y * source_width + pixel.x) * 4 + 3] <= 127: continue
				if base and TerrainSurfaceData.pixel_order(base.get_pixel(x, y)) > stamp.layer_order: continue
				image.set_pixel(x, y, Color(stamp.code, uv.x, uv.y, 1.0))
	return image


func _update_lookup(keys: Dictionary[Vector2i, bool]) -> void:
	var first: Vector2i = keys.keys()[0]
	var last := first
	for key in keys:
		first = first.min(key)
		last = last.max(key)
	var size := last - first + Vector2i.ONE
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for key in keys:
		var layer := _layer_by_chunk[key] + 1
		image.set_pixelv(key - first, Color(float(layer & 255) / 255.0, float((layer >> 8) & 255) / 255.0, 0, 1))
	if _lookup and size == _lookup_size:
		_lookup.update(image)
	else:
		_lookup = ImageTexture.create_from_image(image)
	_lookup_origin = first
	_lookup_size = size


func _brush_for_code(code: int) -> TerrainPaintBrush:
	if not _terrain.paint_palette: return null
	if code < GRASS_CODE: return _terrain.paint_palette.brush_for_id(code)
	var target := TerrainPaintBrush.Target.GRASS if code == GRASS_CODE else TerrainPaintBrush.Target.PATH
	for brush in _terrain.paint_palette.brushes:
		if brush and brush.target == target: return brush
	return null


func _source_image(brush: TerrainPaintBrush, normal := false, material := false) -> Image:
	var image := brush.material_image() if material else (brush.normal_image() if normal else brush.source_image())
	if not image: return null
	if brush.mode == TerrainPaintBrush.Mode.CORNER_ATLAS:
		if brush.atlas_grid.x < 1 or brush.atlas_grid.y < 1 or brush.corner_tiles.size() < 16: return null
		var size := image.get_size() / brush.atlas_grid
		image = image.get_region(Rect2i(Vector2i(brush.corner_tiles[15]) * size, size))
	return image


func _prepare_sources(codes: PackedInt32Array) -> void:
	var composition_sources := {}
	_used_codes = codes.duplicate()
	_sources_dirty = false
	_grass_codes.clear()
	_has_grass_source = false
	var albedo_images: Array[Image] = []
	var normal_images: Array[Image] = []
	var material_images: Array[Image] = []
	var valid_codes := PackedInt32Array()
	var albedo_size := Vector2i.ONE
	var normal_size := Vector2i.ONE
	for code in codes:
		if code < 1 or code > PATH_CODE: continue
		var brush := _brush_for_code(code)
		if not brush or not brush.texture: continue
		var image: Image = _source_images.get(code)
		if not image:
			image = _source_image(brush)
			if not image: continue
			_source_images[code] = image
		if not _source_pixels.has(code): _source_pixels[code] = image.get_data()
		composition_sources[code] = [image.get_size(), _source_pixels[code]]
		_source_brushes[code] = brush
		var normal := _source_image(brush, true)
		albedo_images.append(image)
		normal_images.append(normal)
		material_images.append(_source_image(brush,false,true))
		valid_codes.append(code)
		albedo_size = albedo_size.max(image.get_size())
		if normal: normal_size = normal_size.max(normal.get_size())
		_grass_codes[code] = code == GRASS_CODE or brush.is_grass
		_has_grass_source = _has_grass_source or _grass_codes[code]
	# Tint, normals and material values do not change the authored code/UV field.
	# Native byte equality also catches texture reimports and alpha changes on the same RID.
	if composition_sources != _composition_sources: _full_refresh = true
	_composition_sources = composition_sources
	if valid_codes.is_empty():
		_albedo = null
		_normal = null
		_material = null
		_meta = null
		return
	var meta := Image.create_empty(PATH_CODE + 1, 6, false, Image.FORMAT_RGBAF)
	meta.fill(Color(0, 0, 0, 0))
	var color_layers: Array[Image] = []
	var normal_layers: Array[Image] = []
	var material_layers: Array[Image] = []
	for layer in valid_codes.size():
		var code := valid_codes[layer]
		var brush: TerrainPaintBrush = _source_brushes[code]
		var image := albedo_images[layer]
		var normal := normal_images[layer]
		var padded := Image.create_empty(albedo_size.x, albedo_size.y, false, Image.FORMAT_RGBA8)
		padded.fill(Color(0, 0, 0, 0))
		padded.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
		padded.generate_mipmaps()
		color_layers.append(padded)
		var padded_normal := Image.create_empty(normal_size.x, normal_size.y, false, Image.FORMAT_RGBA8)
		padded_normal.fill(Color(0.5, 0.5, 1, 1))
		if normal: padded_normal.blit_rect(normal, Rect2i(Vector2i.ZERO, normal.get_size()), Vector2i.ZERO)
		padded_normal.generate_mipmaps(true)
		normal_layers.append(padded_normal)
		var data := material_images[layer]
		var padded_data := Image.create_empty(albedo_size.x,albedo_size.y,false,Image.FORMAT_RGBA8)
		padded_data.fill(Color(1,brush.roughness,brush.roughness,0))
		if data: padded_data.blit_rect(data,Rect2i(Vector2i.ZERO,data.get_size()),Vector2i.ZERO)
		padded_data.generate_mipmaps()
		material_layers.append(padded_data)
		var meters := brush.texture_meters
		if meters.x <= 0.0 or meters.y <= 0.0:
			meters = Vector2.ONE * _terrain.data.cell_size
		var scale := Vector2(image.get_size()) / Vector2(albedo_size)
		var normal_scale := Vector2(normal.get_size()) / Vector2(normal_size) if normal else Vector2.ONE
		meta.set_pixel(code, 0, Color(layer + 1, scale.x, scale.y, 1.0 if normal else 0.0))
		meta.set_pixel(code, 1, brush.tint)
		meta.set_pixel(code, 2, Color(brush.roughness, brush.metallic, brush.wet_response, float(_grass_codes[code])))
		meta.set_pixel(code, 3, Color(brush.normal_strength, meters.x, meters.y, 0))
		meta.set_pixel(code, 4, Color(normal_scale.x, normal_scale.y, 0, 0))
		meta.set_pixel(code, 5, Color(scale.x,scale.y,brush.material_flags(),0))
	_albedo = Texture2DArray.new()
	_normal = Texture2DArray.new()
	_material = Texture2DArray.new()
	if _albedo.create_from_images(color_layers) != OK or _normal.create_from_images(normal_layers) != OK or _material.create_from_images(material_layers) != OK:
		push_error("无法创建自由地表素材数组。")
		_albedo = null
		_normal = null
		_material = null
		_meta = null
		return
	_meta = ImageTexture.create_from_image(meta)

func _bind() -> void:
	var materials: Array[ShaderMaterial] = []
	if _terrain.top_material: materials.append(_terrain.top_material)
	var wall := _terrain.wall_material as ShaderMaterial
	if wall and not materials.has(wall): materials.append(wall)
	for material in _bound_materials:
		if not materials.has(material): RenderingServer.material_set_param(material.get_rid(), "surface_canvas_enabled", false)
	_bound_materials = materials
	var enabled := _layers != null and _meta != null
	for material in materials:
		var rid := material.get_rid()
		RenderingServer.material_set_param(rid, "surface_canvas_enabled", enabled)
		if not enabled: continue
		RenderingServer.material_set_param(rid, "surface_canvas_origin", Vector2(_lookup_origin) * CHUNK_METERS)
		RenderingServer.material_set_param(rid, "surface_canvas_grid", _lookup_size)
		RenderingServer.material_set_param(rid, "surface_canvas_chunk_meters", CHUNK_METERS)
		RenderingServer.material_set_param(rid, "surface_canvas_texture_origin", _data.texture_origin)
		for pair in [["surface_canvas_layers", _layers], ["surface_canvas_lookup", _lookup],
				["surface_canvas_albedo", _albedo], ["surface_canvas_normal", _normal], ["surface_canvas_material", _material], ["surface_canvas_meta", _meta]]:
			RenderingServer.material_set_param(rid, pair[0], pair[1].get_rid())


func _disable_materials() -> void:
	for material in _bound_materials:
		RenderingServer.material_set_param(material.get_rid(), "surface_canvas_enabled", false)
	_bound_materials.clear()


func _disable() -> void:
	_material = null
	_disable_materials()
	_layers = null
	_albedo = null
	_normal = null
	_meta = null
	_lookup = null
	_layer_images.clear()
	_layer_by_chunk.clear()
	_source_images.clear()
	_source_pixels.clear()
	_source_brushes.clear()
	_grass_codes.clear()
	_ordered_stamps.clear()
	_used_codes.clear()
	_dirty_chunks.clear()
	_grass_cells.clear()
	_has_grass_source = false
	_full_refresh = true
	_sources_dirty = true


func surface_grass_at(point: Vector2) -> int:
	if _refresh_queued: _flush()
	var key := Vector2i((point / CHUNK_METERS).floor())
	if not _layer_by_chunk.has(key): return -1
	var image := _layer_images[_layer_by_chunk[key]]
	var pixel := Vector2i(((point - Vector2(key) * CHUNK_METERS) * PIXELS_PER_METER).floor())
	pixel = pixel.clamp(Vector2i.ZERO, Vector2i.ONE * (CHUNK_PIXELS - 1))
	var state := image.get_pixelv(pixel)
	var code := roundi(state.r)
	if not _source_images.has(code): return -1
	var source: Image = _source_images[code]
	var uv := Vector2(state.g, state.b)
	if state.a < 0.5:
		var brush: TerrainPaintBrush = _source_brushes[code]
		var meters := brush.texture_meters
		if meters.x <= 0.0 or meters.y <= 0.0: meters = Vector2.ONE * _terrain.data.cell_size
		uv = (point - _data.texture_origin) / meters
		uv = Vector2(fposmod(uv.x, 1.0), fposmod(uv.y, 1.0))
	var source_pixel := Vector2i((uv * Vector2(source.get_size())).floor())
	source_pixel = source_pixel.clamp(Vector2i.ZERO, source.get_size() - Vector2i.ONE)
	if source.get_pixelv(source_pixel).a <= 0.5: return -1
	return 1 if _grass_codes.get(code, false) else 0


func has_grass_in_cell(cell: Vector2i) -> bool:
	if _refresh_queued: _flush()
	if _grass_cells.has(cell): return _grass_cells[cell]
	if not _terrain or not _terrain.data or not _has_grass_source: return false
	var meters := _terrain.data.cell_size
	var rect := Rect2(Vector2(cell) * meters - Vector2.ONE * meters * 0.5, Vector2.ONE * meters)
	for key in _keys_for_rect(rect):
		if not _layer_by_chunk.has(key): continue
		var origin := Vector2(key) * CHUNK_METERS
		var intersection := rect.intersection(Rect2(origin, Vector2.ONE * CHUNK_METERS))
		var first := Vector2i(((intersection.position - origin) * PIXELS_PER_METER).floor()).clamp(Vector2i.ZERO, Vector2i.ONE * CHUNK_PIXELS)
		var last := Vector2i(((intersection.end - origin) * PIXELS_PER_METER).ceil()).clamp(Vector2i.ZERO, Vector2i.ONE * CHUNK_PIXELS)
		var image := _layer_images[_layer_by_chunk[key]]
		for y in range(first.y, last.y):
			for x in range(first.x, last.x):
				if _grass_codes.get(roundi(image.get_pixel(x, y).r), false):
					_grass_cells[cell] = true
					return true
	_grass_cells[cell] = false
	return false


func _exit_tree() -> void:
	_disable_materials()
