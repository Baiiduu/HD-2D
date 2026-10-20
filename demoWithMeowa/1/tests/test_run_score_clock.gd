extends SceneTree

const Session = preload("res://tests/fixtures/ricochet_session.gd")
var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func _initialize() -> void:
	run.call_deferred()

func phase(wave: WavePrototype, value: WavePrototype.Phase) -> void:
	# Isolate the clock bridge from spawning/navigation/UI; phase signals are real.
	wave.phase = value
	wave.phase_changed.emit(value)

func run() -> void:
	var wave := Session.new()
	root.add_child(wave)
	var score := RunScore.new()
	score.session = wave
	score.rules = RunScoreRules.new()
	score.rules.combo_thresholds = PackedInt32Array([1])
	score.rules.combo_multipliers = PackedFloat32Array([2.0])
	wave.add_child(score)
	score.state.begin(1, score.rules)
	phase(wave, WavePrototype.Phase.BATTLE)
	wave._wave_clock = 1.0
	score.state.record_kill(1, 10, true, null, score.combat_time())
	wave._wave_clock = 2.0
	wave.set_combat_frozen(true)
	wave._physics_process(20.0)
	check(is_equal_approx(score.combat_time(), 2.0), "冻结期间沿用真实战斗时钟，不累计连杀空窗")
	wave.set_combat_frozen(false)
	phase(wave, WavePrototype.Phase.REST)
	wave._wave_clock = 200.0
	check(is_equal_approx(score.combat_time(), 2.0), "休整不推进计分时钟")
	wave._wave_clock = 0.0
	phase(wave, WavePrototype.Phase.BATTLE)
	wave._wave_clock = 1.0
	check(is_equal_approx(score.combat_time(), 3.0) and score.state.begin_attack(score.combat_time()).multiplier_milli == 2000, "新波承接上波连杀和剩余宽限")
	wave._wave_clock = 3.1
	check(score.state.begin_attack(score.combat_time()).multiplier_milli == 1000, "仅实际战斗空窗导致降档")
	check(not score.is_processing() and not score.is_physics_processing(), "计分组件没有新增逐帧回调或定时器")
	phase(wave, WavePrototype.Phase.READY)
	check(score.state.total == 0 and score.combat_time() == 0.0, "回到准备阶段清空分数与计时桥")
	wave.free()
	await process_frame
	print("SCORE_CLOCK: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
