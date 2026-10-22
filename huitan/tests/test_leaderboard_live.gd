extends SceneTree
## Explicit opt-in live HTTP test; never part of ordinary regression runs.
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func _initialize() -> void:
	run.call_deferred()

func idle(client: Node) -> void:
	var deadline := Time.get_ticks_msec() + 25000
	while client.busy and Time.get_ticks_msec() < deadline: await process_frame
	check(not client.busy, "HTTP 请求在约定超时内结束")

func run() -> void:
	if OS.get_environment("HD2D_LEADERBOARD_LIVE_TEST") != "1":
		print("Live leaderboard test skipped; set HD2D_LEADERBOARD_LIVE_TEST=1 to opt in.")
		quit(0)
		return
	var client := root.get_node("LeaderboardClient")
	# Never let this destructive integration check adopt a saved player identity.
	if DisplayServer.get_name() != "headless" or client.save_enabled or not client.model.device_id.is_empty():
		push_error("Live leaderboard test requires headless mode and an empty, unsaved identity.")
		quit(1)
		return
	client.network_enabled = true
	client.save_enabled = false
	client.set_upload_consent(true, true)
	var test_identity: String = client.model.device_id
	client.model.nickname = "连接验证（临时）"
	client.refresh_scores()
	await idle(client)
	check(client.status.contains("已更新"), "Godot 原生 HTTPRequest 通过可信 CA 校验读取线上排行榜")
	client.begin_run()
	client.capture_run({"total": 17, "active": false, "simulation": false,
		"eligible_for_submission": true, "rules_version": "integration-test"})
	await idle(client)
	check(client.model.submitted and int(client.personal.get("score", -1)) == 17, "真实 HTTPS 匿名提交、回执与个人排名读取贯通")
	var count: int = client.total
	client._send("submit", "/v1/demo/scores", client.model.frozen_body)
	await idle(client)
	check(client.total == count and client.model.submitted, "同 UUID 重试不增加榜单条目")
	if client.model.device_id != test_identity or client.save_enabled:
		push_error("Refusing to delete an identity outside this integration test.")
		quit(1)
		return
	client.request_deletion()
	await idle(client)
	check(client.model.device_id.is_empty() and not client.model.deletion_pending, "线上删除确认后清除临时测试身份与成绩")
	print("Live leaderboard: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
