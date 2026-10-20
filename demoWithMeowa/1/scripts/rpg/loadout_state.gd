class_name LoadoutState
extends RefCounted

signal changed

const EQUIPMENT_SLOT_COUNT := 3
const SAVE_VERSION := 3
const QUICK_SLOT_COUNT := 8

var catalog: LoadoutCatalog
var training_rules: TrainingRules
## 地图运行规则，不写入存档；正式战斗可保留旧装备但不结算其数值。
var equipment_bonuses_enabled := true:
	set(value):
		if equipment_bonuses_enabled == value: return
		equipment_bonuses_enabled = value
		changed.emit()
var training_points := 0
var _training_levels: Dictionary[String, int] = {"health": 0, "attack": 0, "defense": 0}
var _owned: Array[String] = []
var _learned: Array[String] = []
var _equipped: Array[String] = ["", "", ""]
var _skill_slots: Array[String] = []
var _items: Dictionary[String, int] = {}
var _quick_slots: Array[String] = ["", "", "", "", "", "", "", ""]
var _favorites: Array[String] = []
var active_quick_slot := 0
## 旧存档升级时由界面初始化一次新物品，之后不会补回已耗尽的物品。
var inventory_initialized := false
var loaded_save_version := 0
## 按地图与格子保存，播种与库存扣除在同一次 changed 中提交。
var _farming: Dictionary = {}

func _init(source: LoadoutCatalog = null, skill_slot_count: int = 4, rules: TrainingRules = null) -> void:
	catalog = source
	training_rules = rules if rules else TrainingRules.new()
	training_points = training_rules.initial_points
	set_skill_slot_count(skill_slot_count)

func get_training_level(attribute: String) -> int:
	return _training_levels.get(attribute, 0)

func can_train(attribute: String) -> bool:
	return attribute in TrainingRules.ATTRIBUTES and get_training_level(attribute) < training_rules.level_cap and training_points >= training_rules.get_cost(get_training_level(attribute))

func train(attribute: String) -> bool:
	if not can_train(attribute):
		return false
	training_points -= training_rules.get_cost(get_training_level(attribute))
	_training_levels[attribute] += 1
	changed.emit()
	return true

func get_character_attributes() -> Dictionary[String, float]:
	return _character_attributes_with(get_attribute_totals())

func preview_character_attributes(equipment_id: String) -> Dictionary[String, float]:
	return _character_attributes_with(preview_attribute_totals(equipment_id))

func _character_attributes_with(equipment_bonus: Dictionary[String, float]) -> Dictionary[String, float]:
	var attributes := training_rules.get_base_attributes()
	for attribute in TrainingRules.ATTRIBUTES:
		attributes[attribute] += get_training_level(attribute) * training_rules.get_gain(attribute)
	for attribute in equipment_bonus:
		attributes[attribute] = attributes.get(attribute, 0.0) + equipment_bonus[attribute]
	return attributes

func get_owned_equipment() -> Array[String]:
	return _owned.duplicate()

func get_learned_skills() -> Array[String]:
	return _learned.duplicate()

func get_skill_slots() -> Array[String]:
	return _skill_slots.duplicate()

func get_inventory_ids() -> Array[String]:
	var ids: Array[String] = []
	ids.assign(_items.keys())
	ids.append_array(_owned)
	return ids

func get_quantity(id: String) -> int:
	return 1 if id in _owned else _items.get(id, 0)

func add_item(id: String, quantity := 1) -> bool:
	if not catalog or quantity <= 0:
		return false
	if catalog.get_equipment(id):
		return quantity == 1 and acquire_equipment(id)
	var entry := catalog.get_item(id)
	if not entry or (not entry.stackable and (quantity != 1 or get_quantity(id) > 0)) or get_quantity(id) > 2147483647 - quantity:
		return false
	_items[id] = get_quantity(id) + quantity
	changed.emit()
	return true

func remove_item(id: String, quantity := 1) -> bool:
	if not _remove_item(id, quantity): return false
	changed.emit()
	return true

