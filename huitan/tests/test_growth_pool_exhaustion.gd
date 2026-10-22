extends "res://tests/test_epic_draw.gd"

func run() -> void:
	var session := Session.new()
	session.add_child(session.player)
	root.add_child(session)
	var growth: RunGrowth = load("res://scenes/growth/run_growth.tscn").instantiate()
	growth.session = session
	growth.progression_rules = RunGrowthRules.new()
	growth.rules = ExperienceRules.new()
	growth.rules.first_level_experience = 1
	growth.rules.per_level_increase = 0
	growth.rules.curve_increase = 0
	var ordinary := GrowthChoiceOption.new()
	ordinary.id = &"ordinary"
	var epic := GrowthChoiceOption.new()
	epic.id = &"epic"
	epic.epic = true
	var pool: Array[GrowthChoiceOption] = [ordinary, epic]
	growth.candidate_provider = func(): return pool
	session.add_child(growth)
	growth.choice_ui._audio.enabled = false
	growth.set_physics_process(false)
	growth.choice_ui.open_duration = 0
	var skipped: Array[int] = []
	var granted: Array[int] = []
	growth.growth_choice_skipped.connect(func(level: int): skipped.append(level))
	growth.growth_chosen.connect(func(level: int, id: StringName):
		granted.append(level)
		for item in pool:
			if item.id == id: item.growth_level += 1)
	session.run_started.emit()
	growth.state.level = 9
	growth._grant_experience(2)
	check(skipped.is_empty() and growth.choice_ui.is_open and growth.choice_ui.title.contains("10"), "An exhausted legendary tier keeps the pending milestone and offers lower-rarity cards")
	check(growth.choice_options.size() == 1 and growth.choice_options[0].id == &"epic" and growth.choice_ui.title.contains("史诗"), "Legendary fallback prefers eligible epic cards and labels the actual choice")
	check(growth.state.pending_choices == 2 and session.combat_frozen and growth.rerolls_left == 3, "Fallback preserves every pending reward and its shared reroll budget")
	growth.choice_ui.select_option(&"epic")
	growth.choice_ui.confirm_selection()
	check(granted == [10] and growth.choice_ui.title.contains("11") and session.combat_frozen, "Confirming the lower-rarity fallback grants the tenth-level reward before advancing")
	growth.choice_ui.select_option(&"ordinary")
	growth.choice_ui.confirm_selection()
	check(granted == [10, 11] and not session.combat_frozen and not growth.choice_ui.is_open, "Both valid rewards apply once before the modal and freeze end")
	epic.enabled = false
	growth.state.level = 14
	growth._grant_experience(1)
	check(skipped.is_empty() and growth.state.pending_choices == 1 and growth.choice_ui.is_open and growth.choice_ui.title == "等级 15 · 成长选择", "An exhausted epic tier offers common cards with the ordinary choice title")
	growth.choice_ui.select_option(&"ordinary")
	growth.choice_ui.confirm_selection()
	ordinary.enabled = false
	growth.state.level = 19
	growth._grant_experience(2)
	check(skipped == [20, 21] and growth.state.pending_choices == 0 and not growth.choice_ui.is_open and not session.combat_frozen, "Only fully empty pools skip consecutive pending choices without opening UI")
	ordinary.enabled = true
	growth.progression_rules.ordinary_rarity_weights = {0:0.0}
	growth._grant_experience(1)
	check(skipped[-1] == 22 and growth.state.pending_choices == 0 and not growth.choice_ui.is_open, "Zero-weight ordinary pools skip safely without freezing")
	check(growth.rerolls_left == 3 and granted == [10, 11, 15], "Fallback rewards and truly skipped rounds preserve rerolls without false grants")
	growth._end_run("test")
	session.free()
	await process_frame
	print("PASS growth pool exhaustion: %d checks" % checks)
	quit()
