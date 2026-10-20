extends SceneTree

var failures := 0
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	var catalog: LoadoutCatalog = load("res://data/rpg/loadout_catalog.tres")
	var state := LoadoutState.new(catalog)
	for item in catalog.equipment:
		state.acquire_equipment(item.id)
	for id in ["sword", "armor", "amulet"]: state.equip(id)
	state.learn_skill("fire")
	state.train("health")
	var saved := state.export_state()
	var equipped_attributes := state.get_character_attributes()
	var equipped_power: float = state.get_skill_values("fire").power
	var player := Player.new()
	player.character_state = state
	player.take_damage(10)
	state.set("equipment_bonuses_enabled", false)
	check(state.get_attribute_totals().is_empty(), "Disabled equipment cannot contribute any character attribute")
	check(state.get_skill_bonus("fire") == 0 and state.get_skill_values("fire").power < equipped_power, "Legacy skill equipment scaling is disabled too")
	check(state.get_character_attributes() == {"health": 110.0, "mana": 100.0, "attack": 10.0, "defense": 5.0}, "Base and training values remain without equipment")
	check(state.preview_character_attributes("staff") == state.get_character_attributes(), "Equipment previews cannot report disabled benefits")
	check(player.max_health == 110 and player.current_health == 100, "Bound player recalculates actual health and preserves existing lost health")
	check(state.export_state() == saved, "Disabling bonuses leaves equipment, training and inventory save data untouched")
	var restored := LoadoutState.new(catalog)
	restored.set("equipment_bonuses_enabled", false)
	check(restored.import_state(saved) and restored.get_character_attributes() == state.get_character_attributes(), "Existing equipped saves cannot re-enable the disabled bonuses")
	check(restored.export_state() == saved, "Loading into the new policy preserves the complete old save")
	state.set("equipment_bonuses_enabled", true)
	check(state.get_character_attributes() == equipped_attributes and state.get_skill_values("fire").power == equipped_power, "Legacy maps keep their original equipment rules")
	player.free()
	var world: SceneCombatConfiguration = load("res://data/combat/scenes/world/configuration.tres")
	var city: SceneCombatConfiguration = load("res://data/combat/scenes/city/configuration.tres")
	check(world.get("equipment_bonuses_enabled") == false and city.get("equipment_bonuses_enabled") == true, "Only the formal World disables equipment bonuses")
	print("Equipment bonus policy: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
