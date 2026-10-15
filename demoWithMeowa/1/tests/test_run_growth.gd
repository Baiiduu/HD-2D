extends SceneTree

class FlatPath extends RefCounted:
	func ground_position(point: Vector3) -> Vector3:
		return Vector3(point.x, 0, point.z)

class SessionProbe extends Node3D:
	signal run_started
	signal run_ended(reason: String)
	signal enemy_defeated_at(position: Vector3, experience: int)
	signal wave_clearing
	signal phase_changed(phase: int)
	enum Phase { READY, BATTLE, REST, RESULT }
	var player := Node3D.new()
	var _path := FlatPath.new()
	var combat_frozen := false
	var frames := 0
	func _process(_delta: float) -> void: frames += 1
	func set_combat_frozen(value: bool) -> void: combat_frozen = value

var checks := 0

func _initialize() -> void:
	create_timer(15.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	assert(value, message)

func run() -> void:
	var session := SessionProbe.new()
	session.add_child(session.player)
	root.add_child(session)
	var growth: RunGrowth = load("res://scenes/growth/run_growth.tscn").instantiate()
	growth.session = session
	session.add_child(growth)
	growth.set_physics_process(false)
	growth.choice_ui.open_duration = 0.0
	growth.choice_ui.hover_duration = 0.0
	var choices: Array[Array] = []
	growth.growth_chosen.connect(func(level: int, id: StringName): choices.append([level, id]))
	check(not growth.active and growth.state.level == 1, "No experience outside an active run")
	session.enemy_defeated_at.emit(Vector3.ZERO, 3)
	check(growth._drops.is_empty(), "Inactive run ignores death drops")
	session.run_started.emit()
	session.enemy_defeated_at.emit(Vector3.ZERO, 3)
	check(growth._drops.size() == 1 and growth.state.experience == 0, "Death creates a drop instead of immediately awarding experience")
	growth._physics_process(1.0)
	check(growth._drops.is_empty() and growth.state.experience == 3, "Physical approach collects into run state")
	growth._physics_process(1.0)
	check(growth.state.total_experience == 3, "Collected drop is not awarded again")
	session.enemy_defeated_at.emit(Vector3(8, 0, 0), 2)
	session.enemy_defeated_at.emit(Vector3(10, 0, 0), 5)
	growth._physics_process(0.2)
	check(growth._drops.size() == 2 and growth.state.experience == 3, "Distant experience remains on the ground")
	session.enemy_defeated_at.emit(Vector3.ZERO, 7)
	growth._physics_process(1.0)
	check(growth.state.level == 2 and growth.choice_ui.is_open and session.combat_frozen, "Level crossing opens choice UI and freezes combat")
	check(not paused and get_first_node_in_group(&"gameplay_input_blockers") == growth.choice_ui, "Level UI blocks player controls without pausing the world")
	check(growth.choice_ui._cards[0].get_node("Title").text.is_empty() and growth.choice_ui._cards[0].get_node("Description").text.is_empty(), "Undesigned upgrades remain blank")
	var old_positions: Array[Vector3] = []
	for drop in growth._drops: old_positions.append(drop.global_position)
	growth._physics_process(10.0)
	check(growth._drops[0].global_position == old_positions[0] and growth._drops[1].global_position == old_positions[1], "Pickup motion and collection remain frozen")
	var before := session.frames
	await create_timer(0.1).timeout
	check(session.frames > before, "Unrelated world process continues during a choice")
	growth.choice_ui.select_option(&"slot_a")
	growth.choice_ui.confirm_selection()
	check(not session.combat_frozen and not growth.choice_ui.is_open and choices == [[2, &"slot_a"]], "Confirmation returns a level and candidate identifier then resumes combat")
	growth.choice_ui.confirm_selection()
	check(choices.size() == 1, "Duplicate confirmation cannot consume another level")
	session.enemy_defeated_at.emit(Vector3(15, 0, 0), 30)
	session.wave_clearing.emit()
	check(growth._drops.is_empty() and growth.state.level == 4 and growth.state.pending_choices == 2, "Wave cleanup absorbs remaining experience and queues every crossed level")
	check(growth.choice_ui.title == "等级 3 · 成长选择", "First pending level has the correct title")
	growth.choice_ui.select_option(&"slot_a")
	growth.choice_ui.confirm_selection()
	check(session.combat_frozen and growth.choice_ui.is_open and growth.choice_ui.title == "等级 4 · 成长选择", "Consecutive level choices have no combat gap")
	growth.choice_ui.select_option(&"slot_b")
	growth.choice_ui.confirm_selection()
	check(not session.combat_frozen and choices == [[2, &"slot_a"], [3, &"slot_a"], [4, &"slot_b"]], "Every pending selection is returned exactly once in level order")
	growth.max_pickups = 1
	growth.drop_experience(Vector3(9, 0, 0), 4)
	growth.drop_experience(Vector3(10, 0, 0), 6)
	check(growth._drops.size() == 1 and growth._drops[0].amount == 10, "Pickup cap merges experience without deleting its value")
	growth.collect_remaining_on_clear = false
	session.wave_clearing.emit()
	check(growth._drops.size() == 1, "Automatic wave-end collection can be disabled")
	session.run_ended.emit("test end")
	check(not growth.active and growth._drops.is_empty() and not growth.choice_ui.is_open and not session.combat_frozen, "Run end clears drops, modal and freeze")
	session.phase_changed.emit(session.Phase.READY)
	session.run_started.emit()
	check(growth.state.level == 1 and growth.state.total_experience == 0 and growth.state.pending_choices == 0, "Starting another run resets all local growth")
	growth.drop_experience(Vector3.ZERO, 45)
	growth.collect_all()
	check(growth.state.pending_choices == 3 and session.combat_frozen, "One pickup can queue three upgrade choices")
	session.run_ended.emit("interrupt")
	check(not growth.choice_ui.is_open and not session.combat_frozen and growth.state.pending_choices == 0, "Interrupting a multi-level choice cannot leave the game frozen")
	session.run_started.emit()
	growth.enabled = false
	growth.drop_experience(Vector3.ZERO, 100)
	check(not growth.active and growth._drops.is_empty(), "Other system tests can isolate growth through its own switch")
	session.free()
	await create_timer(0.1).timeout
	print("Run growth coordinator: %d checks passed" % checks)
	quit.call_deferred()
