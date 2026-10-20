extends SceneTree

class Session extends Node3D:
	signal run_started
	signal run_ended(reason: String)
	signal enemy_defeated_at(position: Vector3, amount: int)
	signal wave_clearing
	signal phase_changed(phase: int)
	enum Phase { READY, BATTLE, REST, RESULT }
	var phase := Phase.BATTLE
	var player := Node3D.new()
	var combat_frozen := false
	func set_combat_frozen(value: bool) -> void: combat_frozen = value
	func is_wave_finish_pending() -> bool: return false

var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	assert(value, message)

func _initialize() -> void:
	create_timer(15).timeout.connect(func(): quit(2))
	run.call_deferred()

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
	var second := GrowthChoiceOption.new()
	second.id = &"epic_two"
	second.epic = true
	var pool: Array[GrowthChoiceOption] = [ordinary, epic, second]
	growth.candidate_provider = func(): return pool
	session.add_child(growth)
	growth.choice_ui._audio.enabled = false
	growth.set_physics_process(false)
	growth.choice_ui.open_duration = 0
	var levels: Array[int] = []
	growth.growth_chosen.connect(func(level: int, id: StringName):
		levels.append(level)
		for item in pool:
			if item.id == id: item.growth_level += 1)
	session.run_started.emit()
	growth.state.level = 4
	growth._grant_experience(3)
	check(growth.state.level == 7 and growth.choice_options.all(func(item): return item.epic), "A multi-level XP pickup opens epic choice for pending level five")
	check(growth.choice_ui.title.contains("5") and growth.choice_ui.selected_index == -1, "Milestone title uses pending level and never preselects")
	check(growth.choice_ui.select_option(&"epic"), "Milestone unlock can be selected")
	growth.choice_ui.confirm_selection()
	check(levels == [5] and growth.choice_ui.title.contains("6"), "Only one epic round is paid at level five")
	check(growth.choice_options.any(func(item): return item.id == &"epic") and not growth.choice_options.any(func(item): return item.id == &"epic_two"), "Acquired epic continues in ordinary pool while unowned epic stays locked")
	check(growth.choice_options.any(func(item): return item.id == &"epic" and item.growth_level == 1), "Card copies preserve current epic rank for future card presentation")
	check(growth.choice_options.all(func(item): return item.hide_category), "World cards share an ungrouped layout")
	growth.choice_ui.select_option(&"epic")
	growth.choice_ui.confirm_selection()
	growth.choice_ui.select_option(&"ordinary")
	growth.choice_ui.confirm_selection()
	check(levels == [5, 6, 7] and not session.combat_frozen and not growth.choice_ui.is_open, "Consecutive choices consume exact levels and thaw combat")
	check(growth.rerolls_left == 3, "Small-pool draws consume no reroll budget")
	var draw := GrowthDrawPool.new()
	draw.free_selection = true
	draw.reset(20261020)
	ordinary.ricochet_growth = true
	var missed_ricochet := false
	for i in 60:
		var cards := draw.draw(pool, 1)
		if cards[0] != ordinary: missed_ricochet = true
	check(missed_ricochet, "Free selection does not reserve a ricochet slot")
	growth._end_run("test")
	session.free()
	await process_frame
	print("PASS epic draw: %d checks" % checks)
	quit()
