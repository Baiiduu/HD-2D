class_name ItemDefinition
extends Resource

enum Category { TOOL = 1, MATERIAL, PLANTING, CONSUMABLE }
enum FarmAction { NONE, HOE, SEED, WATER }

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var icon: Texture2D
## 详情插画可单独配置；留空时使用物品图标。
@export var illustration: Texture2D
@export var category: Category = Category.MATERIAL
## 工具一般不堆叠，材料、种子、作物和消耗品显示共用数量。
@export var stackable := true
## 在地图上使用此物品时执行的种植操作；其他物品保持 NONE。
@export var farm_action: FarmAction = FarmAction.NONE