func _remove_item(id: String, quantity: int) -> bool:
	if quantity <= 0 or get_quantity(id) < quantity:
		return false
	if id in _owned:
		_owned.erase(id)
		for slot in EQUIPMENT_SLOT_COUNT:
			if _equipped[slot] == id:
				_equipped[slot] = ""
	else:
		_items[id] -= quantity
		if _items[id] == 0:
			_items.erase(id)
	if get_quantity(id) == 0:
		_favorites.erase(id)
		for slot in QUICK_SLOT_COUNT:
			if _quick_slots[slot] == id:
				_quick_slots[slot] = ""
	return true

func _plot_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

func get_farm_plots(world_id: String) -> Dictionary:
	return _farming.get(world_id, {}).duplicate(true)

func get_farm_plot(world_id: String, cell: Vector2i) -> Dictionary:
	return _farming.get(world_id, {}).get(_plot_key(cell), {}).duplicate(true)

func till_farm_plot(world_id: String, cell: Vector2i) -> bool:
	if world_id.is_empty() or not get_farm_plot(world_id, cell).is_empty(): return false
	if not _farming.has(world_id): _farming[world_id] = {}
	_farming[world_id][_plot_key(cell)] = {"seed": "", "watered": false}
	changed.emit()
	return true

func plant_farm_plot(world_id: String, cell: Vector2i, seed_id: String) -> bool:
	var plot := get_farm_plot(world_id, cell)
	var seed := catalog.get_item(seed_id) if catalog else null
	if plot.is_empty() or not plot.seed.is_empty() or not seed or seed.farm_action != ItemDefinition.FarmAction.SEED:
		return false
	if not _remove_item(seed_id, 1): return false
	_farming[world_id][_plot_key(cell)].seed = seed_id
	changed.emit()
	return true

func water_farm_plot(world_id: String, cell: Vector2i) -> bool:
	var plot := get_farm_plot(world_id, cell)
	if plot.is_empty() or plot.watered: return false
	_farming[world_id][_plot_key(cell)].watered = true
	changed.emit()
	return true

func restore_farm_plot(world_id: String, cell: Vector2i, refund_seed := true) -> bool:
	var plot := get_farm_plot(world_id, cell)
	if plot.is_empty(): return false
	if refund_seed and not plot.seed.is_empty():
		var seed := catalog.get_item(plot.seed) if catalog else null
		if not seed or (not seed.stackable and get_quantity(seed.id) > 0) or get_quantity(seed.id) >= 2147483647:
			return false
		_items[seed.id] = get_quantity(seed.id) + 1
	_farming[world_id].erase(_plot_key(cell))
	if _farming[world_id].is_empty(): _farming.erase(world_id)
	changed.emit()
	return true

func get_quick_slots() -> Array[String]:
	return _quick_slots.duplicate()

func assign_item(id: String, slot: int) -> bool:
	if get_quantity(id) <= 0 or slot < 0 or slot >= QUICK_SLOT_COUNT or _quick_slots[slot] == id:
		return false
	var previous := _quick_slots.find(id)
	if previous >= 0:
		_quick_slots[previous] = _quick_slots[slot]
	_quick_slots[slot] = id
	changed.emit()
	return true

func clear_quick_slot(slot: int) -> bool:
	if slot < 0 or slot >= QUICK_SLOT_COUNT or _quick_slots[slot].is_empty():
		return false
	_quick_slots[slot] = ""
	changed.emit()
	return true

func select_quick_slot(slot: int) -> void:
	if slot < 0 or slot >= QUICK_SLOT_COUNT or active_quick_slot == slot:
		return
	active_quick_slot = slot
	changed.emit()

func is_favorite(id: String) -> bool:
	return id in _favorites

func toggle_favorite(id: String) -> void:
	if get_quantity(id) <= 0:
		return
	if id in _favorites:
		_favorites.erase(id)
	else:
		_favorites.append(id)
	changed.emit()

func sort_inventory() -> void:
	var ids := get_inventory_ids()
	ids.sort_custom(func(a: String, b: String):
		if is_favorite(a) != is_favorite(b): return is_favorite(a)
		if catalog.get_item_category(a) != catalog.get_item_category(b): return catalog.get_item_category(a) < catalog.get_item_category(b)
		return catalog.get_inventory_entry(a).display_name < catalog.get_inventory_entry(b).display_name)
	var sorted: Dictionary[String, int] = {}
	var gear: Array[String] = []
	for id in ids:
		if id in _owned: gear.append(id)
		else: sorted[id] = _items[id]
	_items = sorted
	_owned = gear
	changed.emit()

