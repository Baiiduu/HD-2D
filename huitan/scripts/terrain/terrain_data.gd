@tool
class_name TerrainData
extends Resource

signal surface_changed(indices: PackedInt32Array)
var surface_change_only := false

## 地形格数据：每格一个区域类型、一个高度层级 + 一组覆盖层标记。
## 格子 (x, z) 的中心位于世界坐标 (x * cell_size, z * cell_size)。

enum Biome { CITY, CYBER, CULTIVATION, WILD }

const OVERLAY_PATH := 1
const OVERLAY_DIRT := 2
## 水：格子高度是河床，水面在河床上方 WATER_SURFACE 层
const OVERLAY_WATER := 4
## 桥：只对水格有效，桥面与河床上一层齐平
const OVERLAY_BRIDGE := 8
## 坡道：格子高度是坡底，朝高一层的相邻格抬升
const OVERLAY_RAMP := 16

## heights 中存储的是 层级 + HEIGHT_OFFSET，层级范围 -8..247
const HEIGHT_OFFSET := 8
const WATER_SURFACE := 0.6

## 左上角（西北）格子的坐标
@export var origin := Vector2i.ZERO
@export var size := Vector2i.ONE
## 一个地形格 / 一块 64px 纹理对应的世界尺寸（米）
@export var cell_size := 1.6
## 每一层的高度（米）
@export var layer_height := 0.8
@export var biomes := PackedByteArray()
@export var overlays := PackedByteArray()
@export var heights := PackedByteArray()
## 自定义画笔的固定编号；0 使用原底层 / 道路。旧地图留空时全部视为 0。
@export var paints := PackedByteArray()

## 改变地图范围，保留重叠部分的数据，新增的格子为城市区、高度 0、无覆盖层
func resize(new_origin: Vector2i, new_size: Vector2i) -> void:
	var old_origin := origin
	var old_size := size
	var old_biomes := biomes
	var old_overlays := overlays
	var old_heights := heights
	var old_paints := paints
	if old_heights.size() != old_biomes.size():
		old_heights = PackedByteArray()
		old_heights.resize(old_biomes.size())
		old_heights.fill(HEIGHT_OFFSET)
	origin = new_origin
	size = new_size
	biomes = PackedByteArray()
	biomes.resize(size.x * size.y)
	overlays = PackedByteArray()
	overlays.resize(size.x * size.y)
	heights = PackedByteArray()
	heights.resize(size.x * size.y)
	heights.fill(HEIGHT_OFFSET)
	paints = PackedByteArray()
	paints.resize(size.x * size.y)
	for z in old_size.y:
		for x in old_size.x:
			var cell := old_origin + Vector2i(x, z)
			if has_cell(cell):
				var from := z * old_size.x + x
				var to := _index(cell)
				biomes[to] = old_biomes[from]
				overlays[to] = old_overlays[from]
				heights[to] = old_heights[from]
				paints[to] = old_paints[from] if from < old_paints.size() else 0
	emit_changed()

func has_cell(cell: Vector2i) -> bool:
	var index := cell - origin
	return index.x >= 0 and index.y >= 0 and index.x < size.x and index.y < size.y

func _index(cell: Vector2i) -> int:
	var index := cell - origin
	return index.y * size.x + index.x

func get_biome(cell: Vector2i) -> int:
	return biomes[_index(cell)] if has_cell(cell) else 0

func set_biome(cell: Vector2i, biome: int) -> void:
	if has_cell(cell):
		biomes[_index(cell)] = biome
		emit_changed()

func get_level(cell: Vector2i) -> int:
	if not has_cell(cell):
		return 0
	var index := _index(cell)
	return (heights[index] if index < heights.size() else HEIGHT_OFFSET) - HEIGHT_OFFSET

func set_level(cell: Vector2i, level: int) -> void:
	if has_cell(cell):
		heights[_index(cell)] = clampi(level + HEIGHT_OFFSET, 0, 255)
		emit_changed()

func has_overlay(cell: Vector2i, flag: int) -> bool:
	return has_cell(cell) and overlays[_index(cell)] & flag != 0

func set_overlay(cell: Vector2i, flag: int, enabled: bool) -> void:
	if not has_cell(cell):
		return
	var index := _index(cell)
	overlays[index] = overlays[index] | flag if enabled else overlays[index] & ~flag
	emit_changed()

## 批量应用地表修改；画笔的一笔及撤销/重做均只发送一次更新。
func paint_at_index(index: int) -> int:
	return paints[index] if index < paints.size() else 0

func set_paint_at_index(index: int, id: int) -> void:
	if paints.size() != biomes.size(): paints.resize(biomes.size())
	paints[index] = id

func apply_surface_patch(indices: PackedInt32Array, patch_biomes: PackedByteArray, patch_overlays: PackedByteArray, patch_paints := PackedByteArray()) -> void:
	if indices.size() != patch_biomes.size() or indices.size() != patch_overlays.size():
		push_error("地表修改的格子与数据数量不一致。")
		return
	if not patch_paints.is_empty() and patch_paints.size() != indices.size():
		push_error("自定义地表修改的格子与数据数量不一致。")
		return
	for index in indices:
		if index < 0 or index >= biomes.size() or index >= overlays.size():
			push_error("地表修改包含地图范围外的格子。")
			return
	var geometry_changed := false
	for i in indices.size():
		geometry_changed = geometry_changed or ((overlays[indices[i]] ^ patch_overlays[i]) & (OVERLAY_WATER | OVERLAY_BRIDGE | OVERLAY_RAMP)) != 0
		biomes[indices[i]] = patch_biomes[i]
		overlays[indices[i]] = patch_overlays[i]
		if not patch_paints.is_empty(): set_paint_at_index(indices[i],patch_paints[i])
	if geometry_changed: emit_changed()
	else: notify_surface_changed(indices)

## 绘制仍通知保存与其它读者，但地形和地编可跳过全量几何重建。
func notify_surface_changed(indices: PackedInt32Array) -> void:
	if indices.is_empty(): return
	surface_change_only = true
	surface_changed.emit(indices)
	emit_changed()
	surface_change_only = false

func world_to_cell(position: Vector3) -> Vector2i:
	return Vector2i(roundi(position.x / cell_size), roundi(position.z / cell_size))

## 地形覆盖的世界范围（XZ 平面）
func get_world_rect() -> Rect2:
	return Rect2((Vector2(origin) - Vector2(0.5, 0.5)) * cell_size, Vector2(size) * cell_size)

## 打包成数据纹理：R = 区域类型，G = 覆盖层标记，B = 高度（含偏移），A 保留
func to_image() -> Image:
	var bytes := PackedByteArray()
	bytes.resize(size.x * size.y * 4)
	for i in size.x * size.y:
		bytes[i * 4] = biomes[i]
		bytes[i * 4 + 1] = overlays[i]
		bytes[i * 4 + 2] = heights[i] if i < heights.size() else HEIGHT_OFFSET
		bytes[i * 4 + 3] = paint_at_index(i)
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGBA8, bytes)
