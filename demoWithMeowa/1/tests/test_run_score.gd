extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var state := RunScoreState.new()
	var rules := RunScoreRules.new()
	state.record_kill(1, 10, true, &"flight_sword", 1)
	check(state.total == 0, "Inactive state ignores kills")
	state.begin(1, rules)
	rules.wave_points = 900
	check(state.rules.wave_points == 100, "Rules are snapshotted per run")
	state.begin_flight(1)
	for index in 12: state.record_kill(index + 1, 10, true, &"flight_sword", 1)
	check(state.kill_score == 120 and state.performance_score == 20 and state.total == 140, "Only small capped performance reward is added to real base kills")
	state.record_kill(1, 10, true, &"flight_sword", 1)
	check(state.total == 140 and state.kills == 12, "Repeated death cannot score twice")
	state.record_kill(20, 2, false, &"flight_sword", 1)
	check(state.flight_kills == 12 and state.total == 142, "Infants score low base points without advancing performance")
	state.begin_flight(2)
	state.record_kill(21, 10, true, &"ricochet_storm", 1)
	state.record_kill(22, 10, true, &"ricochet_storm", 0)
	state.record_kill(23, 10, true, &"basic_sword", 2)
	check(state.flight_kills == 0, "Old storm, tail damage and manual attacks do not join a new volley")
	for index in 3: state.record_kill(30 + index, 10, true, &"ricochet_storm", 2)
	check(state.flight_kills == 3 and state.performance_score == 25, "A fresh volley can earn its own first tier")
	state.record_wave(1)
	state.record_wave(1)
	check(state.wave_score == 100, "Each wave pays once")
	state.finish(2, true)
	check(state.wave_score == 200 and state.snapshot().completed_waves == 2, "Final cleared wave settles before the final snapshot")
	var total := state.total
	state.record_wave(2)
	state.record_kill(99, 10, true, &"flight_sword", 2)
	check(state.total == total and state.eligible_for_submission, "Late signals cannot change a settled score")
	state.begin(2, RunScoreRules.new(), true)
	state.begin_flight(3)
	state.record_kill(100, 20, true, &"flight_sword", 3)
	state.record_wave(1)
	state.finish(1, true)
	check(state.total == 0 and not state.eligible_for_submission, "Simulation does not score or qualify for submission")
	state.begin(3, RunScoreRules.new())
	state.record_kill(1, 10, false, &"basic_sword", 0)
	state.finish(0, false)
	check(state.total == 10 and not state.eligible_for_submission, "Error preserves earned points but excludes the result")
	var saved_rules := state.rules
	state.reset()
	check(state.total == 0 and state.run_id == 0 and state.rules == null and not state.active and not state.eligible_for_submission, "Returning to preparation clears score without starting a run")
	state.record_kill(120, 20, true, &"flight_sword", 1)
	state.record_wave(1)
	check(state.total == 0, "Late combat events cannot restore a discarded run's score")
	state.begin(4, saved_rules)
	var definition := WaveEnemyDefinition.new()
	definition.enemy_id = &"mini_slime"
	check(state.rules.points_for(definition) == 2, "Infant override is independent of experience")
	definition.enemy_id = &"pot_brood"
	check(state.rules.points_for(definition) == 20, "Pot parent has its own points even with COMMON crowd role")
	definition.enemy_id = &"new_special"
	definition.role = WaveEnemyDefinition.Role.SPECIAL
	check(state.rules.points_for(definition) == 20, "New special enemies inherit sensible score defaults")
	var wave_scene: PackedScene = load("res://scenes/combat/wave_prototype.tscn")
	var instance := wave_scene.instantiate()
	check(instance.get_node_or_null("RunScore") != null and instance.get_node_or_null("ScoreHUD") != null, "Shared battle scene includes real scoring and HUD")
	instance.free()
	print("RUN_SCORE_TEST ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
