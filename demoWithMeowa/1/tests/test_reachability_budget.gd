extends SceneTree

## Only replace the geometric query: exercise the real round, clocks and cleanup.
class BudgetWave extends WavePrototype:
	var calls: Dictionary[int, Array] = {}
	var goal_queries := 0
	var stop_after_query := false

	func _ready() -> void:
		set_physics_process(false)
		set_process_unhandled_key_input(false)

	func _ground_target() -> Vector3:
		goal_queries += 1
		return Vector3.ZERO

	func _check_enemy_reachability(enemy: WaveEnemy, _goal: Vector3, elapsed: float) -> void:
		var id := enemy.get_instance_id()
		if not calls.has(id): calls[id] = []
		calls[id].append({"elapsed": elapsed, "clock": _reachability_clock})
		if stop_after_query: _finish("budget fixture ended")

	func total_calls() -> int:
		var total := 0
		for history: Array in calls.values(): total += history.size()
		return total


var checks := 0
var failures := 0
var fixtures: Array[BudgetWave] = []

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func make_wave(count: int) -> BudgetWave:
	var wave := BudgetWave.new()
	root.add_child(wave)
	wave.phase = WavePrototype.Phase.BATTLE
	fixtures.append(wave)
	for index in count: add_enemy(wave)
	return wave

func add_enemy(wave: BudgetWave, warning := 0.0) -> WaveEnemy:
	var enemy := WaveEnemy.new()
	enemy.definition = WaveEnemyDefinition.new()
	enemy.spawn_delay = warning
	enemy.set_physics_process(false)
	wave.add_child(enemy)
	wave.enemies.append(enemy)
	# Match the real spawn registration; warning eligibility is sampled per visit.
	wave._reachability_last[enemy.get_instance_id()] = wave._reachability_clock
	wave._alive_by_definition[enemy.definition] = 1
	wave._alive_by_role[enemy.definition.role] += 1
	wave._population_cost += enemy.definition.population_cost
	return enemy

func count_calls(wave: BudgetWave, enemy: WaveEnemy) -> int:
	return wave.calls.get(enemy.get_instance_id(), []).size()

func coverage_checks() -> void:
	for count in [1, 60, 512]:
		var wave := make_wave(count)
		var peak := 0
		for frame in 60:
			var before := wave.total_calls()
			var previous_goals := wave.goal_queries
			wave._check_reachability(1.0 / 60.0)
			peak = maxi(peak, wave.total_calls() - before)
			check(wave.goal_queries - previous_goals <= 1, "%d monsters: compute the target at most once per tick" % count)
		var once := true
		for enemy in wave.enemies: once = once and count_calls(wave, enemy) == 1
		check(once, "%d monsters: fractional budgets cover the round exactly once in one second" % count)
		check(peak <= ceili(float(count) / 60.0) + 1, "%d monsters: no full-population catch-up spike at 60 Hz" % count)
		for frame in 60: wave._check_reachability(1.0 / 60.0)
		var interval_valid := true
		for enemy in wave.enemies:
			var history: Array = wave.calls.get(enemy.get_instance_id(), [])
			interval_valid = interval_valid and history.size() == 2
			if history.size() == 2:
				interval_valid = interval_valid and is_equal_approx(history[1].elapsed, 1.0)
		check(interval_valid, "%d monsters: the next visit reports real individual elapsed time" % count)

func long_frame_checks() -> void:
	var wave := make_wave(60)
	wave._check_reachability(3.25)
	var correct := true
	for enemy in wave.enemies:
		var history: Array = wave.calls.get(enemy.get_instance_id(), [])
		correct = correct and history.size() == 1
		if history.size() == 1: correct = correct and is_equal_approx(history[0].elapsed, 3.25)
	check(correct, "a long frame checks every current monster once and preserves elapsed combat time")
	check(wave.goal_queries == 1, "a long frame still computes the target only once")
	var mixed := make_wave(60)
	mixed._check_reachability(0.25)
	check(mixed.total_calls() == 15, "the first quarter-second checks one quarter of the round")
	mixed._check_reachability(3.0)
	check(mixed.total_calls() == 60, "a long frame finishes the current round without rechecking its earlier entries")
	mixed._check_reachability(1.0)
	check(mixed.total_calls() == 120, "discarded whole-round debt does not leak into later frames")

func warning_checks() -> void:
	var skipped := make_wave(0)
	var enemy := add_enemy(skipped, 2.0)
	skipped._check_reachability(1.0)
	check(skipped.total_calls() == 0 and skipped.goal_queries == 0 and not skipped._unreachable.has(enemy.get_instance_id()), "a warning entry spends its slot without querying geometry or accumulating failure")
	enemy.spawn_delay = 0.0
	skipped._check_reachability(0.5)
	skipped._check_reachability(0.5)
	var resumed: Array = skipped.calls.get(enemy.get_instance_id(), [])
	check(resumed.size() == 1 and is_equal_approx(resumed[0].elapsed, 1.0), "activation does not charge the check interval that was skipped during warning")

