@tool
class_name TerrainPaintPalette
extends Resource

@export var brushes: Array[TerrainPaintBrush] = []:
	set(value):
		brushes = value
		_connect_brushes()
		emit_changed()

var _connected: Array[TerrainPaintBrush] = []

func _connect_brushes() -> void:
	for brush in _connected:
		if brush.changed.is_connected(emit_changed): brush.changed.disconnect(emit_changed)
	_connected.clear()
	for brush in brushes:
		if brush and not _connected.has(brush):
			brush.changed.connect(emit_changed)
			_connected.append(brush)

func brush_for_id(id: int) -> TerrainPaintBrush:
	for brush in brushes:
		if brush and brush.target == TerrainPaintBrush.Target.CUSTOM and brush.paint_id == id:
			return brush
	return null

func validation_error() -> String:
	var conflict := id_error()
	if not conflict.is_empty(): return conflict
	for brush in brushes:
		if not brush: return "画笔列表中有空项，请补齐或删除。"
		var problem := brush.validation_error()
		if not problem.is_empty(): return brush.label + "：" + problem
	return ""

func id_error() -> String:
	var ids := {}
	var targets := {}
	for brush in brushes:
		if not brush: continue
		if brush.target == TerrainPaintBrush.Target.CUSTOM:
			if brush.paint_id < 1 or brush.paint_id > 255 or ids.has(brush.paint_id):
				return "自定义画笔编号需要在 1–255 内且不能重复。"
			ids[brush.paint_id] = true
		else:
			if targets.has(brush.target): return "草地底层和原道路覆盖层各只能配置一支画笔。"
			targets[brush.target] = true
	return ""

func apply_to(material: ShaderMaterial) -> Dictionary:
	_connect_brushes()
	var textures := {}
	material.set_shader_parameter("paint_enabled",false)
	if not id_error().is_empty(): return textures
	var images: Array[Image] = []
	var normal_images: Array[Image] = []
	var custom: Array[TerrainPaintBrush] = []
	for brush in brushes:
		if not brush or not brush.validation_error().is_empty(): continue
		if brush.target == TerrainPaintBrush.Target.CUSTOM:
			custom.append(brush)
			images.append(brush.source_image())
			normal_images.append(brush.normal_image())
		else:
			var prefix := "wild" if brush.target == TerrainPaintBrush.Target.GRASS else "path"
			var source: Texture2D = brush.texture
			if brush.mode == TerrainPaintBrush.Mode.ATLAS_TILE or source is AtlasTexture:
				var image := brush.source_image()
				image.generate_mipmaps()
				source = ImageTexture.create_from_image(image)
			textures[prefix + ("_texture" if prefix == "wild" else "_atlas")] = source
			var normal_image := brush.normal_image()
			material.set_shader_parameter(prefix + "_normal_enabled", normal_image != null)
			material.set_shader_parameter(prefix + "_normal_strength", brush.normal_strength)
			if normal_image:
				normal_image.generate_mipmaps()
				textures[prefix + "_normal_texture"] = ImageTexture.create_from_image(normal_image)
			material.set_shader_parameter(prefix + "_tint",brush.tint)
			material.set_shader_parameter(prefix + "_surface",brush.surface())
			if prefix == "path":
				material.set_shader_parameter("path_configured",true)
				material.set_shader_parameter("path_grid",Vector2(brush.atlas_grid))
				material.set_shader_parameter("path_tiles",brush.corner_tiles)
	if images.is_empty(): return textures
	# Texture arrays isolate the mipmaps of each brush; source art remains unchanged.
	var size := Vector2i.ZERO
	for image in images:
		size = size.max(image.get_size())
	size = Vector2i(nearest_po2(size.x),nearest_po2(size.y))
	# Normal data can be much smaller than the largest unrelated colour brush.
	var normal_size := Vector2i(4,4)
	for image in normal_images:
		if image: normal_size = normal_size.max(image.get_size())
	normal_size = Vector2i(nearest_po2(normal_size.x),nearest_po2(normal_size.y))
	var settings := Image.create_empty(256,20,false,Image.FORMAT_RGBAF)
	var normals: Array[Image] = []
	for i in images.size():
		var image := images[i]
		image.resize(size.x,size.y,Image.INTERPOLATE_NEAREST)
		image.generate_mipmaps()
		var brush := custom[i]
		settings.set_pixel(brush.paint_id,0,Color(i+1,brush.mode,brush.atlas_grid.x,brush.atlas_grid.y))
		settings.set_pixel(brush.paint_id,1,brush.tint)
		settings.set_pixel(brush.paint_id,2,Color(brush.roughness,brush.metallic,brush.wet_response,float(brush.is_grass)))
		var normal_image := normal_images[i]
		settings.set_pixel(brush.paint_id,3,Color(1.0 if normal_image else 0.0,brush.normal_strength,0,0))
		if not normal_image:
			normal_image = Image.create_empty(normal_size.x,normal_size.y,false,Image.FORMAT_RGBA8)
			normal_image.fill(Color(0.5,0.5,1.0,1.0))
		else:
			normal_image.resize(normal_size.x,normal_size.y,Image.INTERPOLATE_NEAREST)
		normal_image.generate_mipmaps()
		normals.append(normal_image)
		for key in 16:
			var tile := brush.corner_tiles[key] if brush.mode == TerrainPaintBrush.Mode.CORNER_ATLAS else Vector2.ZERO
			settings.set_pixel(brush.paint_id,4+key,Color(tile.x,tile.y,0,0))
	var texture_array := Texture2DArray.new()
	if texture_array.create_from_images(images) != OK: return textures
	textures["paint_textures"] = texture_array
	var normal_array := Texture2DArray.new()
	if normal_array.create_from_images(normals) == OK: textures["paint_normals"] = normal_array
	textures["paint_settings"] = ImageTexture.create_from_image(settings)
	material.set_shader_parameter("paint_enabled",true)
	return textures
