@tool
class_name TerrainPaintBrush
extends Resource

enum Target { CUSTOM, GRASS, PATH }
enum Mode { TEXTURE, ATLAS_TILE, CORNER_ATLAS }

const MEOWA_TILES := [Vector2(0,3),Vector2(3,3),Vector2(0,0),Vector2(3,2),
	Vector2(0,2),Vector2(1,2),Vector2(2,3),Vector2(3,1),Vector2(1,3),Vector2(0,1),
	Vector2(3,0),Vector2(2,0),Vector2(1,0),Vector2(2,2),Vector2(1,1),Vector2(2,1)]

@export var label := "新地表":
	set(value): label = value; emit_changed()
## 隐藏旧画笔选项，仍保留固定编号、已有铺设和原型引用。
@export var show_in_painter := true:
	set(value): show_in_painter = value; emit_changed()
## 自定义地表独立绘制；草地与道路沿用现有地图的底层和道路标记。
@export var target: Target = Target.CUSTOM:
	set(value): target = value; emit_changed()
## 自定义画笔的固定编号；同一配置内不能重复。已有绘制依赖此编号，重排列表不改变编号。
@export_range(1,255,1) var paint_id := 1:
	set(value): paint_id = value; emit_changed()
@export var texture: Texture2D:
	set(value): texture = value; emit_changed()
@export var mode: Mode = Mode.TEXTURE:
	set(value): mode = value; emit_changed()
## 整张纹理或图集单块的重复尺寸（米）；零值沿用一格一张。使用世界坐标，旋转镜头不改变铺装。
@export var texture_meters := Vector2.ZERO:
	set(value): texture_meters = value; emit_changed()
## 透明装饰下面的固定画笔编号；0 透出原地表。底层只采样一层。
@export_range(0,255,1) var underlay_paint_id := 0:
	set(value): underlay_paint_id = value; emit_changed()
## 原图奇数像素接口的旋转基准；默认不补偿，砖格分隔带使用半像素。
@export var snap_pivot_offset := Vector2.ZERO:
	set(value): snap_pivot_offset = value; emit_changed()

@export_group("材质贴图")
## 线性灰度：白色无遮挡，暗色为砖缝与凹槽遮蔽。须与颜色纹理同画布、同切片。
@export var ao_texture: Texture2D:
	set(value): ao_texture = value; emit_changed()
## 线性灰度：白色粗糙，暗色光滑；不改变原颜色纹理。
@export var roughness_texture: Texture2D:
	set(value): roughness_texture = value; emit_changed()
## 可选湿润粗糙度，沿用现有天气湿润程度混合。
@export var wet_roughness_texture: Texture2D:
	set(value): wet_roughness_texture = value; emit_changed()

@export_group("图集")
## 图集的列数、行数；整张纹理模式忽略此值。
@export var atlas_grid := Vector2i(4,4):
	set(value): atlas_grid = value; emit_changed()
## 单块图集模式选取的列、行，从 0 开始。
@export var atlas_tile := Vector2i.ZERO:
	set(value): atlas_tile = value; emit_changed()
## 过渡图集的 16 个格子坐标：索引 = 左上1 + 左下2 + 右上4 + 右下8。默认使用 Meowa 顺序。
@export var corner_tiles := PackedVector2Array(MEOWA_TILES):
	set(value): corner_tiles = value; emit_changed()

@export_group("表面")
## 可选 OpenGL 法线；尺寸、图集布局与颜色纹理一致。留空可用已准备的对应法线。
@export var normal_texture: Texture2D:
	set(value): normal_texture = value; emit_changed()
@export_range(0.0, 1.5, 0.05) var normal_strength := 1.0:
	set(value): normal_strength = value; emit_changed()
@export var tint := Color.WHITE:
	set(value): tint = value; emit_changed()
@export_range(0.0,1.0,0.01) var roughness := 0.9:
	set(value): roughness = value; emit_changed()
@export_range(0.0,1.0,0.01) var metallic := 0.0:
	set(value): metallic = value; emit_changed()
## 接入现有天气湿润效果，0 表示不被打湿。
@export_range(0.0,1.0,0.01) var wet_response := 0.6:
	set(value): wet_response = value; emit_changed()
## 使用现有草地光照，并允许地编在此地表上铺设草花。
@export var is_grass := false:
	set(value): is_grass = value; emit_changed()

func validation_error() -> String:
	if not texture: return "请选择纹理。"
	if texture_meters != Vector2.ZERO and (texture_meters.x <= 0 or texture_meters.y <= 0):
		return "纹理重复尺寸需同时大于 0；零值沿用地形格。"
	if normal_texture and normal_texture.get_size() != texture.get_size(): return "法线图尺寸须与颜色纹理一致。"
	for data in [ao_texture, roughness_texture, wet_roughness_texture]:
		if data and data.get_size() != texture.get_size(): return "AO 与粗糙度贴图须与颜色纹理同尺寸、同切片。"
	if target == Target.PATH and mode != Mode.CORNER_ATLAS:
		return "原道路画笔需要过渡图集；整张纹理或单块图集请使用自定义地表。"
	if target == Target.GRASS and mode == Mode.CORNER_ATLAS:
		return "草地底层使用整张纹理或单块图集；过渡图集请使用自定义地表。"
	if mode == Mode.TEXTURE: return ""
	if atlas_grid.x < 1 or atlas_grid.y < 1: return "图集列数与行数必须大于 0。"
	if texture.get_width() % atlas_grid.x != 0 or texture.get_height() % atlas_grid.y != 0:
		return "纹理尺寸必须能被图集列数和行数整除。"
	if mode == Mode.ATLAS_TILE:
		if not _inside(atlas_tile): return "选中的图集格子超出范围。"
	else:
		if corner_tiles.size() != 16: return "过渡图集需要 16 个四角组合坐标。"
		for point in corner_tiles:
			if point != point.round() or not _inside(Vector2i(point)):
				return "过渡格子坐标必须是图集范围内的整数。"
	return ""

