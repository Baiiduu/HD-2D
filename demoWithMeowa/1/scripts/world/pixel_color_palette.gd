@tool
class_name PixelColorPalette
extends Resource

## 每种材质固定五档，从暗到亮；颜色按原画的 sRGB 色值填写。
@export var grass: PackedColorArray:
	set(value): grass = value; _invalidate()
@export var cobble: PackedColorArray:
	set(value): cobble = value; _invalidate()
@export var plaster: PackedColorArray:
	set(value): plaster = value; _invalidate()
@export var roof: PackedColorArray:
	set(value): roof = value; _invalidate()

var _texture: ImageTexture

func _invalidate() -> void:
	_texture = null
	emit_changed()

func validation_error() -> String:
	for colors in [grass, cobble, plaster, roof]:
		if colors.size() != 5: return "草地、卵石、墙面和屋瓦每条色阶需要五种颜色。"
	return ""

func palette_texture() -> ImageTexture:
	if _texture: return _texture
	var problem := validation_error()
	if not problem.is_empty():
		push_warning(problem)
		return null
	var image := Image.create_empty(5, 4, false, Image.FORMAT_RGBA8)
	var ramps := [grass, cobble, plaster, roof]
	for row in 4:
		for index in 5: image.set_pixel(index, row, ramps[row][index])
	_texture = ImageTexture.create_from_image(image)
	return _texture
