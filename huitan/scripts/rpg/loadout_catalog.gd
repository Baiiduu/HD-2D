class_name LoadoutCatalog
extends Resource

@export var equipment: Array[EquipmentDefinition] = []
@export var skills: Array[SkillDefinition] = []
@export var items: Array[ItemDefinition] = []
@export var attribute_labels: Dictionary[String, String] = {}
@export var skill_value_labels: Dictionary[String, String] = {}

func get_equipment(id: String) -> EquipmentDefinition:
	for entry in equipment:
		if entry and entry.id == id:
			return entry
	return null

func get_skill(id: String) -> SkillDefinition:
	for entry in skills:
		if entry and entry.id == id:
			return entry
	return null

func get_item(id: String) -> ItemDefinition:
	for entry in items:
		if entry and entry.id == id:
			return entry
	return null

func get_inventory_entry(id: String) -> Resource:
	var gear := get_equipment(id)
	return gear if gear else get_item(id)

func get_item_category(id: String) -> int:
	var item := get_item(id)
	return item.category if item else 0

func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	var equipment_ids: Array[String] = []
	var skill_ids: Array[String] = []
	for entry in equipment:
		if not entry or entry.id.is_empty() or entry.id in equipment_ids:
			errors.append("装备配置包含空条目、空 ID 或重复 ID。")
			continue
		equipment_ids.append(entry.id)
	for entry in skills:
		if not entry or entry.id.is_empty() or entry.id in skill_ids:
			errors.append("技能配置包含空条目、空 ID 或重复 ID。")
			continue
		skill_ids.append(entry.id)
	var item_ids: Array[String] = []
	for entry in items:
		if not entry or entry.id.is_empty() or entry.id in item_ids or entry.id in equipment_ids:
			errors.append("物品配置包含空条目、空 ID 或重复 ID。")
			continue
		item_ids.append(entry.id)
	for entry in equipment:
		if entry:
			for skill_id in entry.skill_bonuses:
				if skill_id not in skill_ids:
					errors.append("装备 %s 引用了不存在的技能 %s。" % [entry.id, skill_id])
	return errors