func _inside(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < atlas_grid.x and tile.y < atlas_grid.y

func source_image() -> Image:
	var image: Image = texture.get_image().duplicate()
	if image.is_compressed(): image.decompress()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	image = _atlas_margin(image, texture, false)
	if mode == Mode.ATLAS_TILE:
		var tile_size := Vector2i(image.get_size()) / atlas_grid
		image = image.get_region(Rect2i(atlas_tile * tile_size,tile_size))
	return image

func surface() -> Vector3:
	return Vector3(roughness,metallic,wet_response)

func normal_image() -> Image:
	var source := normal_texture if normal_texture else SurfaceNormalMaps.for_texture(texture)
	if not source: return null
	var image: Image = source.get_image().duplicate()
	if image.is_compressed(): image.decompress()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	if not normal_texture and texture is AtlasTexture:
		var atlas := texture as AtlasTexture
		if atlas.region.has_area(): image = image.get_region(Rect2i(atlas.region))
	image = _atlas_margin(image, normal_texture if normal_texture else texture, true)
	if mode == Mode.ATLAS_TILE:
		var tile_size := Vector2i(image.get_size()) / atlas_grid
		image = image.get_region(Rect2i(atlas_tile * tile_size, tile_size))
	return image

func _atlas_margin(image: Image, source: Texture2D, normal: bool) -> Image:
	if not source is AtlasTexture or source.get_size() == Vector2(image.get_size()): return image
	var atlas := source as AtlasTexture
	var padded := Image.create_empty(int(source.get_width()), int(source.get_height()), false, Image.FORMAT_RGBA8)
	padded.fill(Color(0.5, 0.5, 1, 0) if normal else Color(0, 0, 0, 0))
	padded.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(atlas.margin.position))
	return padded

func material_flags() -> int:
	return (1 if ao_texture else 0) | (2 if roughness_texture else 0) | (4 if wet_roughness_texture else 0)

## Runtime-only linear channels: AO / dry roughness / wet roughness / reserved.
func material_image() -> Image:
	if material_flags() == 0: return null
	var size := source_image().get_size()
	var planes: Array[PackedByteArray] = []
	for source in [ao_texture, roughness_texture, wet_roughness_texture]:
		if not source:
			planes.append(PackedByteArray())
			continue
		var image: Image = source.get_image().duplicate()
		if image.is_compressed(): image.decompress()
		image.clear_mipmaps()
		image.convert(Image.FORMAT_RGBA8)
		image = _atlas_margin(image, source, false)
		if mode == Mode.ATLAS_TILE:
			var tile_size := Vector2i(image.get_size()) / atlas_grid
			image = image.get_region(Rect2i(atlas_tile * tile_size, tile_size))
		planes.append(image.get_data())
	var pixels := PackedByteArray()
	pixels.resize(size.x * size.y * 4)
	for index in range(0, pixels.size(), 4):
		pixels[index] = (planes[0][index] if planes[0][index+3]>127 else 255) if not planes[0].is_empty() else 255
		pixels[index+1] = (planes[1][index] if planes[1][index+3]>127 else 255) if not planes[1].is_empty() else roundi(roughness*255)
		pixels[index+2] = (planes[2][index] if planes[2][index+3]>127 else 255) if not planes[2].is_empty() else roundi(roughness*255)
		pixels[index+3] = 0 # Metalness continues to use the brush's scalar, currently zero.
	return Image.create_from_data(size.x,size.y,false,Image.FORMAT_RGBA8,pixels)

## 一笔内只修改格子，完成整笔后由画笔发送一次 changed 并登记撤销。
func stamp(data: TerrainData,index: int,erase: bool) -> Vector3i:
	var before := Vector3i(data.biomes[index],data.overlays[index],data.paint_at_index(index))
	var after := before
	if erase:
		if target == Target.CUSTOM:
			if after.z == paint_id: after.z = 0
		else:
			after.y &= ~TerrainData.OVERLAY_PATH
	elif target == Target.CUSTOM:
		after.z = paint_id
		after.y &= ~(TerrainData.OVERLAY_PATH | TerrainData.OVERLAY_DIRT)
		if is_grass: after.x = TerrainData.Biome.WILD
	elif target == Target.PATH:
		after.z = 0
		after.y |= TerrainData.OVERLAY_PATH
	else:
		after.z = 0
		after.x = TerrainData.Biome.WILD
		after.y &= ~(TerrainData.OVERLAY_PATH | TerrainData.OVERLAY_DIRT)
	data.biomes[index] = after.x
	data.overlays[index] = after.y
	if after.z != before.z: data.set_paint_at_index(index,after.z)
	return before