func get_equipped_id(slot: int) -> String:
	return _equipped[slot] if slot >= 0 and slot < EQUIPMENT_SLOT_COUNT else ""

func owns_equipment(id: String) -> bool:
	return id in _owned

func has_learned_skill(id: String) -> bool:
	return id in _learned

func acquire_equipment(id: String) -> bool:
	if not catalog or not catalog.get_equipment(id) or id in _owned:
		return false
	_owned.append(id)
	changed.emit()
	return true

func equip(id: String) -> bool:
	var entry := catalog.get_equipment(id) if catalog else null
	if not entry or id not in _owned or _equipped[entry.slot] == id:
		return false
	_equipped[entry.slot] = id
	changed.emit()
	return true

func unequip(slot: int) -> bool:
	if slot < 0 or slot >= EQUIPMENT_SLOT_COUNT or _equipped[slot].is_empty():
		return false
	_equipped[slot] = ""
	changed.emit()
	return true

func learn_skill(id: String) -> bool:
	if not catalog or not catalog.get_skill(id) or id in _learned:
		return false
	_learned.append(id)
	changed.emit()
	return true

func set_skill_slot_count(count: int) -> void:
	count = clampi(count, 1, 8)
	if count == _skill_slots.size():
		return
	while _skill_slots.size() < count:
		_skill_slots.append("")
	_skill_slots.resize(count)
	changed.emit()

func assign_skill(id: String, slot: int) -> bool:
	if id not in _learned or slot < 0 or slot >= _skill_slots.size() or _skill_slots[slot] == id:
		return false
	var previous := _skill_slots.find(id)
	if previous >= 0:
		# Moving an assigned skill swaps occupied slots instead of duplicating it.
		_skill_slots[previous] = _skill_slots[slot]
	_skill_slots[slot] = id
	changed.emit()
	return true

func unassign_skill(slot: int) -> bool:
	if slot < 0 or slot >= _skill_slots.size() or _skill_slots[slot].is_empty():
		return false
	_skill_slots[slot] = ""
	changed.emit()
	return true

func get_attribute_totals() -> Dictionary[String, float]:
	return _attribute_totals_for(_equipped)

func preview_attribute_totals(id: String) -> Dictionary[String, float]:
	var preview := _equipped.duplicate()
	var entry := catalog.get_equipment(id) if catalog else null
	if entry:
		preview[entry.slot] = id
	return _attribute_totals_for(preview)

func _attribute_totals_for(equipment_ids: Array[String]) -> Dictionary[String, float]:
	var totals: Dictionary[String, float] = {}
	if not equipment_bonuses_enabled: return totals
	for id in equipment_ids:
		var entry := catalog.get_equipment(id) if catalog else null
		if entry:
			for attribute in entry.attribute_bonuses:
				totals[attribute] = totals.get(attribute, 0.0) + entry.attribute_bonuses[attribute]
	return totals

func get_skill_bonus(id: String) -> float:
	if not equipment_bonuses_enabled: return 0.0
	var total := 0.0
	for equipment_id in _equipped:
		var entry := catalog.get_equipment(equipment_id) if catalog else null
		if entry:
			total += entry.skill_bonuses.get(id, 0.0)
	return total

func get_skill_values(id: String) -> Dictionary[String, float]:
	var entry := catalog.get_skill(id) if catalog else null
	var values: Dictionary[String, float] = {}
	if entry:
		values = entry.values.duplicate()
		if values.has("power"):
			values["power"] *= maxf(0.0, 1.0 + get_skill_bonus(id) / 100.0)
	return values

func export_state() -> Dictionary:
	return {"version": SAVE_VERSION, "owned_equipment": _owned.duplicate(), "equipped": _equipped.duplicate(),
		"learned_skills": _learned.duplicate(), "skill_slots": _skill_slots.duplicate(),
		"training": {"points": training_points, "levels": _training_levels.duplicate()},
		"items": _items.duplicate(), "quick_slots": _quick_slots.duplicate(),
		"favorites": _favorites.duplicate(), "active_quick_slot": active_quick_slot,
		"farming": _farming.duplicate(true)}

