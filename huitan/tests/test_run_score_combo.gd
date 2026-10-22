extends SceneTree

var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var state = load("res://scripts/combat/run_score_state.gd").new()
	check(state.has_method("begin_attack"), "计分须支持每刀／每片攻击的独立倍率快照")
	if not state.has_method("begin_attack"):
		print("SCORE_COMBO: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	var rules = load("res://scripts/combat/run_score_rules.gd").new()
	rules.combo_thresholds = PackedInt32Array([2, 4, 6])
	rules.combo_multipliers = PackedFloat32Array([1.25, 1.5, 2.0])
	rules.burst_thresholds = PackedInt32Array([2, 4])
	rules.burst_rewards = PackedInt32Array([25, 50])
	state.begin(1, rules)
	rules.combo_multipliers[0] = 9.0
	var first = state.begin_attack(0.0)
	state.record_kill(1, 10, true, first, 0.1)
	state.record_kill(2, 10, true, first, 0.2)
	check(state.total == 45 and state.kill_score == 20 and state.combo_score == 0 and state.burst_score == 25, "同刀使用同一倍率，成片奖励即时入账")
	var second = state.begin_attack(0.3)
	check(second.multiplier_milli == 1250, "连杀升档从后续攻击生效，开局规则快照不受编辑影响")
	state.record_kill(3, 10, true, second, 0.3)
	state.record_kill(4, 10, true, second, 0.4)
	check(state.combo_score == 5 and state.burst_score == 50 and state.total == 95, "小数余量保留，不因每只取整少给分，固定奖励不吃倍率")
	state.record_kill(5, 10, true, first, 0.5)
	state.record_kill(6, 10, true, first, 0.6)
	check(state.burst_score == 75 and state.total == 140, "同攻击升档只补奖励差额，不把每档奖励重复相加")
	var total: int = state.total
	state.record_kill(1, 10, true, first, 0.7)
	check(state.total == total and state.kills == 6 and first.kills == 4, "重复死亡不推进连杀、攻击击杀数或奖励")
	state.record_kill(7, 2, false, first, 1.0)
	check(state.total == 142 and state.combo_kills == 6 and first.kills == 4, "幼体只给基础分，不推进连杀或成片门槛")
	check(state.begin_attack(4.5).multiplier_milli == 2000, "四秒宽限内保持连杀倍率")
	check(state.begin_attack(5.0).multiplier_milli == 1500, "空窗后只降一档")
	check(state.begin_attack(6.0).multiplier_milli == 1250, "继续空窗逐档衰减")
	check(state.begin_attack(7.0).multiplier_milli == 1000, "衰减回基础倍率，无需逐帧推进")
	var before_wave: int = state.total
	state.record_wave(1)
	state.record_wave(1)
	check(state.total == before_wave + 100, "清波分独立入账，不受连杀倍率影响或重复支付")
	var before_finish: int = state.total
	state.finish(1, true)
	check(state.total == before_finish and state.eligible_for_submission, "结束不追加结算倍率或回算已得分")
	state.record_kill(8, 10, true, second, 8.0)
	check(state.total == before_finish and state.begin_attack(9.0) == null, "结算后停止计分和攻击批次创建")
	var snapshot: Dictionary = state.snapshot()
	check(snapshot.total == snapshot.kill_score + snapshot.combo_score + snapshot.burst_score + snapshot.wave_score, "完整分项能解释最终总分")
	check(snapshot.performance_score == snapshot.combo_score + snapshot.burst_score, "保留旧协议的表现分汇总字段")
	state.begin(2, rules)
	state.record_kill(9, 10, true, first, 0.0)
	check(state.total == 0 and state.kills == 0, "上局攻击快照不能给新局加分")
	var other = load("res://scripts/combat/run_score_state.gd").new()
	other.begin(2, rules)
	state.record_kill(10, 10, true, other.begin_attack(0.0), 0.0)
	check(state.total == 0, "不同计分实例不能混用攻击快照")
	state.begin(3, rules, true)
	state.record_kill(11, 100, true, null, 0.0)
	state.record_wave(1)
	state.finish(1, true)
	check(state.total == 0 and not state.eligible_for_submission, "模拟模式不计连杀、成片或清波分")
	var plain = load("res://scripts/combat/run_score_rules.gd").new()
	plain.combo_enabled = false
	plain.burst_enabled = false
	state.begin(4, plain)
	var plain_attack = state.begin_attack(0.0)
	for index in 40: state.record_kill(index + 1, 10, true, plain_attack, 0.0)
	check(state.total == 400 and state.combo_score == 0 and state.burst_score == 0, "两项机制可独立关闭，基础计分不受影响")
	plain.combo_enabled = true
	plain.combo_thresholds = PackedInt32Array([2])
	plain.combo_multipliers = PackedFloat32Array([1.25])
	state.begin(5, plain)
	var queued_first = state.begin_attack(0.0)
	var queued_second = state.begin_attack(0.0)
	state.record_kill(1, 10, true, queued_first, 0.0)
	state.record_kill(2, 10, true, queued_first, 0.0)
	state.record_kill(3, 10, true, queued_second, 0.0)
	check(queued_second.multiplier_milli == 1250 and state.total == 32, "同帧预收集多刀时，后一刀仍能接上前一刀取得的连杀倍率")
	state.reset()
	check(state.rules == null and state.combo_kills == 0 and state.total == 0 and state.combo_score == 0 and state.burst_score == 0, "重试／返回准备清空全部本局计分状态")
	print("SCORE_COMBO: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
