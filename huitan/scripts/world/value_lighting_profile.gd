@tool
class_name ValueLightingProfile
extends Resource

## 样板关闭时使用原色板，开启使用层次色板；实际颜色只保存在这些资源中。
@export var original_material_palette: PixelColorPalette
@export var material_palette: PixelColorPalette
@export var original_foliage_palette: FoliageColorPalette
@export var foliage_palette: FoliageColorPalette
## 原始光影、黄金、细雨、夜晚，顺序与 VisualSample / Style 一致；空项不叠加光影。
@export var lighting_presets: Array[SpawnVisualPreset] = []
