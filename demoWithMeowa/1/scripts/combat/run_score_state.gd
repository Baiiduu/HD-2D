class_name RunScoreState
extends RefCounted

const AttackBatch = preload("res://scripts/combat/score_attack_batch.gd")

signal changed
## UI 只合并显示，不延迟真实计分。details 不包含场景节点。
signal awarded(amount: int, kind: StringName, details: Dictionary)

var rules: RunScoreRules
var run_id := 0
var active := false
var simulation := false
var eligible_for_submission := false
var total := 0
var kill_score := 0
var wave_score := 0
var performance_score := 0
var combo_score := 0
var burst_score := 0
var kills := 0
var eligible_kills := 0
var combo_kills := 0
var peak_multiplier_milli := 1000
var _epoch := 0
var _clock := 0.0
var _next_decay_at := INF
var _fraction := 0
var _defeated := {}
var _waves := {}

func reset() -> void:
	rules = null
	run_id = 0
	active = false
	simulation = false
	_clear_values()
	changed.emit()

func _clear_values() -> void:
	_epoch += 1
	eligible_for_submission = false
	total = 0
	kill_score = 0
	wave_score = 0
	performance_score = 0
	combo_score = 0
	burst_score = 0
	kills = 0
	eligible_kills = 0
	combo_kills = 0
	peak_multiplier_milli = 1000
	_clock = 0.0
	_next_decay_at = INF
	_fraction = 0
	_defeated.clear()
	_waves.clear()

func begin(id: int, configuration: RunScoreRules, simulated := false) -> void:
	rules = configuration.duplicate(true)
	run_id = id
	simulation = simulated
	active = true
	_clear_values()
	changed.emit()

func begin_attack(combat_time := 0.0) -> AttackBatch:
	if not active or simulation: return null
	_sync_time(combat_time)
	var batch := AttackBatch.new()
	batch.owner_id = get_instance_id()
	batch.epoch = _epoch
	batch.multiplier_milli = rules.combo_multiplier_milli(combo_kills)
	return batch

func record_kill(enemy_id: int, points: int, performance_allowed: bool, batch: AttackBatch = null, combat_time := 0.0) -> void:
	if not active or simulation or enemy_id <= 0 or _defeated.has(enemy_id): return
	if batch and (batch.owner_id != get_instance_id() or batch.epoch != _epoch): return
	_sync_time(combat_time)
	_defeated[enemy_id] = true
	kills += 1
	var base := maxi(points, 0)
	kill_score += base
	var awarded_points := base
	if performance_allowed and base > 0:
		if batch and not batch.locked:
			batch.multiplier_milli = rules.combo_multiplier_milli(combo_kills)
			batch.locked = true
		var multiplier := batch.multiplier_milli if batch else rules.combo_multiplier_milli(combo_kills)
		awarded_points = _weighted_points(base, multiplier)
		combo_score += awarded_points - base
		performance_score += awarded_points - base
		eligible_kills += 1
		if rules.combo_enabled:
			combo_kills = mini(combo_kills + 1, rules.combo_threshold(rules.combo_thresholds.size()))
			peak_multiplier_milli = maxi(peak_multiplier_milli, rules.combo_multiplier_milli(combo_kills))
			_next_decay_at = _clock + maxf(0.1, rules.combo_grace_seconds)
	_award(awarded_points, &"kill", {})
	if performance_allowed and base > 0 and batch:
		batch.kills += 1
		var reward := rules.burst_reward(batch.kills)
		var bonus := maxi(0, reward - batch.rewarded)
		batch.rewarded = reward
		burst_score += bonus
		performance_score += bonus
		_award(bonus, &"burst", {})
	changed.emit()

@warning_ignore("integer_division")
func _weighted_points(base: int, multiplier: int) -> int:
	var scaled := base * multiplier + _fraction
	_fraction = scaled % 1000
	return scaled / 1000

## Lazy decay on attack/kill events, using the existing battle clock. No ticking.
func _sync_time(combat_time: float) -> void:
	if is_finite(combat_time): _clock = maxf(_clock, combat_time)
	if not rules.combo_enabled or combo_kills == 0 or _clock < _next_decay_at: return
	var tier := rules.combo_tier(combo_kills)
	var interval := maxf(0.1, rules.combo_decay_seconds)
	var steps := 1 + floori(minf(tier + 1.0, (_clock - _next_decay_at) / interval))
	combo_kills = rules.combo_threshold(maxi(0, tier - steps))
	_next_decay_at += steps * interval

func record_wave(number: int) -> void:
	if not active or simulation or number <= 0 or _waves.has(number): return
	_waves[number] = true
	var points := maxi(rules.wave_points, 0)
	wave_score += points
	_award(points, &"wave", {"wave": number})
	changed.emit()

func finish(completed: int, valid_result: bool) -> void:
	if not active: return
	# 有限最后一波的 run_ended 先于 wave_cleared；在冻结快照前补齐。
	for number in range(1, completed + 1): record_wave(number)
	active = false
	eligible_for_submission = valid_result and not simulation
	changed.emit()

func snapshot() -> Dictionary:
	return {"run_id": run_id, "rules_version": String(rules.rules_version) if rules else "", "total": total,
		"kill_score": kill_score, "wave_score": wave_score, "performance_score": performance_score,
		"combo_score": combo_score, "burst_score": burst_score, "eligible_kills": eligible_kills,
		"peak_multiplier_milli": peak_multiplier_milli,
		"kills": kills, "completed_waves": _waves.size(), "simulation": simulation,
		"active": active, "eligible_for_submission": eligible_for_submission}

func _award(amount: int, kind: StringName, details: Dictionary) -> void:
	if amount <= 0: return
	total += amount
	awarded.emit(amount, kind, details)
