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

func finish(client: Node, score := 120) -> void:
	client.begin_run()
	client.capture_run({"total": score, "active": false, "simulation": false, "eligible_for_submission": true})

func run() -> void:
	var Model = load("res://scripts/network/leaderboard_state.gd")
	var state = Model.new()
	if not state.has_method("upload_authorized"):
		check(false, "排行榜必须具有默认拒绝、版本化且可撤回的授权状态")
		print("Leaderboard privacy: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	var snapshot := {"total": 120, "active": false, "simulation": false, "eligible_for_submission": true}
	check(not state.upload_authorized() and state.device_id.is_empty(), "默认不授权，也不提前生成身份")
	state.begin_run()
	check(not state.capture(snapshot) and not state.can_submit(), "未授权结算不收集待传成绩")
	check(not state.grant_consent(true, false) and not state.upload_authorized(), "上传和公开必须分别作出肯定选择")
	check(state.grant_consent(true, true) and state.upload_authorized(), "双重明确选择后才启用")
	state.begin_run()
	check(state.capture(snapshot), "授权后保留有效结算")
	var body: Dictionary = state.submission_body()
	check(body.get("privacy_version") == "2026-10-21" and body.get("public_consent") == true, "提交携带对应政策与公开同意声明")
	var identity: String = state.device_id
	var path := "D:/.codexfile/work/huitan-privacy-20261021/consent-state.cfg"
	check(state.save_to(path) == OK, "授权及队列可持久化")
	var restored = Model.new()
	check(restored.load_from(path) == OK and restored.upload_authorized() and restored.submission_body() == body, "重启恢复相同授权与幂等请求")
	restored.withdraw_consent()
	check(not restored.upload_authorized() and restored.pending.is_empty() and restored.outbox.is_empty(), "撤回清除全部待传数据")
	check(restored.device_id == identity, "撤回保留凭据供本人删除既有远端数据")
	check(not restored.capture(snapshot), "撤回后不继续生成提交")
	# Previous clients had identities and queued runs, but no recorded consent.
	var legacy := ConfigFile.new()
	legacy.set_value("demo", "device_id", identity)
	legacy.set_value("demo", "device_token", state.device_token)
	legacy.set_value("demo", "pending", state.pending)
	legacy.set_value("demo", "outbox", [body])
	legacy.save(path)
	var migrated = Model.new()
	check(migrated.load_from(path) == OK and migrated.device_id == identity, "旧版身份保留，不擅自破坏已提交记录的归属")
	check(not migrated.upload_authorized() and not migrated.can_submit() and migrated.pending.is_empty(), "旧版无授权队列不能在升级后补交")
	legacy.set_value("demo", "upload_consent_version", "old-policy")
	legacy.set_value("demo", "public_consent_version", "old-policy")
	legacy.save(path)
	check(migrated.load_from(path) == OK and not migrated.upload_authorized(), "政策版本变化后重新授权")
	var client := RecordingClient.new()
	root.add_child(client)
	await process_frame
	client.network_enabled = true # Recording transport only; never contacts production.
	finish(client)
	client.refresh_scores()
	check(client.requests.is_empty(), "首次启动及未选择查看时不请求任何排行榜接口")
	client.allow_reading()
	check(client.requests.size() == 1 and client.requests[0].operation == "scores", "主动选择只查看允许公开查询")
	client.busy = false
	finish(client)
	check(not client.model.can_submit(), "只查看不生成上传队列")
	client.set_upload_consent(true, true)
	finish(client)
	check(client.requests[-1].operation == "submit", "授权后自动提交，无需手动提交成绩")
	var submitted: Dictionary = client.requests[-1].body
	var generation: int = client.get("_request_generation")
	client.withdraw_consent()
	client.call("_completed", HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify({"submission_id": submitted.submission_id}).to_utf8_buffer(), generation)
	check(not client.busy and not client.model.can_submit() and client._retry_timer.is_stopped(), "撤回取消重试，并忽略迟到的上传回执")
	client.refresh_scores()
	check(client.entries.is_empty() and client._operation.is_empty(), "撤回后不继续查询或恢复公开数据")
	client.request_deletion()
	check(client.requests[-1].operation == "delete" and not client.model.upload_authorized(), "删除请求独立于上传同意，撤回后仍可删除")
	client._completed(HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray())
	check(client.model.deletion_pending and not client._retry_timer.is_stopped(), "删除失败持久等待并退避重试")
	check(client.model.save_to(path) == OK, "删除请求可以保存用于重启补办")
	var deletion_recovered := RecordingClient.new()
	root.add_child(deletion_recovered)
	await process_frame
	deletion_recovered.model.load_from(path)
	deletion_recovered.network_enabled = true
	deletion_recovered._try_submit()
	check(deletion_recovered.requests.size() == 1 and deletion_recovered.requests[0].operation == "delete", "重启仅恢复本人发起的删除，不恢复上传同意")
	deletion_recovered.free()
	check(not client.set_upload_consent(true, true), "删除未完成时不能重新授权并竞争上传")
	client._retry_timer.stop()
	client._try_submit()
	check(client.requests[-1].operation == "delete", "重试仅发送删除，不复活旧成绩")
	var previous_identity: String = client.model.device_id
	client._completed(HTTPRequest.RESULT_SUCCESS, 204, PackedStringArray(), PackedByteArray())
	check(not client.model.deletion_pending and client.model.device_id.is_empty() and client.model.device_token.is_empty(), "删除确认后清除本地身份与凭据")
	check(client.set_upload_consent(true, true) and client.model.device_id != previous_identity, "再次主动参与使用新身份")
	client.free()
	var broken := RecordingClient.new()
	root.add_child(broken)
	await process_frame
	broken.model = UnwritableState.new()
	broken.save_enabled = true
	broken.network_enabled = true
	check(not broken.set_upload_consent(true, true) and not broken.model.upload_authorized(), "授权无法保存时不启用上传")
	finish(broken)
	check(broken.requests.is_empty(), "持久化失败不会发送成绩或读取个人记录")
	broken.free()
	print("Leaderboard privacy: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
