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
	var image := texture.get_image()
	if image.is_compressed(): image.decompress()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	if mode == Mode.ATLAS_TILE:
		var tile_size := Vector2i(image.get_size()) / atlas_grid
		image = image.get_region(Rect2i(atlas_tile * tile_size,tile_size))
	return image

func surface() -> Vector3:
	return Vector3(roughness,metallic,wet_response)

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
