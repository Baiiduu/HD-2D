extends SceneTree
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	assert(value, message)

func item(id: StringName, rarity: int, owned := 0) -> GrowthChoiceOption:
	var result := GrowthChoiceOption.new()
	result.id = id
	result.rarity = rarity
	result.growth_level = owned
	return result

func _initialize() -> void:
	var rules := RunGrowthRules.new()
	check(rules.has_method("is_legendary_level"), "Legendary milestones are explicit progression rules")
	if not rules.has_method("is_legendary_level"): quit(1); return
	check(rules.call("is_legendary_level", 10) and rules.call("is_legendary_level", 20) and not rules.call("is_legendary_level", 5), "Legendary cadence uses each pending tenth level")
	var common := item(&"common", 0)
	var epic := item(&"epic", 1)
	var legendary := item(&"legendary", 2)
	var owned := item(&"owned", 2, 1)
	var pool: Array[GrowthChoiceOption] = [common, epic, legendary, owned]
	check(rules.candidates(pool, 4) == [common, owned], "Unlearned high rarities stay locked in ordinary draws")
	check(rules.candidates(pool, 5) == [epic], "Fifth-level epic unlock behavior remains")
	check(rules.candidates(pool, 10).has(legendary) and not rules.candidates(pool, 10).has(owned), "Tenth-level draws prefer a new legendary mechanism")
	var draw := GrowthDrawPool.new()
	draw.free_selection = true
	draw.set("guaranteed_rarity", 2)
	draw.reset(42)
	for round in 40:
		var cards := draw.draw(pool, 3)
		check(cards.any(func(card): return card.get_card_rarity() == 2), "A legendary occupies at least one actual slot")
	draw.set("guaranteed_rarity", -1)
	draw.set("rarity_weights", {0:1.0, 1:0.0, 2:0.1})
	var ordinary_count := 0
	for round in 1500:
		var cards := draw.draw([common, epic, owned], 1)
		check(cards.size() == 1 and cards[0] != epic, "Zero-weight rarity is excluded")
		if cards[0] == common: ordinary_count += 1
	check(ordinary_count > 1300 and ordinary_count < 1430, "Configured relative rarity weights affect ordinary draws")
	draw.set("guaranteed_rarity", 2)
	check(not draw.can_redraw([common, owned], [owned]), "A one-slot guaranteed legendary cannot be rerolled into an ordinary card")
	var mods := RunCombatModifiers.new()
	check(mods.has_method("record_kill"), "Kill haste uses explicit actual-kill events")
	if not mods.has_method("record_kill"): quit(1); return
	mods.growth_rules = rules
	var card: GrowthBuffDefinition = load("res://data/combat/scenes/world/growth/legendary/kill_haste.tres")
	check(card != null and mods.apply_buff(card), "The legendary is a real learnable growth resource")
	for index in 15: mods.call("record_kill")
	check(mods.call("haste_stacks") == 10 and is_equal_approx(mods.call("haste_speed_multiplier"), 1.5), "Haste stacks cap and add movement speed")
	check(mods.bonus(GrowthBuffEffect.Attribute.ATTACK_SPEED) == 0.0 and mods.interval_multiplier() == 1.0, "Kill haste leaves attack speed unchanged")
	var preview := mods.preview_after(card)
	check(is_equal_approx(preview.call("haste_speed_multiplier"), 2.0) and is_equal_approx(mods.call("haste_speed_multiplier"), 1.5), "Upgrade previews preserve temporary stacks without mutating live state")
	mods.call("advance_temporary", 3.0)
	mods.call("record_kill")
	mods.call("advance_temporary", 1.01)
	check(mods.call("haste_stacks") == 1, "Each stack expires independently")
	mods.call("clear_temporary")
	check(mods.call("haste_stacks") == 0 and mods.level_for(card.id) == 1, "Wave cleanup removes haste but retains the learned card")
	mods.call("record_kill")
	mods.reset()
	check(mods.call("haste_stacks") == 0 and mods.level_for(card.id) == 0, "Run reset clears learned and temporary state")
	mods.apply_buff(card)
	mods.damage_disabled = true
	mods.record_kill()
	check(mods.haste_stacks() == 0, "Immortal simulation does not manufacture actual-kill haste")
	print("Legendary growth: %d checks" % checks)
	quit()
