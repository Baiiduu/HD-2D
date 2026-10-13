@tool
class_name FoliageColorPalette
extends Resource

## 叶片、枯草和六类花瓣各五档；底色选档后继续接受真实光照。
@export var leaves: PackedColorArray:
	set(value): leaves = value; _invalidate()
@export var dry_grass: PackedColorArray:
	set(value): dry_grass = value; _invalidate()
@export var cream: PackedColorArray:
	set(value): cream = value; _invalidate()
@export var pink: PackedColorArray:
	set(value): pink = value; _invalidate()
@export var violet: PackedColorArray:
	set(value): violet = value; _invalidate()
@export var yellow: PackedColorArray:
	set(value): yellow = value; _invalidate()
@export var blue: PackedColorArray:
	set(value): blue = value; _invalidate()
@export var red: PackedColorArray:
	set(value): red = value; _invalidate()

var _texture: ImageTexture

func _invalidate() -> void:
	_texture = null
	emit_changed()

func validation_error() -> String:
	for ramp in [leaves, dry_grass, cream, pink, violet, yellow, blue, red]:
		if ramp.size() != 5: return "叶片、枯草和每类花瓣需要五种颜色。"
	return ""

func palette_texture() -> ImageTexture:
	if _texture: return _texture
	if not validation_error().is_empty():
		push_warning(validation_error())
		return null
	var ramps := [leaves, dry_grass, cream, pink, violet, yellow, blue, red]
	var image := Image.create_empty(5, ramps.size(), false, Image.FORMAT_RGBA8)
	for row in ramps.size():
		for index in 5: image.set_pixel(index, row, ramps[row][index])
	_texture = ImageTexture.create_from_image(image)
	return _texture
