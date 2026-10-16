extends SceneTree
## 技能核心应能在没有地图、波次、成长界面和存档的树中独立工作。

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
	create_timer(10.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func make_manager() -> RunSkillManager:
	var manager := RunSkillManager.new()
	var skill := SkillFixture.new()
	skill.name = "ExampleSkill"
	skill.definition = CombatSkillDefinition.new()
	skill.definition.id = &"example"
	skill.definition.display_name = "Example"
	skill.definition.levels = [CombatSkillLevel.new(), CombatSkillLevel.new()]
	manager.add_child(skill)
	manager.skill_paths.append(NodePath("ExampleSkill"))
	root.add_child(manager)
	return manager

func run() -> void:
	var first := make_manager()
	var second := make_manager()
	check(first.get_registered_ids() == [&"example"], "Standalone startup registers configured components without a battle session")
	check(second.get_registered_ids() == [&"example"], "Another standalone manager initializes independently")
	check(first.candidates().size() == 1, "Skill upgrade candidates do not require growth or a choice UI")
	check(first.set_skill_level(&"example", 1), "Standalone manager can learn a skill")
	check(first.get_level(&"example") == 1 and second.get_level(&"example") == 0, "Learning state is isolated per manager")
	check(first.set_skill_enabled(&"example", false) and second.is_skill_enabled(&"example"), "Runtime switches are isolated per manager")
	first.reset()
	check(first.get_level(&"example") == 0 and first.is_skill_enabled(&"example"), "Core reset restores configured state without run lifecycle signals")
	first.unregister_skill(&"example")
	check(first.get_slots().is_empty() and first.get_registered_ids().is_empty(), "Standalone unregister clears registry and learned slots")
	check(get_first_node_in_group(&"gameplay_input_blockers") == null, "Skill state operations create no modal UI")
	first.free()
	second.free()
	await process_frame
	print(JSON.stringify({"suite":"run_skill_manager_standalone", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