func lifecycle_checks() -> void:
	var wave := make_wave(60)
	wave._check_reachability(0.25)
	# Remove an entry whose snapshot slot has not been visited yet.
	var removed := wave.enemies[20]
	var removed_id := removed.get_instance_id()
	wave._unreachable[removed_id] = 0.25
	wave._enemy_defeated(removed)
	check(not wave._reachability_last.has(removed_id) and not wave._unreachable.has(removed_id), "defeat removes both reachability clocks and failure state")
	removed.free()
	var newborn := add_enemy(wave)
	var born_at := wave._reachability_clock
	for frame in 120: wave._check_reachability(1.0 / 60.0)
	var history: Array = wave.calls.get(newborn.get_instance_id(), [])
	check(not history.is_empty(), "an enemy appended mid-round is included in a later live snapshot")
	var covered := true
	for enemy in wave.enemies: covered = covered and count_calls(wave, enemy) >= 1
	check(covered and not wave.calls.has(removed_id), "a freed unvisited snapshot entry neither crashes nor skips its surviving neighbours")
	if not history.is_empty():
		check(is_equal_approx(history[0].elapsed, history[0].clock - born_at), "new monsters only receive elapsed time since their own registration")
	var exiting := wave.enemies[-1]
	var exiting_id := exiting.get_instance_id()
	wave._unreachable[exiting_id] = 1.0
	wave._enemy_exiting(exiting)
	check(wave.phase == WavePrototype.Phase.RESULT and wave.result_reason.contains("意外移除"), "unexpected removal still ends the run instead of faking a defeat")
	check(wave._reachability_last.is_empty() and wave._unreachable.is_empty() and wave._reachability_queue.is_empty(), "finishing clears remaining rounds and all per-monster state")
	check(wave._reachability_cursor == 0 and is_zero_approx(wave._reachability_clock) and is_zero_approx(wave._reachability_budget), "finishing resets scheduler clocks, cursor and fractional credit")
	# A new round must not inherit old object references, time or work debt.
	wave._reset_reachability()
	wave.calls.clear()
	wave.phase = WavePrototype.Phase.BATTLE
	add_enemy(wave)
	wave._check_reachability(1.0)
	check(wave.total_calls() == 1 and is_equal_approx(wave._reachability_clock, 1.0), "a restarted scheduler begins with clean time and membership")
	var stopping := make_wave(60)
	stopping.stop_after_query = true
	stopping._check_reachability(1.0)
	check(stopping.total_calls() == 1 and stopping.phase == WavePrototype.Phase.RESULT, "an error during a visit immediately stops the rest of the round")
	var restarted := make_wave(60)
	restarted.stop_after_query = true
	restarted.run_ended.connect(func(_reason: String):
		# Match a synchronous retry listener replacing the old run before _finish returns.
		restarted.phase = WavePrototype.Phase.BATTLE
		add_enemy(restarted), CONNECT_ONE_SHOT)
	restarted._check_reachability(1.0)
	check(restarted.phase == WavePrototype.Phase.BATTLE and restarted.total_calls() == 1 and restarted.enemies.size() == 1, "a synchronous end listener cannot let the old generation visit the restarted run")
	check(restarted._reachability_queue.is_empty() and is_zero_approx(restarted._reachability_clock) and is_zero_approx(restarted._reachability_budget), "the old visit does not mutate the replacement run's empty scheduler")
	restarted.stop_after_query = false
	restarted._check_reachability(1.0)
	var restarted_history: Array = restarted.calls.get(restarted.enemies[0].get_instance_id(), [])
	check(restarted.total_calls() == 2 and restarted_history.size() == 1 and is_equal_approx(restarted_history[0].elapsed, 1.0), "the replacement run receives its own first normal interval after synchronous restart")

func freeze_checks() -> void:
	var wave := make_wave(60)
	wave._check_reachability(0.4)
	var before := wave.total_calls()
	var clock := wave._reachability_clock
	var credit := wave._reachability_budget
	wave.set_combat_frozen(true)
	wave._check_reachability(20.0)
	check(wave.total_calls() == before and wave._reachability_clock == clock and wave._reachability_budget == credit, "combat freeze accrues neither time nor catch-up work")
	wave.set_combat_frozen(false)
	wave.phase = WavePrototype.Phase.REST
	wave._check_reachability(20.0)
	check(wave._reachability_clock == clock and wave.total_calls() == before, "safe rest cannot advance failure clocks")
	wave.phase = WavePrototype.Phase.BATTLE
	wave._check_reachability(0.0)
	wave._check_reachability(-1.0)
	check(wave._reachability_clock == clock and wave.total_calls() == before, "non-positive delta does not consume a visit or rewind combat time")
	wave._check_reachability(0.6)
	check(wave.total_calls() == 60 and is_equal_approx(wave._reachability_clock, 1.0), "resuming continues the interrupted round without frozen-time debt")

func run() -> void:
	coverage_checks()
	long_frame_checks()
	warning_checks()
	lifecycle_checks()
	freeze_checks()
	for wave in fixtures: wave.free()
	await process_frame
	print("Reachability budget: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
