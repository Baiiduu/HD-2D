extends SceneTree

const OUT := "D:/.codexfile/work/plaza-material-maps/"
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func data_image(texture: Texture2D) -> Image:
	var image := texture.get_image().duplicate()
	if image.is_compressed(): image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	if texture is AtlasTexture and texture.get_size()!=Vector2(image.get_size()):
		var atlas := texture as AtlasTexture
		var padded := Image.create_empty(int(texture.get_width()),int(texture.get_height()),false,Image.FORMAT_RGBA8)
		padded.fill(Color(1,1,1,0))
		padded.blit_rect(image,Rect2i(Vector2i.ZERO,image.get_size()),Vector2i(atlas.margin.position))
		return padded
	return image

func _run() -> void:
	var protected := {}
	for path in ["res://data/world/world_surface.res","res://data/world/world_terrain.tres","res://scenes/world/world.tscn"]:
		protected[path]=FileAccess.get_sha256(path)
	var palette := load("res://data/world/spawn_paint_palette.tres") as TerrainPaintPalette
	check(palette.validation_error().is_empty(),"Existing palette accepts the aligned material maps")
	for code in range(12,25):
		var brush := palette.brush_for_id(code)
		check(brush.material_flags()==7,"Every plaza brush binds AO and both roughness maps")
		check(brush.metallic==0,"Every plaza brush remains nonmetal")
		var prepared := brush.material_image()
		check(prepared.get_size()==brush.source_image().get_size(),"Material canvas matches its native albedo and normal slice")
		var actual := prepared.get_data()
		for pair in [[brush.ao_texture,0],[brush.roughness_texture,1],[brush.wet_roughness_texture,2]]:
			var expected := data_image(pair[0]).get_data()
			var matches := true
			for index in range(0,actual.size(),4):
				var value: int = expected[index] if expected[index+3]>127 else 255
				if actual[index+int(pair[1])]!=value:
					matches=false
					break
			check(matches,"Every material byte preserves its source channel without sRGB conversion, resizing or slice shift")
		var neutral_metal := true
		for index in range(3,actual.size(),4):
			if actual[index]!=0: neutral_metal=false
		check(neutral_metal,"Packed data never invents a metallic surface")
	var empty := TerrainPaintBrush.new()
	empty.texture=palette.brush_for_id(12).texture
	check(empty.material_flags()==0 and empty.material_image()==null,"Unmapped brushes preserve existing scalar material behavior")
	empty.ao_texture=palette.brush_for_id(12).ao_texture
	check(empty.material_flags()==1,"AO can be used independently of roughness")
	var invalid := ImageTexture.create_from_image(Image.create_empty(8,8,false,Image.FORMAT_RGBA8))
	empty.roughness_texture=invalid
	check(not empty.validation_error().is_empty(),"Wrong material dimensions are rejected before painting")
	var material := ShaderMaterial.new()
	material.shader=load("res://shaders/terrain/terrain.gdshader")
	var packed := palette.apply_to(material)
	check(packed.has("paint_materials"),"Legacy terrain-cell brush mode also receives the material array")
	var settings := (packed["paint_settings"] as ImageTexture).get_image()
	for code in range(12,25):
		check(roundi(settings.get_pixel(code,3).a)==7,"Legacy shader flags match material channels")
		check(settings.get_pixel(code,2).g==0,"Legacy shader keeps metallic zero")
	DirAccess.make_dir_recursive_absolute(OUT)
	var fixture := palette.brush_for_id(21).duplicate(true) as TerrainPaintBrush
	check(ResourceSaver.save(fixture,OUT+"brush-roundtrip.tres")==OK,"Material brush saves with its original atlas padding")
	var loaded := ResourceLoader.load(OUT+"brush-roundtrip.tres","",ResourceLoader.CACHE_MODE_IGNORE) as TerrainPaintBrush
	check(loaded.material_flags()==7 and loaded.material_image().get_data()==fixture.material_image().get_data(),
		"Saving and reloading keeps all aligned material channels")
	for path in protected:
		check(FileAccess.get_sha256(path)==protected[path],"Materials do not change user map or scene data")
	print("Terrain material maps: %d checks, %d failures"%[checks,failures])
	quit(0 if failures==0 else 1)
