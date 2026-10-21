extends SceneTree

const Session = preload("res://tests/fixtures/ricochet_session.gd")
var checks := 0
var failures := 0
var wave: WavePrototype
var score: RunScore
var hud: ScoreHUD
var run_id := 0
var enemy_id := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(message)

func _initialize() -> void:
	run.call_deferred()

func restart() -> void:
	run_id += 1
	wave.set_combat_frozen(false)
	hud.show()
	score.state.begin(run_id, score.rules)
	hud._process(0.0)

func award(points: int) -> void:
	enemy_id += 1
	score.state.record_kill(enemy_id, points, false)

func run() -> void:
	wave = Session.new()
	root.add_child(wave)
	score = RunScore.new()
	score.session = wave
	score.rules = RunScoreRules.new()
	wave.add_child(score)
	hud = ScoreHUD.new()
	hud.score = score
	wave.add_child(hud)
	hud.set_process(false)
	restart()

	# 击杀经验立刻打开选卡：真实分数已到账，UI 合并与动效尚未播放。
	award(10)
	hud._process(0.1)
	wave.set_combat_frozen(true)
	hud._process(4.0)
	check(score.state.total == 10, "选卡隐藏期间真实分数保留")
	check(not hud._root.visible, "战斗冻结隐藏得分 HUD")
	check(hud._pending == 10 and is_equal_approx(hud._merge_time, 0.1), "隐藏期间不能消耗待显示加分及合并时间")
	check(hud._display == 0 and hud._gain.text.is_empty(), "隐藏期间不提前播放计数和加分")
	wave.set_combat_frozen(false)
	hud._process(0.21)
	check(hud._gain.text == "+10" and hud._gain.modulate.a == 1.0, "关闭选卡后显示完整的加分提示")
	check(is_equal_approx(hud._feedback_time, 0.62), "新提示首个可见帧保留完整时长")
	hud._process(0.1)
	var remaining := hud._feedback_time
	var displayed := hud._display
	var pulse := hud._pulse.duplicate()
	wave.set_combat_frozen(true)
	hud._process(2.0)
	check(is_equal_approx(hud._feedback_time, remaining) and hud._display == displayed and hud._pulse == pulse, "已播放一部分的提示在隐藏时保留计数、跳字与淡出进度")
	wave.set_combat_frozen(false)
	hud._process(0.1)
	check(is_equal_approx(hud._feedback_time, remaining - 0.1), "恢复可见后继续提示剩余时间")
	hud._process(1.0)
	check(hud._display == 10 and hud._gain.modulate.a == 0.0, "正常显示后计数完成并淡出")

	# 帧耗时跨过合并窗口时，不能在同一帧把刚创建的提示耗尽。
	restart()
	award(20)
	hud._process(1.0)
	check(hud._gain.text == "+20" and hud._gain.modulate.a == 1.0, "长帧仍至少呈现一次完整加分")
	check(hud._count_time == 0.0 and is_equal_approx(hud._pulse[0], 0.26), "长帧不跳过刚启动的计数和变化位动效")
	hud._process(0.3)
	check(hud._display == 20 and hud._gain.modulate.a == 1.0, "后续可见帧按原计数与淡出规则推进")

	# 管理输入占用同样隐藏 HUD；期间多个奖励仍正常入账并合并。
	restart()
	var blocker := Node.new()
	root.add_child(blocker)
	blocker.add_to_group(&"gameplay_input_blockers")
	award(10)
	hud._process(2.0)
	award(20)
	hud._process(2.0)
	check(not hud._root.visible and hud._pending == 30, "管理界面下保留多次加分")
	check(score.state.total == 30, "界面隐藏不延迟真实入账")
	blocker.free()
	hud._process(0.31)
	check(hud._gain.text == "+30" and hud._gain.modulate.a == 1.0, "关闭管理界面后合并显示全部待提示分数")
	var snapshot := score.state.snapshot()
	hud._process(2.0)
	check(score.state.snapshot() == snapshot, "HUD 动画不重复计分或修改结算快照")

	# 入场/菜单可直接隐藏整个 CanvasLayer，未改战斗冻结状态。
	restart()
	hud.hide()
	award(40)
	hud._process(2.0)
	check(hud._pending == 40 and hud._display == 0, "CanvasLayer 隐藏也保留待显示提示")
	hud.show()
	hud._process(0.31)
	check(hud._gain.text == "+40" and hud._gain.modulate.a == 1.0, "CanvasLayer 恢复后显示提示")

	# 最终结算通过 changed 信号立即提交，可能发生在 HUD 隐藏期间。
	restart()
	wave.set_combat_frozen(true)
	award(10)
	score.state.finish(1, true)
	check(score.state.total == 110 and hud._gain.text == "+110", "最后击杀与补齐清波奖合并，结算仍即时完成")
	hud._process(3.0)
	check(is_equal_approx(hud._feedback_time, 0.85), "隐藏的最终清波提示不能提前淡出")
	wave.set_combat_frozen(false)
	wave.add_to_group(&"gameplay_input_blockers")
	hud._process(2.0)
	check(hud._root.visible and hud._gain.modulate.a == 1.0, "结算自身输入占用不隐藏 HUD，首个可见帧保留最终加分")
	hud._process(1.0)
	check(hud._display == 110 and hud._gain.modulate.a == 0.0, "最终得分正常完成计数与淡出")
	wave.remove_from_group(&"gameplay_input_blockers")
	restart()
	hud._process(1.0)
	check(hud._gain.text.is_empty() and hud._display == 0 and hud._pending == 0, "重试清空上一局提示，不重播旧加分")

	wave.free()
	await process_frame
	print("SCORE_GAIN_VISIBILITY: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
