extends SceneTree

var checks := 0
var failures := 0

class RecordingClient:
	extends "res://scripts/network/leaderboard_client.gd"
	var requests: Array[Dictionary] = []
	func _send(operation: String, path: String, body: Dictionary = {}) -> void:
		_operation = operation
		busy = true
		requests.append({"operation": operation, "path": path, "body": body.duplicate(true)})

class UnwritableState:
	extends "res://scripts/network/leaderboard_state.gd"
	func save_to(_path: String) -> Error: return ERR_CANT_CREATE

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)

func _initialize() -> void:
	run.call_deferred()

func finish(client: Node, score: int) -> void:
	client.begin_run()
	client.capture_run({"total": score, "active": false, "simulation": false, "eligible_for_submission": true})

func reply(client: Node, data: Dictionary, code := 200) -> void:
	client._completed(HTTPRequest.RESULT_SUCCESS, code, PackedStringArray(), JSON.stringify(data).to_utf8_buffer())

func run() -> void:
	var client := RecordingClient.new()
	root.add_child(client)
	await process_frame
	client.network_enabled = true # Recording transport never opens a connection.
	for invalid in [{"active": true}, {"simulation": true}, {"eligible_for_submission": false}]:
		client.capture_run({"total": 1, "active": false, "simulation": false, "eligible_for_submission": true}.merged(invalid, true))
	check(client.requests.is_empty(), "战斗中、模拟及异常结束不触发自动提交")
	finish(client, 120)
	check(client.requests.size() == 1 and client.requests[0].operation == "submit", "有效结算立即自动提交，无需打开 UI")
	if client.requests.is_empty():
		client.free()
		print("Leaderboard auto-submit: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	var first: Dictionary = client.requests[0].body
	client.capture_run({"total": 120, "active": false, "simulation": false, "eligible_for_submission": true})
	check(client.requests.size() == 1, "重复结算通知不重复并发提交")
	finish(client, 240)
	check(client.requests.size() == 1, "提交未结束时保留后续结算，不并发请求")
	reply(client, {"submission_id": first.submission_id})
	check(client.requests.size() == 2 and client.requests[1].body.get("score") == 240, "旧回执到达后继续提交下一局，不丢失结算")
	var second: Dictionary = client.requests[1].body
	client._completed(HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray())
	check(not client.busy and client.model.can_submit() and not client._retry_timer.is_stopped(), "超时保留成绩并安排后台退避重试")
	client.set_nickname("新的昵称")
	client._retry_timer.stop()
	client._try_submit()
	check(client.requests[-1].body == second, "自动重试复用完整原请求，改名不破坏幂等")
	reply(client, {}, 503)
	check(not client._retry_timer.is_stopped() and client._retry_timer.wait_time == 4.0, "服务器暂不可用时逐步延长重试间隔")
	client._retry_timer.stop()
	client._try_submit()
	reply(client, {"submission_id": second.submission_id})
	check(client.model.submitted and client.requests[-1].operation == "scores", "自动提交成功后更新榜单")
	reply(client, {"entries": [], "total": 0})
	reply(client, {}, 404)
	check(not client.busy and not client.model.can_submit() and client._retry_timer.is_stopped(), "成功后停止重试，不反复提交")
	client.refresh_scores()
	finish(client, 360)
	reply(client, {"entries": [], "total": 0})
	if client.requests[-1].operation == "personal": reply(client, {}, 404)
	check(client.requests[-1].operation == "submit" and client.requests[-1].body.score == 360, "查询占用连接时，结算排队并在查询结束后自动上传")
	reply(client, {}, 401)
	check(client._retry_timer.is_stopped() and client.model.can_submit(), "身份错误保留成绩且不循环轰炸服务器")
	client.free()
	var broken := RecordingClient.new()
	root.add_child(broken)
	await process_frame
	broken.model = UnwritableState.new()
	broken.network_enabled = true
	broken.save_enabled = true
	finish(broken, 12)
	check(broken.requests.is_empty() and broken.status.contains("保存失败"), "本机持久化失败时不发送自动提交")
	broken.free()
	var offline := RecordingClient.new()
	root.add_child(offline)
	await process_frame
	finish(offline, 500)
	finish(offline, 100)
	var path := "D:/.codexfile/work/leaderboard-flow-20261020/queued.cfg"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	check(offline.model.save_to(path) == OK and offline.requests.is_empty(), "无网络时多局成绩留在本机，无界面默认不联网")
	var restored := RecordingClient.new()
	root.add_child(restored)
	await process_frame
	check(restored.model.load_from(path) == OK, "待上传队列可以恢复")
	restored.network_enabled = true
	restored._try_submit()
	check(restored.requests[0].body.score == 500, "重启先上传断网期间的高分，不被后续低分覆盖")
	reply(restored, {"submission_id": restored.requests[0].body.submission_id})
	check(restored.requests[1].body.score == 100, "重启依次自动补交后续结算")
	offline.free()
	restored.free()
	print("Leaderboard auto-submit: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
