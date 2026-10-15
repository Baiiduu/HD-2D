extends SceneTree

const POOL := preload("res://scripts/growth/growth_draw_pool.gd")

class SkillProbe extends Node:
	var definition: CombatSkillDefinition
	var level := 0
	func get_skill_definition() -> CombatSkillDefinition: return definition
	func apply_skill_level(value: int) -> bool:
		level = value
		return true
	func describe_skill_upgrade(_from: int, _to: int) -> String: return "Test-only pool expansion"

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func ids(options: Array[GrowthChoiceOption]) -> Array[StringName]:
	var result: Array[StringName] = []
	for option in options: result.append(option.id)
	result.sort()
	return result

func settle() -> void:
	for frame in 12: await physics_frame

func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()

func pool_checks() -> void:
	var pool: Array[GrowthChoiceOption] = []
	for index in 7:
		var option := GrowthChoiceOption.new()
		option.id = StringName("card%d" % index)
		option.category = GrowthChoiceOption.Category.LEARN_SKILL if index < 3 else GrowthChoiceOption.Category.GLOBAL_BUFF
		option.enabled = index < 6
		pool.append(option)
	var draw = POOL.new()
	draw.reset(426)
	var seen := {}
	for round in 120:
		var cards: Array[GrowthChoiceOption] = draw.draw(pool, 3)
		check(cards.size() == 3 and ids(cards).size() == 3 and cards[0] != cards[1] and cards[0] != cards[2] and cards[1] != cards[2], "Three different rewards are drawn")
		check(cards.all(func(option: GrowthChoiceOption): return option.enabled), "Unavailable cards never occupy a slot")
		check(cards.any(func(option: GrowthChoiceOption): return option.category == GrowthChoiceOption.Category.LEARN_SKILL), "Eligible pool retains a skill direction")
		seen[str(ids(cards))] = true
		var rerolled: Array[GrowthChoiceOption] = draw.draw(pool, 3, cards)
		check(ids(rerolled) != ids(cards), "Reroll actually changes rewards")
	check(seen.size() > 8, "Repeated draws produce varied reward combinations")
	var short: Array[GrowthChoiceOption] = [pool[0], pool[1]]
	check(draw.draw(short, 3).size() == 2 and not draw.can_redraw(short, short), "Short pool uses available cards without blanks or paid reorder")
	check(not draw.valid_pool([pool[0], pool[0]]) and not draw.valid_pool([null]), "Malformed pools are rejected")
	var same = POOL.new()
	draw.reset(28)
	same.reset(28)
	check(ids(draw.draw(pool, 3)) == ids(same.draw(pool, 3)), "Test seed reproduces a draw independently of combat RNG")

func ui_checks() -> void:
	var ui: GrowthChoiceUI = load("res://scenes/ui/growth_choice_ui.tscn").instantiate()
	root.add_child(ui)
	var option := GrowthChoiceOption.new()
	option.id = &"animation"
	var cards: Array[GrowthChoiceOption] = [option]
	var confirmations := [0]
	ui.choice_confirmed.connect(func(_id: StringName): confirmations[0] += 1)
	check(ui.present_choices(cards) and not ui.cards_revealed, "Real draw begins with a card back")
	check(not ui.select_option(option.id), "Hidden cards cannot be selected")
	ui.confirm_selection()
	check(confirmations[0] == 0, "Reveal animation cannot accidentally grant a reward")
	key(KEY_ENTER)
	check(ui.cards_revealed and ui.get_selected_option() == null and ui._confirm.disabled, "Skipping animation still requires explicit choice")
	check(ui.select_option(option.id), "Revealed card becomes selectable")
	ui.confirm_selection()
	check(confirmations[0] == 1 and not ui.is_open, "Selected card is awarded once")
	ui.present_choices(cards)
	ui.close()
	ui.open_duration = 0
	ui.present_choices(cards)
	await create_timer(0.4).timeout
	check(ui.cards_revealed and ui._cards[0].scale == Vector2.ONE and ui.get_selected_option() == null, "Old reveal callbacks cannot mutate a reopened draw")
	ui.queue_free()
	await process_frame

