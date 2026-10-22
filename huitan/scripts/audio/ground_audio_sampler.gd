class_name GroundAudioSampler
extends RefCounted

enum Surface { STONE, COBBLE, GRASS, SOIL, WOOD, METAL }
const SURFACE_COUNT := 6
const ATLAS: Array[Vector2i] = [
	Vector2i(0, 3), Vector2i(3, 3), Vector2i(0, 0), Vector2i(3, 2),
	Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 1),
	Vector2i(1, 3), Vector2i(0, 1), Vector2i(3, 0), Vector2i(2, 0),
	Vector2i(1, 0), Vector2i(2, 2), Vector2i(1, 1), Vector2i(2, 1)]

var _images: Dictionary[Texture2D, Image] = {}

func one_surface(surface: int) -> PackedFloat32Array:
	var weights := PackedFloat32Array()
	weights.resize(SURFACE_COUNT)
	weights[clampi(surface, 0, SURFACE_COUNT - 1)] = 1.0
	return weights

## 与 terrain_surface.gdshaderinc 使用相同的图集格、透明阈值和覆盖优先级。
## 纹理只读回并解压一次，移动时只查询缓存像素。
func sample(terrain: Terrain, world_point: Vector3, radius: float, biomes: PackedInt32Array) -> PackedFloat32Array:
	var weights := PackedFloat32Array()
	weights.resize(SURFACE_COUNT)
	var offsets: Array[Vector2] = [Vector2.ZERO, Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]
	for index in offsets.size():
		var offset := offsets[index] * radius
		var point := terrain.to_local(world_point + Vector3(offset.x, 0.0, offset.y))
		var surface := surface_at(terrain, Vector2(point.x, point.z), biomes)
		weights[surface] += 0.4 if index == 0 else 0.15
	return weights

func surface_at(terrain: Terrain, location: Vector2, biomes: PackedInt32Array) -> int:
	var data := terrain.data
	var grid := location / data.cell_size
	var cell := Vector2i(roundi(grid.x), roundi(grid.y))
	if data.has_overlay(cell, TerrainData.OVERLAY_BRIDGE):
		return Surface.WOOD
	var zone := _biome_at(data, grid)
	var surface := biomes[clampi(zone, 0, biomes.size() - 1)]
	if not terrain.top_material:
		return surface
	var top_left := Vector2i(floori(grid.x), floori(grid.y))
	var local := grid - Vector2(top_left)
	if _covered(terrain.top_material, "dirt_atlas", _key(data, top_left, TerrainData.OVERLAY_DIRT), local):
		surface = Surface.SOIL
	if _covered(terrain.top_material, "path_atlas", _key(data, top_left, TerrainData.OVERLAY_PATH), local):
		surface = Surface.COBBLE
	return surface

func _clamped_cell(data: TerrainData, cell: Vector2i) -> Vector2i:
	return Vector2i(clampi(cell.x, data.origin.x, data.origin.x + data.size.x - 1),
		clampi(cell.y, data.origin.y, data.origin.y + data.size.y - 1))

func _is(data: TerrainData, cell: Vector2i, flag: int) -> bool:
	return data.has_overlay(_clamped_cell(data, cell), flag)

func _biome_at(data: TerrainData, grid: Vector2) -> int:
	var cell := Vector2i(roundi(grid.x), roundi(grid.y))
	if _is(data, cell, TerrainData.OVERLAY_PATH):
		var offset := grid - Vector2(cell)
		var step_x := Vector2i(int(signf(offset.x)), 0)
		var step_z := Vector2i(0, int(signf(offset.y)))
		var first := step_x if absf(offset.x) >= absf(offset.y) else step_z
		var second := step_z if absf(offset.x) >= absf(offset.y) else step_x
		for neighbor in [cell + first, cell + second, cell + first + second]:
			if not _is(data, neighbor, TerrainData.OVERLAY_PATH):
				return data.get_biome(_clamped_cell(data, neighbor))
	return data.get_biome(_clamped_cell(data, cell))

func _key(data: TerrainData, cell: Vector2i, flag: int) -> int:
	return int(_is(data, cell, flag)) + int(_is(data, cell + Vector2i(0, 1), flag)) * 2 \
		+ int(_is(data, cell + Vector2i(1, 0), flag)) * 4 + int(_is(data, cell + Vector2i(1, 1), flag)) * 8

func _covered(material: ShaderMaterial, parameter: String, key: int, local: Vector2) -> bool:
	if key == 0:
		return false
	var texture := material.get_shader_parameter(parameter) as Texture2D
	if not texture:
		return false
	if not _images.has(texture):
		var image := texture.get_image()
		if image.is_compressed():
			image.decompress()
		_images[texture] = image
	var image := _images[texture]
	var inset := local.clamp(Vector2.ONE * (0.5 / 64.0), Vector2.ONE * (1.0 - 0.5 / 64.0))
	var uv := (Vector2(ATLAS[key]) + inset) / 4.0
	return image.get_pixel(clampi(int(uv.x * image.get_width()), 0, image.get_width() - 1),
		clampi(int(uv.y * image.get_height()), 0, image.get_height() - 1)).a > 0.5
