class_name RunScore
extends Node

@export var session: WavePrototype
@export var rules: RunScoreRules
@export var online_demo_enabled := false
var state := RunScoreState.new()
var _lethal := {}
var _completed_wave_time := 0.0
var _counting_wave := false

func _ready() -> void:
	if not rules: rules = RunScoreRules.new()
	set_process(false)
	session.run_started.connect(_begin)
	session.run_ended.connect(_finish)
	session.phase_changed.connect(_phase_changed)
	session.wave_cleared.connect(state.record_wave)
	session.enemy_spawned.connect(_watch)

func _begin() -> void:
	_lethal.clear()
	_completed_wave_time = 0.0
	_counting_wave = false
	state.begin(int(session.get_run_state().run_id), rules, session.is_horde_simulation())
	if online_demo_enabled: get_node("/root/LeaderboardClient").begin_run()

func _phase_changed(phase: WavePrototype.Phase) -> void:
	if _counting_wave: _completed_wave_time += session._wave_clock
	_counting_wave = phase == WavePrototype.Phase.BATTLE
	if phase != WavePrototype.Phase.READY: return
	_lethal.clear()
	_completed_wave_time = 0.0
	state.reset()

func combat_time() -> float:
	return _completed_wave_time + (session._wave_clock if _counting_wave else 0.0)

## Optional attack context for weapons; one allocation per sword/patch, not hit.
func begin_attack() -> RunScoreState.AttackBatch:
	return state.begin_attack(combat_time()) if session.combat_active() else null

func _watch(enemy: WaveEnemy) -> void:
	if not state.active or state.simulation: return
	var id := enemy.get_instance_id()
	var serial := state.run_id
	# 只订阅实际注册的战斗怪物。清理/离树不产生死亡分。
	enemy.damaged.connect(_damaged)
	enemy.defeated.connect(_defeated.bind(serial), CONNECT_ONE_SHOT)
	enemy.tree_exiting.connect(func(): _lethal.erase(id), CONNECT_ONE_SHOT)

func _damaged(event: CombatDamageEvent) -> void:
	if state.active and not event.simulated and event.lethal and event.amount > 0.0:
		_lethal[event.target_id] = event

func _defeated(enemy: WaveEnemy, serial: int) -> void:
	var id := enemy.get_instance_id()
	var event: CombatDamageEvent = _lethal.get(id)
	_lethal.erase(id)
	if serial != state.run_id or not enemy.dead or not event: return
	var allowed := enemy.definition != null and enemy.definition.enemy_id not in state.rules.performance_excluded
	state.record_kill(id, state.rules.points_for(enemy.definition), allowed, event.score_batch, combat_time())

func _finish(_reason: String) -> void:
	state.finish(session.completed_waves, session.outcome in [WavePrototype.Outcome.VICTORY, WavePrototype.Outcome.DEFEAT, WavePrototype.Outcome.RETREAT])
	if online_demo_enabled: get_node("/root/LeaderboardClient").capture_run(state.snapshot())
	_lethal.clear()
