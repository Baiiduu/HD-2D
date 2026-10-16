extends SceneTree
const SETTINGS_PATH := "res://scripts/core/game_system_settings.gd"
const SkillFixture := preload("res://tests/test_run_skill_manager_contract.gd").SkillFixture
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(15.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func skill() -> SkillFixture:
	var node := SkillFixture.new()
	node.name = "Example"
	node.definition = CombatSkillDefinition.new()
	node.definition.id = &"example"
	node.definition.levels = [CombatSkillLevel.new(), CombatSkillLevel.new()]
	return node

func make_manager() -> RunSkillManager:
	var manager := RunSkillManager.new()
	manager.add_child(skill())
	manager.skill_paths.append(NodePath("Example"))
	root.add_child(manager)
	return manager

func run() -> void:
	check(ResourceLoader.exists(SETTINGS_PATH), "Game Manager uses project settings independently from scene nodes")
	if not ResourceLoader.exists(SETTINGS_PATH): quit(1); return
	var settings = load(SETTINGS_PATH)
	var editor_panel = load("res://addons/game_manager/panel.gd").new()
	check(editor_panel.set_switch(settings.DRAFT, false, false) == OK and not settings.is_enabled(settings.DRAFT), "Editor control writes the shared project setting without a map")
	check(editor_panel.set_switch(&"unknown_system", false, false) == ERR_INVALID_PARAMETER, "Editor control rejects unknown systems")
	editor_panel.free()
	for id in [settings.UPGRADES, settings.DRAFT, settings.RUN_SKILLS]:
		ProjectSettings.set_setting(settings.key(id), true)
	var manager := make_manager()
	check(manager.has_method("is_enabled"), "Run skill management has an explicit effective switch")
	if not manager.has_method("is_enabled"): manager.free(); quit(1); return
	check(manager.set_skill_level(&"example", 1), "Enabled run skill management supports normal learning")
	manager.set("enabled", false)
	check(not manager.call("is_enabled") and manager.candidates().is_empty() and manager.get_slots().is_empty(), "Local disable removes candidates and active skill slots")
	check(manager.get_level(&"example") == 1 and manager.get_skill(&"example").applied == 0 and not manager.get_skill(&"example").enabled, "Disable stops execution while retaining the learned level")
	check(not manager.set_skill_level(&"example", 2) and not manager.set_skill_enabled(&"example", true), "Direct calls cannot bypass a disabled system")
	manager.set("enabled", true)
	check(manager.call("is_enabled") and manager.get_level(&"example") == 1 and manager.get_skill(&"example").applied == 1, "Re-enable restores the prior learned skill")
	manager.set("enabled", false)
	manager.reset()
	manager.set("enabled", true)
	check(manager.get_level(&"example") == 0 and manager.is_skill_available(&"example"), "A new run still clears learning while the system is disabled")
	manager.free()
	ProjectSettings.set_setting(settings.key(settings.RUN_SKILLS), false)
	manager = make_manager()
	check(not manager.call("is_enabled") and not manager.set_skill_level(&"example", 1), "The editor project switch also gates a fresh standalone manager")
	manager.set("enabled", false)
	manager.set("enabled", true)
	check(not manager.call("is_enabled"), "A local switch cannot override a disabled project system")
	var detached := manager.get_skill(&"example")
	manager.unregister_skill(&"example")
	check(detached.enabled and detached.applied == 0, "Unregistering a suspended component restores its own switch while keeping it unlearned")
	manager.free()
	for id in [settings.UPGRADES, settings.DRAFT, settings.RUN_SKILLS]: ProjectSettings.set_setting(settings.key(id), true)
	await process_frame
	print(JSON.stringify({"suite":"game_system_switches", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
