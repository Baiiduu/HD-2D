class_name WaveSpawnShadowAtlas
extends RefCounted
## 仅在目录预热／素材变更时从原帧烘一次：R=主体，G=一原生像素细边。
## 不实例化怪物，不渲染 Viewport，不在每帧读取贴图或计算轮廓。
var texture: ImageTexture
var records: Dictionary[PackedScene, Dictionary] = {}
var _scenes: Array[PackedScene] = []
var _dirty := true

func prepare(scenes: Array[PackedScene]) -> bool:
	var unique: Array[PackedScene] = []
	for scene in scenes:
		if scene and scene not in unique: unique.append(scene)
	if unique == _scenes and not _dirty: return false
	_scenes = unique
	_dirty = false
	records.clear()
	var masks: Array[Image] = []
	var cell := 4
	for scene in unique:
		if not scene.changed.is_connected(_invalidate): scene.changed.connect(_invalidate)
		var data := _sprite_data(scene.get_state())
		var source_texture := data.get("texture") as Texture2D
		if not source_texture: continue
		if not source_texture.changed.is_connected(_invalidate): source_texture.changed.connect(_invalidate)
		var image := _source_image(source_texture)
		if not image or image.is_empty(): continue
		var used := image.get_used_rect()
		if not used.has_area(): continue
		var mask := bake_mask(image.get_region(used))
		cell = maxi(cell, maxi(mask.get_width(), mask.get_height()))
		var pose: Transform3D = data.get("transform", Transform3D.IDENTITY)
		var scale: Vector3 = data.get("scale", pose.basis.get_scale())
		records[scene] = {"slot":masks.size(), "pixels":Vector2(mask.get_size()),
			"size":Vector2(mask.get_width() * absf(scale.x), mask.get_height() * absf(scale.y)) * float(data.get("pixel_size", 0.01))}
		masks.append(mask)
	if masks.is_empty(): texture = null; return true
	var columns := ceili(sqrt(float(masks.size())))
	var rows := ceili(float(masks.size()) / columns)
	var atlas := Image.create_empty(columns * cell, rows * cell, false, Image.FORMAT_RGBA8)
	for scene in records:
		var record := records[scene]
		var slot: int = record.slot
		var origin := Vector2i(slot % columns, slot / columns) * cell
		atlas.blit_rect(masks[slot], Rect2i(Vector2i.ZERO, masks[slot].get_size()), origin)
		record.region = Color(float(origin.x) / atlas.get_width(), float(origin.y) / atlas.get_height(),
			float(masks[slot].get_width()) / atlas.get_width(), float(masks[slot].get_height()) / atlas.get_height())
	texture = ImageTexture.create_from_image(atlas)
	return true

func _invalidate() -> void:
	_dirty = true

func _source_image(source: Texture2D) -> Image:
	# AtlasTexture.get_image() 会在解压之前裁剪；压缩图集先解压底图再取原帧。
	if source is AtlasTexture:
		var image := _source_image(source.atlas)
		if not image: return null
		var region := Rect2i(source.region)
		if not region.has_area(): region = Rect2i(Vector2i.ZERO, image.get_size())
		var frame := image.get_region(region)
		if source.margin.has_area():
			var padded := Image.create_empty(frame.get_width() + int(source.margin.size.x), frame.get_height() + int(source.margin.size.y), false, frame.get_format())
			padded.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i(source.margin.position))
			return padded
		return frame
	var image := source.get_image()
	if image and image.is_compressed() and image.decompress() != OK: return null
	return image

static func bake_mask(source: Image) -> Image:
	# 两像素留边使最近邻采样和外轮廓均不会碰到相邻图块。
	var mask := Image.create_empty(source.get_width() + 4, source.get_height() + 4, false, Image.FORMAT_RGBA8)
	for y in source.get_height():
		for x in source.get_width():
			if source.get_pixel(x, y).a <= 0.1: continue
			mask.set_pixel(x + 2, y + 2, Color(1, 0, 0, 1))
	for y in range(1, mask.get_height() - 1):
		for x in range(1, mask.get_width() - 1):
			if mask.get_pixel(x, y).r > 0.0: continue
			if mask.get_pixel(x - 1, y).r + mask.get_pixel(x + 1, y).r + mask.get_pixel(x, y - 1).r + mask.get_pixel(x, y + 1).r > 0.0:
				mask.set_pixel(x, y, Color(0, 1, 0, 1))
	return mask

func _sprite_data(state: SceneState) -> Dictionary:
	var data := {}
	if state.get_base_scene_state(): data = _sprite_data(state.get_base_scene_state())
	for index in state.get_node_count():
		if String(state.get_node_path(index)) != "Sprite" and state.get_node_type(index) != &"Sprite3D": continue
		for property in state.get_node_property_count(index):
			data[state.get_node_property_name(index, property)] = state.get_node_property_value(index, property)
		break
	return data
