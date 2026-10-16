extends SceneTree
const CHARACTER_MANAGER := "res://scripts/player/character_skill_manager.gd"
const RUN_MANAGER := "res://scripts/combat/run_skill_manager.gd"
var checks := 0
var failures: Array[String] = []

class Ability extends Node:
	var requests := 0
	var cancellations := 0
	func begin_charge(_direction: Vector3) -> bool: requests += 1; return true
	func aim(_direction: Vector3) -> void: requests += 1
	func release_charge() -> bool: requests += 1; return true
	func request(_direction: Vector3) -> void: requests += 1
	func cancel(_reset := false) -> void: cancellations += 1

func _initialize() -> void:
	create_timer(15.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures.append(label); push_error(label)

func run() -> void:
	check(ResourceLoader.exists(CHARACTER_MANAGER), "Character-owned abilities have a separate manager")
	check(ResourceLoader.exists(RUN_MANAGER), "Learnable skills use an explicitly named run manager")
	if not ResourceLoader.exists(CHARACTER_MANAGER) or not ResourceLoader.exists(RUN_MANAGER): quit(1); return
	var character = load(CHARACTER_MANAGER).new()
	var ricochet := Ability.new()
	var dash := Ability.new()
	character.add_child(ricochet)
	character.add_child(dash)
	root.add_child(character)
	check(character.register_skill(&"body_ricochet", ricochet, true) and character.register_skill(&"dash", dash, true), "Only character abilities are registered with their configured state")
	check(character.get_registered_ids().size() == 2 and character.get_skill(&"basic_sword") == null, "The character skill registry contains ricochet and dash; basic attack remains separate")
	check(character.begin_charge(Vector3.RIGHT) and ricochet.requests == 1, "Charge input routes to the character ability")
	character.aim_charge(Vector3.FORWARD)
	check(character.release_charge() and ricochet.requests == 3, "Aim and release use the same character manager")
	character.request_dash(Vector3.RIGHT)
	check(dash.requests == 1, "Dash input routes to its character ability")
	character.set_skill_enabled(&"dash", false)
	character.request_dash(Vector3.RIGHT)
	check(dash.requests == 1 and dash.cancellations == 1, "Disabling dash stops it and rejects subsequent direct input")
	var run_manager = load(RUN_MANAGER).new()
	root.add_child(run_manager)
	run_manager.reset()
	check(not character.is_skill_enabled(&"dash") and character.is_skill_enabled(&"body_ricochet"), "Resetting the run skill pool cannot rewrite character ability switches")
	check(run_manager.get_registered_ids().is_empty() and not run_manager.set_skill_level(&"body_ricochet", 1) and not run_manager.set_skill_level(&"dash", 1), "Character abilities have no learnable levels or upgrade slots")
	character.set_combat_frozen(true)
	check(not character.begin_charge(Vector3.RIGHT) and not character.release_charge(), "Combat freeze blocks character skill input without disabling its configured ability")
	check(character.is_skill_enabled(&"body_ricochet"), "Freeze preserves character skill availability")
	character.set_combat_frozen(false)
	character.reset()
	check(character.is_skill_enabled(&"dash") and character.get_registered_ids().size() == 2, "Character reset restores its own defaults without removing innate skills")
	character.unregister_skill(&"body_ricochet")
	check(not character.begin_charge(Vector3.RIGHT), "Unregistered ricochet cannot receive input")
	run_manager.free()
	character.free()
	await process_frame
	print(JSON.stringify({"suite":"character_skill_ownership", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)