func import_state(data: Dictionary) -> bool:
	if not catalog or not _saved_integer(data.get("version", 0)) or int(data.get("version", 0)) not in [1, 2, SAVE_VERSION]:
		return false
	for field in ["owned_equipment", "equipped", "learned_skills", "skill_slots"]:
		if not data.get(field) is Array:
			return false
	# 旧版装备存档没有 training 字段，升级后只初始化一次。
	var points := training_rules.initial_points
	var levels: Dictionary[String, int] = {"health": 0, "attack": 0, "defense": 0}
	if data.has("training"):
		var training: Variant = data.training
		if not training is Dictionary or not training.get("levels") is Dictionary or not _saved_integer(training.get("points")):
			return false
		points = int(training.points)
		for attribute in TrainingRules.ATTRIBUTES:
			var level: Variant = training.levels.get(attribute)
			if not _saved_integer(level):
				return false
			levels[attribute] = int(level)
	var owned: Array[String] = []
	var learned: Array[String] = []
	for id in data.owned_equipment:
		if id is String and catalog.get_equipment(id) and id not in owned:
			owned.append(id)
	for id in data.learned_skills:
		if id is String and catalog.get_skill(id) and id not in learned:
			learned.append(id)
	var equipped: Array[String] = ["", "", ""]
	for slot in mini(EQUIPMENT_SLOT_COUNT, data.equipped.size()):
		var id: Variant = data.equipped[slot]
		if id is String and id in owned and catalog.get_equipment(id).slot == slot:
			equipped[slot] = id
	var slots: Array[String] = []
	for slot in _skill_slots.size():
		var id: Variant = data.skill_slots[slot] if slot < data.skill_slots.size() else ""
		slots.append(id if id is String and id in learned and id not in slots else "")
	var items: Dictionary[String, int] = {}
	var quick: Array[String] = ["", "", "", "", "", "", "", ""]
	var favorites: Array[String] = []
	var active := 0
	if data.version >= 2:
		if not data.get("items") is Dictionary or not data.get("quick_slots") is Array or not data.get("favorites") is Array or not _saved_integer(data.get("active_quick_slot")):
			return false
		for id in data.items:
			var quantity: Variant = data.items[id]
			if not id is String or not _saved_integer(quantity) or int(quantity) <= 0:
				return false
			var entry := catalog.get_item(id)
			if entry:
				if not entry.stackable and int(quantity) != 1:
					return false
				items[id] = int(quantity)
		for slot in mini(QUICK_SLOT_COUNT, data.quick_slots.size()):
			var id: Variant = data.quick_slots[slot]
			if id is String and (id in items or id in owned) and id not in quick:
				quick[slot] = id
		for id in data.favorites:
			if id is String and (id in items or id in owned) and id not in favorites:
				favorites.append(id)
		active = clampi(int(data.active_quick_slot), 0, QUICK_SLOT_COUNT - 1)
	var farming: Variant = data.get("farming", {})
	if not _valid_farming(farming): return false
	_owned = owned
	_learned = learned
	_equipped = equipped
	_skill_slots = slots
	_items = items
	_quick_slots = quick
	_favorites = favorites
	active_quick_slot = active
	inventory_initialized = data.version >= 2
	loaded_save_version = int(data.version)
	_farming = farming.duplicate(true)
	training_points = points
	_training_levels = levels
	changed.emit()
	return true

func _valid_farming(value: Variant) -> bool:
	if not value is Dictionary: return false
	for world_id in value:
		if not world_id is String or world_id.is_empty() or not value[world_id] is Dictionary: return false
		for key in value[world_id]:
			if not key is String: return false
			var parts: PackedStringArray = key.split(",")
			if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int(): return false
			if _plot_key(Vector2i(int(parts[0]), int(parts[1]))) != key: return false
			var plot: Variant = value[world_id][key]
			if not plot is Dictionary or not plot.get("seed") is String or not plot.get("watered") is bool: return false
	return true

func _saved_integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) == floorf(float(value)) and float(value) <= 2147483647.0

func save_to_path(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(export_state(), "\t"))
	return OK

func load_from_path(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		return false
	return import_state(json.data)
