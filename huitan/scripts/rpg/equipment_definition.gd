class_name EquipmentDefinition
extends Resource

enum Slot { WEAPON, ARMOR, ACCESSORY }

@export var id: String = ""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var icon: Texture2D
@export var slot: Slot = Slot.WEAPON
## 属性名到加成值；由配置定义属性，不在此固定战斗数值。
@export var attribute_bonuses: Dictionary[String, float] = {}
## 技能 ID 到效果强度加成，单位百分比：15 表示 +15%。
@export var skill_bonuses: Dictionary[String, float] = {}
