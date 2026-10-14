extends SceneTree

const REPAINT := preload("res://tools/repaint_battle_brick_grid.gd")
const OUT := "D:/.codexfile/work/battle-grid-repaint/"
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var data := TerrainSurfaceData.new()
	data.texture_origin = Vector2(-15.2,29.6)
	var centre := data.snap_brush_point(Vector2(-8.01,36.81))
	check(centre.is_equal_approx(Vector2(-8.4,37.2)), "Cursor snaps to the actual brick centre, relative to texture origin")
	var before := data.paint_segment(centre,centre,0.05,13,false,1,true)
	check(not before.is_empty(), "A small snapped brush still paints one complete brick")
	for y in 32:
		for x in 32:
			check(data.get_code(centre-Vector2(0.4,0.4)+(Vector2(x,y)+Vector2(0.5,0.5))/40.0)==13,
				"Every native pixel in a snapped brick is covered")
	for offset in [Vector2(-0.413,0),Vector2(0.413,0),Vector2(0,-0.413),Vector2(0,0.413)]:
		check(data.get_code(centre+offset)==0, "Neighbouring bricks are untouched")
	data.apply_chunk_patch(before)
	check(data.chunks.is_empty(), "Snapped stroke undo restores missing chunks")
	var crossed := data.paint_segment(centre,centre+Vector2(2.4,0),0.4,12,false,2,true)
	for x in 128:
		check(data.get_code(centre-Vector2(0.4,0)+(Vector2(x+0.5,0)/40.0))==12,
			"A snapped drag leaves no gap across brick and chunk boundaries")
	data.paint_segment(centre,centre+Vector2(2.4,0),0.4,12,true,3,true)
	check(data.chunks.is_empty(), "Snapped erase removes complete selected bricks")
	data.apply_chunk_patch(crossed)
	var palette := load("res://data/world/spawn_paint_palette.tres") as TerrainPaintPalette
	for code in [15,16,17,18,22,23,24,20,21]:
		var brush := palette.brush_for_id(code)
		check(brush.validation_error().is_empty(), "Snapped catalog albedo and normal sizes match")
		for angle in [0.0,90.0,180.0,-90.0]:
			var point := data.snap_stamp_point(Vector2(-7.93,36.77),brush.texture_meters,angle,brush.snap_pivot_offset)
			var correction := brush.snap_pivot_offset-brush.snap_pivot_offset.rotated(deg_to_rad(angle))
			var size := brush.texture_meters if int(absf(angle))%180==0 else Vector2(brush.texture_meters.y,brush.texture_meters.x)
			var corner := (point-correction-size*0.5-data.texture_origin)/0.8
			check(corner.is_equal_approx(corner.round()), "Every snapped logical footprint uses the texture's brick boundaries")
			check(data.snap_stamp_point(point,brush.texture_meters,angle,brush.snap_pivot_offset).is_equal_approx(point),
				"Deleting then re-placing at a snapped centre is stable")
	for code in [20,21]:
		var brush := palette.brush_for_id(code)
		var atlas := brush.texture as AtlasTexture
		var raw := atlas.get_image()
		var prepared := brush.source_image()
		check(prepared.get_size()==Vector2i(128,128), "Irregular ornaments have a whole-brick transparent canvas")
		check(prepared.get_region(Rect2i(Vector2i(atlas.margin.position),raw.get_size())).get_data()==raw.get_data(),
			"Transparent canvas keeps every original ornament pixel unchanged")
	var current := load("res://data/world/world_surface.tres") as TerrainSurfaceData
	var staged := REPAINT.build(current,palette)
	check(staged.brush_snap_enabled and staged.stamps.size()>=127, "Map uses persisted snap and independent native-sized stamps")
	var origin := Vector2i((staged.texture_origin*40).round())
	for y in 38:
		for x in 38:
			var start := origin+Vector2i(x,y)*32
			var chunk := Vector2i((Vector2(start)/256).floor())
			var region := staged.chunks[chunk].get_region(Rect2i(start-chunk*256,Vector2i(32,32)))
			var uniform := Image.create_empty(32,32,false,Image.FORMAT_RGBAH)
			uniform.fill(region.get_pixel(0,0))
			check(region.get_data()==uniform.get_data(), "All 1444 map bricks have whole-brick material and order coverage")
	var terrain := Terrain.new()
	terrain.data = load("res://data/world/world_terrain.tres")
	terrain.paint_palette = palette
	terrain.surface_data = staged
	var canvas := TerrainSurfaceCanvas.new()
	var started := Time.get_ticks_usec()
	canvas.configure(terrain)
	canvas._flush()
	print("Canvas compose: ", (Time.get_ticks_usec()-started)/1000.0, "ms")
	var image := Image.create_empty(1216,1216,false,Image.FORMAT_RGBA8)
	for y in 1216:
		for x in 1216:
			var pixel := origin+Vector2i(x,y)
			var chunk := Vector2i((Vector2(pixel)/256).floor())
			var layer: int = canvas._layer_by_chunk[chunk]
			var record := canvas._layer_images[layer].get_pixelv(pixel-chunk*256)
			var code := roundi(record.r)
			var source: Image = canvas._source_images[code]
			var uv := Vector2(record.g,record.b) if record.a>0.5 else (Vector2(x,y)+Vector2(0.5,0.5))/40.0/palette.brush_for_id(code).texture_meters
			uv = Vector2(fposmod(uv.x,1.0),fposmod(uv.y,1.0))
			var sample := Vector2i((uv*Vector2(source.get_size())).floor()).clamp(Vector2i.ZERO,source.get_size()-Vector2i.ONE)
			image.set_pixel(x,y,source.get_pixelv(sample))
	check(image.save_png(OUT+"brick-layout.png")==OK, "Actual composed surface preview saves")
	canvas.free()
	terrain.free()
	print("Terrain brick grid: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
