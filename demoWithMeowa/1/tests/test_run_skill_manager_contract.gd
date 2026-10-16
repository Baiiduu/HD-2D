extends SceneTree
## 核心技能状态契约：不加载正式地图、地编、天气或存档。

class SessionFixture extends Node3D:
	signal changed
	signal run_started
	signal run_ended(reason: String)
	signal enemy_defeated_at(point: Vector3, experience: int)
	signal wave_clearing
	signal phase_changed(phase: int)
	enum Phase { READY, BATTLE, REST, RESULT }
	var phase := Phase.READY
	var player := Node3D.new()
	var combat_frozen := false
	var combat_nodes: Array[Node] = []
	func register_combat_node(node: Node) -> void:
		if node not in combat_nodes: combat_nodes.append(node)
	func unregister_combat_node(node: Node) -> void: combat_nodes.erase(node)
	func set_combat_frozen(value: bool) -> void: combat_frozen = value
	func can_start_run() -> bool: return phase == Phase.READY
	func start_run() -> bool:
		phase = Phase.BATTLE
		run_started.emit()
		return true

class SkillFixture extends Node:
	var enabled := true
	var definition: CombatSkillDefinition
	var applied := 0
	func get_skill_definition() -> CombatSkillDefinition: return definition
	func apply_skill_level(level: int) -> bool:
		if level < 0 or level > definition.levels.size(): return false
		applied = level
		return true
	func describe_skill_upgrade(from: int, to: int) -> String: return "%d → %d" % [from, to]

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var session := SessionFixture.new()
	session.add_child(session.player)
	var growth: RunGrowth = load("res://scenes/growth/run_growth.tscn").instantiate()
	growth.name = "RunGrowth"
	growth.session = session
	session.add_child(growth)
	var manager := RunSkillManager.new()
	var draft := RunSkillDraft.new()
	draft.session = session
	draft.manager = manager
	draft.growth = growth
	var choice: GrowthChoiceUI = load("res://scenes/ui/growth_choice_ui.tscn").instantiate()
	choice.name = "InitialSkillChoice"
	draft.add_child(choice)
	draft.initial_choice = choice
	choice.get_node("UIAudio").enabled = false
	for id in [&"active", &"disabled"]:
		var skill := SkillFixture.new()
		skill.name = String(id)
		skill.enabled = id == &"active"
		skill.definition = CombatSkillDefinition.new()
		skill.definition.id = id
		skill.definition.display_name = String(id)
		skill.definition.levels = [CombatSkillLevel.new(), CombatSkillLevel.new()]
		session.add_child(skill)
		manager.skill_paths.append(NodePath("../" + String(id)))
	session.add_child(manager)
	session.add_child(draft)
	root.add_child(session)
	growth.choice_ui.get_node("UIAudio").enabled = false
	growth.set_physics_process(false)
	check(session.combat_nodes.size() == 2, "Run binding registers existing components with the combat lifecycle")
	check(manager.candidates().size() == 1 and manager.candidates()[0].id == &"skill:active:1", "Configured disabled skills cannot enter the growth pool")
	check(not manager.set_skill_level(&"disabled", 1), "A configured unavailable skill cannot be learned by a direct command")
	manager.reset()
	check(draft.present_initial_choice(), "Available skills still open initial selection")
	check(draft._initial_pool.size() == 1 and draft._initial_pool[0].id == &"initial:active", "Initial draw excludes configured disabled skills")
	choice.cancel()
	check(manager.set_skill_enabled(&"active", false) and not manager.is_skill_enabled(&"active"), "Temporary execution disable is observable")
	check(manager.candidates().size() == 1, "Temporary execution disable preserves configured learning eligibility")
	manager.reset()
	check(manager.is_skill_enabled(&"active") and not manager.is_skill_enabled(&"disabled"), "New-run reset clears temporary disable and retains configured exclusions")
	check(manager.has_method("set_skill_available"), "Learning eligibility has an explicit API")
	if manager.has_method("set_skill_available"):
		manager.set_skill_available(&"active", false)
		check(manager.candidates().is_empty() and not manager.set_skill_level(&"active", 1), "Unavailable skills reject cards and learning together")
		manager.set_skill_available(&"active", true)
		manager.set_skill_enabled(&"active", true)
		check(manager.set_skill_level(&"active", 1), "Restoring eligibility allows learning again")
		manager.unregister_skill(&"active")
		check(session.get_node("active").applied == 0 and manager.get_slots().is_empty(), "Unregister stops learned skill state and clears slots")
		check(session.get_node("active") not in session.combat_nodes, "Unregister also detaches the component from combat freeze management")
	manager.set_skill_available(&"disabled", true)
	check(draft.present_initial_choice() and choice.is_open, "Changing the skill pool can open a fresh initial draw")
	session.remove_child(draft)
	check(not choice.is_open and get_first_node_in_group(&"gameplay_input_blockers") == null, "Removing the run binding closes its modal and releases input")
	check(not growth.candidate_provider.is_valid() and session.combat_nodes.is_empty(), "Removing the run binding clears its candidate provider and combat registrations")
	check(manager.set_skill_level(&"disabled", 1), "Skill core continues to work after the run binding is removed")
	draft.free()
	session.free()
	await process_frame
	print(JSON.stringify({"suite":"run_skill_manager_contract", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
