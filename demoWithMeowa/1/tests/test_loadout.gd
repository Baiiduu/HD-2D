extends SceneTree

func _initialize() -> void:
	var catalog := LoadoutCatalog.new()
	var sword := EquipmentDefinition.new()
	sword.id = "sword"
	sword.attribute_bonuses = {"attack": 5.0}
	sword.skill_bonuses = {"fire": 15.0}
	var staff := EquipmentDefinition.new()
	staff.id = "staff"
	staff.attribute_bonuses = {"attack": 2.0}
	var armor := EquipmentDefinition.new()
	armor.id = "armor"
	armor.slot = EquipmentDefinition.Slot.ARMOR
	armor.attribute_bonuses = {"defense": 3.0}
	var charm := EquipmentDefinition.new()
	charm.id = "charm"
	charm.slot = EquipmentDefinition.Slot.ACCESSORY
	charm.skill_bonuses = {"fire": 10.0}
	catalog.equipment.assign([sword, staff, armor, charm])
	for id in ["fire", "ice", "heal"]:
		var skill := SkillDefinition.new()
		skill.id = id
		skill.values = {"power": 20.0}
		catalog.skills.append(skill)
	assert(catalog.validation_errors().is_empty())
	var state := LoadoutState.new(catalog, 3)
	assert(not state.equip("sword"))
	assert(not state.acquire_equipment("missing"))
	for entry in catalog.equipment:
		assert(state.acquire_equipment(entry.id))
	assert(not state.acquire_equipment("sword"))
	assert(state.equip("sword") and state.equip("armor") and state.equip("charm"))
	assert(state.get_attribute_totals() == {"attack": 5.0, "defense": 3.0})
	var snapshot := state.export_state()
	assert(state.preview_attribute_totals("staff") == {"attack": 2.0, "defense": 3.0})
	assert(state.export_state() == snapshot)
	assert(is_equal_approx(state.get_skill_values("fire")["power"], 25.0))
	assert(not state.assign_skill("fire", 0))
	assert(state.learn_skill("fire") and state.learn_skill("ice"))
	assert(not state.learn_skill("fire"))
	assert(state.assign_skill("fire", 0) and state.assign_skill("ice", 1))
	assert(state.assign_skill("fire", 1))
	assert(state.get_skill_slots() == ["ice", "fire", ""])
	assert(not state.assign_skill("heal", 2))
	assert(state.equip("staff"))
	assert(state.has_learned_skill("fire"))
	assert(is_equal_approx(state.get_skill_bonus("fire"), 10.0))
	assert(state.unequip(EquipmentDefinition.Slot.ACCESSORY))
	assert(is_zero_approx(state.get_skill_bonus("fire")))
	var saved_path := "D:/.codexfile/work/equipment-skills-ui/test-state.json"
	assert(state.save_to_path(saved_path) == OK)
	var restored := LoadoutState.new(catalog, 3)
	assert(restored.load_from_path(saved_path))
	assert(restored.export_state() == state.export_state())
	var before_invalid := restored.export_state()
	assert(not restored.import_state({"version": 999}))
	assert(restored.export_state() == before_invalid)
	var damaged := state.export_state()
	damaged.owned_equipment.append("deleted_item")
	damaged.equipped = ["armor", "staff", "deleted_item"]
	damaged.skill_slots = ["fire", "fire", "heal"]
	assert(restored.import_state(damaged))
	assert("deleted_item" not in restored.get_owned_equipment())
	assert(restored.get_equipped_id(0).is_empty() and restored.get_equipped_id(1).is_empty())
	assert(restored.get_skill_slots() == ["fire", "", ""])
	state.set_skill_slot_count(1)
	assert(state.get_skill_slots() == ["ice"])
	print("PASS: equipment replacement, previews, skill learning and swapping, bonus aggregation, save/load and stale data validation.")
	quit()
