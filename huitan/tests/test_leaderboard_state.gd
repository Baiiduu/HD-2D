extends SceneTree

var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func _initialize() -> void:
	var Model = load("res://scripts/network/leaderboard_state.gd")
	if Model == null:
		check(false, "需要独立的匿名身份、结算快照与幂等提交状态")
		quit(1)
		return
	var state = Model.new()
	state.create_identity()
	state.grant_consent(true, true)
	var identity: String = state.device_id
	check(identity.length() == 36 and state.device_token.length() == 64, "匿名身份使用随机 UUID 与独立 256 位凭证")
	state.nickname = "测试玩家"
	state.begin_run()
	var snapshot := {"total": 120, "kill_score": 20, "wave_score": 100, "performance_score": 0,
		"kills": 2, "completed_waves": 1, "rules_version": "test-v1", "active": false,
		"simulation": false, "eligible_for_submission": true}
	check(not state.capture(snapshot.merged({"active": true}, true)), "战斗中不能生成提交")
	check(not state.capture(snapshot.merged({"simulation": true}, true)), "模拟模式不提交")
	check(not state.capture(snapshot.merged({"eligible_for_submission": false}, true)), "异常结算不提交")
	check(not state.capture(snapshot.merged({"total": 1.5}, true)), "成绩须为整数")
	check(state.capture(snapshot), "真实结束快照可自动提交")
	var first: Dictionary = state.submission_body()
	check(not state.capture(snapshot), "同一结算重复通知不重建请求或清除回执")
	state.nickname = "更改的昵称"
	check(state.submission_body() == first, "请求失败后仍使用同一 UUID 和同一内容，不因改名破坏幂等")
	check(first.device_id == identity and first.score == 120 and not first.has("player_id"), "客户端不指定任意玩家或榜单")
	var path := "D:/.codexfile/work/leaderboard-deploy-20261020/godot-state-test.cfg"
	check(state.save_to(path) == OK, "待提交成绩和独立身份可持久化")
	var restored = Model.new()
	check(restored.load_from(path) == OK and restored.device_id == identity, "重启沿用身份")
	check(restored.submission_body() == first, "重启后失败重试保留原 UUID、昵称和快照")
	check(not restored.confirm({"submission_id": "wrong"}), "不确认错配的回执")
	check(restored.confirm({"submission_id": first.submission_id, "personal_best": 120}), "匹配的成功回执确认提交")
	check(not restored.can_submit(), "成功后不反复提交本局")
	restored.begin_run()
	check(restored.capture(snapshot) and restored.submission_body().submission_id != first.submission_id, "新挑战使用新的提交 UUID")
	check(restored.device_id == identity, "重试与新挑战不清空设备身份")
	restored.confirm({"submission_id": restored.pending.submission_id})
	restored.begin_run()
	var expanded := snapshot.merged({"total": 185, "kill_score": 60, "performance_score": 25,
		"combo_score": 0, "burst_score": 25, "eligible_kills": 6, "peak_multiplier_milli": 1250, "rules_version": "score_v2"}, true)
	check(restored.capture(expanded), "新计分版本保留自动提交资格")
	var expanded_body: Dictionary = restored.submission_body()
	check(expanded_body.metadata.rules_version == "score_v2" and expanded_body.metadata.burst_score == 25 and expanded_body.metadata.peak_multiplier_milli == 1250 and expanded_body.score == 185, "提交包含精简计分分项和真实总分")
	# Simulate a frozen request written by the previous client. Its body must stay exact.
	expanded_body.metadata.erase("combo_score")
	expanded_body.metadata.erase("burst_score")
	expanded_body.metadata.erase("eligible_kills")
	expanded_body.metadata.erase("peak_multiplier_milli")
	restored.frozen_body = expanded_body
	check(restored.save_to(path) == OK, "旧版冻结请求可继续持久化")
	var legacy = Model.new()
	check(legacy.load_from(path) == OK and legacy.submission_body() == expanded_body, "升级计分后不改写已冻结请求，保留超时重试的幂等内容")
	print("Leaderboard state: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