func run() -> void:
	pool_checks()
	await ui_checks()
	AudioServer.set_bus_mute(0, true)
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("MapEffects/BGM").music_enabled = false
	var wave: WavePrototype = world.get_node("WavePrototype")
	var skills: RunSkills = wave.get_node("RunSkills")
	var growth: RunGrowth = wave.get_node("RunGrowth")
	growth.draw_seed = 617
	growth.get_node("GrowthChoiceUI").open_duration = 0
	skills.get_node("InitialSkillChoice").open_duration = 0
	var fourth := SkillProbe.new()
	fourth.name = "FourthSkillProbe"
	fourth.definition = CombatSkillDefinition.new()
	fourth.definition.id = &"probe"
	fourth.definition.display_name = "Probe"
	fourth.definition.levels.assign([CombatSkillLevel.new(), CombatSkillLevel.new()])
	wave.add_child(fourth)
	skills.skill_paths.append(NodePath("../FourthSkillProbe"))
	root.add_child(world)
	current_scene = world
	await settle()
	wave.player.set_physics_process(false)
	wave.set_physics_process(false)
	growth.set_physics_process(false)
	var save_before := wave.loadout.state.export_state().duplicate(true)
	check(wave.start_run() and skills.initial_choice.is_open and not growth.active, "Initial draw opens before enemies and run experience")
	check(skills.initial_choice._options.size() == 3 and skills._initial_pool.size() == skills._components.size() and skills._initial_pool.size() > 3, "Expanded starting pool draws three instead of showing every skill")
	var first_draw := ids(skills._initial_cards)
	skills.initial_choice.request_reroll()
	check(growth.rerolls_left == 2 and ids(skills._initial_cards) != first_draw, "Initial draw consumes one shared reroll")
	var kept := ids(skills._initial_cards)
	skills.initial_choice.cancel()
	check(wave.start_run() and ids(skills._initial_cards) == kept and growth.rerolls_left == 2, "Cancel and reopen neither redraw nor refund the budget")
	var initial_id: StringName
	for option in skills._initial_cards:
		if option.id != &"initial:probe": initial_id = option.id; break
	check(skills.initial_choice.select_option(initial_id), "An actual skill can be learned from the draw")
	skills.initial_choice.confirm_selection()
	check(wave.phase == WavePrototype.Phase.BATTLE and growth.active and growth.rerolls_left == 2, "Starting battle preserves initial reroll spending")
	for definition in wave.get_node("RunBuffs").definitions:
		var text: String = wave.get_node("RunBuffs")._description(definition)
		check(not text.contains("扇") and not text.contains("雷光") and not text.contains("棱光"), "Global buff copy contains no current weapon descriptions")
	growth._grant_experience(10)
	check(growth.choice_options.size() == 3 and wave.combat_frozen and not paused, "Real level gain draws three and freezes only combat")
	check(growth.choice_ui.get_selected_option() == null, "Upgrade does not preselect a reward")
	var pending := growth.state.pending_choices
	var levels := skills._levels.duplicate()
	var buffs := wave.combat_modifiers.levels.duplicate()
	var spawn_rng := wave._random.state
	var style: int = world.get_node("VisualSample").style
	for reroll in 2:
		var previous := ids(growth.choice_options)
		key(KEY_R)
		check(ids(growth.choice_options) != previous, "Shared remaining reroll changes actual upgrade cards")
		check(growth.state.pending_choices == pending and skills._levels == levels and wave.combat_modifiers.levels == buffs and wave.combat_frozen, "Reroll grants no skill or buff and consumes no pending level")
	check(growth.rerolls_left == 0 and growth.choice_ui._reroll.disabled and wave._random.state == spawn_rng, "Three total rerolls cannot perturb enemy spawn RNG")
	check(world.get_node("VisualSample").style == style, "Real reroll key is consumed without changing world Style")
	var exhausted := ids(growth.choice_options)
	growth.choice_ui.request_reroll()
	check(ids(growth.choice_options) == exhausted, "Exhausted reroll key has no effect")
	for option in growth._candidate_pool:
		if not exhausted.has(option.id):
			growth._confirm_choice(option.id)
			break
	check(growth.state.pending_choices == pending and skills._levels == levels and wave.combat_modifiers.levels == buffs, "Hidden pool entries cannot be confirmed")
	growth.choice_ui.select_option(growth.choice_options[0].id)
	growth.choice_ui.confirm_selection()
	check(growth.state.pending_choices == 0 and not wave.combat_frozen, "Visible reward applies and restores combat")
	growth._grant_experience(60)
	check(growth.state.pending_choices >= 2, "Large pickup queues multiple real draws")
	var remaining := growth.state.pending_choices
	growth.choice_ui.confirm_selection()
	check(growth.state.pending_choices == remaining, "Repeated Enter cannot claim an unselected next draw")
	while growth.choice_ui.is_open:
		growth.choice_ui.select_option(growth.choice_options[0].id)
		growth.choice_ui.confirm_selection()
		if growth.state.pending_choices > 0: check(wave.combat_frozen, "Queued draws retain combat freeze without a gap")
	check(wave.loadout.state.export_state() == save_before, "Run draft and rewards leave permanent loadout untouched")
	wave.retreat()
	wave.retry()
	check(skills.initial_choice.is_open and growth.rerolls_left == 3 and skills.get_slots().is_empty(), "Retry begins a fresh skill draw and shared budget")
	world.queue_free()
	await settle()
	# Let the audio mixer retire UI playbacks before the headless process exits.
	await create_timer(0.25).timeout
	check(get_first_node_in_group(&"gameplay_input_blockers") == null, "World removal releases draw input ownership")
	print("Growth draw: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
