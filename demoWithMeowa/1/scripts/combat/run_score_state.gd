class_name RunScoreState
extends RefCounted

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
var kills := 0
var flight_id := 0
var flight_kills := 0
var _flight_reward := 0
var _defeated := {}
var _waves := {}

func reset() -> void:
	rules = null
	run_id = 0
	active = false
	simulation = false
	eligible_for_submission = false
	total = 0
	kill_score = 0
	wave_score = 0
	performance_score = 0
	kills = 0
	flight_id = 0
	flight_kills = 0
	_flight_reward = 0
	_defeated.clear()
	_waves.clear()
	changed.emit()

func begin(id: int, configuration: RunScoreRules, simulated := false) -> void:
	rules = configuration.duplicate(true)
	run_id = id
	simulation = simulated
	active = true
	eligible_for_submission = false
	total = 0
	kill_score = 0
	wave_score = 0
	performance_score = 0
	kills = 0
	flight_id = 0
	flight_kills = 0
	_flight_reward = 0
	_defeated.clear()
	_waves.clear()
	changed.emit()

func begin_flight(id: int) -> void:
	if not active or simulation or id <= 0 or id == flight_id: return
	flight_id = id
	flight_kills = 0
	_flight_reward = 0

func record_kill(enemy_id: int, points: int, performance_allowed: bool, source: StringName, origin_flight: int) -> void:
	if not active or simulation or enemy_id <= 0 or _defeated.has(enemy_id): return
	_defeated[enemy_id] = true
	kills += 1
	var base := maxi(points, 0)
	kill_score += base
	_award(base, &"kill", {})
	if performance_allowed and origin_flight > 0 and origin_flight == flight_id and source in [&"flight_sword", &"ricochet_storm"]:
		flight_kills += 1
		var reward := rules.performance_reward(flight_kills)
		var bonus := maxi(0, reward - _flight_reward)
		_flight_reward = reward
		performance_score += bonus
		_award(bonus, &"performance", {"kills": flight_kills, "flight_id": flight_id})
	changed.emit()

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
		"kills": kills, "completed_waves": _waves.size(), "simulation": simulation,
		"active": active, "eligible_for_submission": eligible_for_submission}

func _award(amount: int, kind: StringName, details: Dictionary) -> void:
	if amount <= 0: return
	total += amount
	awarded.emit(amount, kind, details)
