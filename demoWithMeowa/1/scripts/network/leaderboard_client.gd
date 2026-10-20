extends Node

signal changed

const Model = preload("res://scripts/network/leaderboard_state.gd")
const PREFERENCES := "user://leaderboard.cfg"
var configuration = preload("res://data/network/leaderboard.tres").duplicate()
var model = Model.new()
var network_enabled := false
var save_enabled := false
var busy := false
var status := "匿名试玩榜 · 客户端上报成绩"
var entries: Array = []
var total := 0
var offset := 0
var personal: Dictionary = {}
var _http: HTTPRequest
var _operation := ""
var _tls_ready := false
var _retry_timer: Timer
var _retry_seconds := 2.0

func _ready() -> void:
	save_enabled = DisplayServer.get_name() != "headless"
	network_enabled = save_enabled
	if save_enabled:
		var server := ConfigFile.new()
		if server.load("user://leaderboard_server.cfg") == OK:
			var endpoint: Variant = server.get_value("connection", "endpoint", "")
			if endpoint is String and endpoint.begins_with("https://"): configuration.endpoint = endpoint.strip_edges()
	if save_enabled: model.load_from(PREFERENCES)
	model.create_identity()
	_save()
	_http = HTTPRequest.new()
	_http.timeout = configuration.timeout_seconds
	_http.body_size_limit = 1048576
	_http.max_redirects = 0 # Device credentials are never forwarded to another origin.
	_http.use_threads = true
	add_child(_http)
	var ca := X509Certificate.new()
	if ca.load_from_string(configuration.trusted_ca_pem) == OK:
		_http.set_tls_options(TLSOptions.client(ca, configuration.certificate_name))
		_tls_ready = true
	_http.request_completed.connect(_completed)
	_retry_timer = Timer.new()
	_retry_timer.one_shot = true
	_retry_timer.ignore_time_scale = true
	_retry_timer.timeout.connect(_try_submit)
	add_child(_retry_timer)
	_try_submit.call_deferred()

func _save() -> bool:
	if save_enabled and model.save_to(PREFERENCES) != OK:
		status = "本机成绩保存失败，请检查存储空间。"
		return false
	return true

func begin_run() -> void:
	model.begin_run()

func capture_run(snapshot: Dictionary) -> void:
	if not model.capture(snapshot): return
	_retry_seconds = 2.0
	_retry_timer.stop()
	if _save(): _try_submit()
	changed.emit()

func _try_submit() -> void:
	if network_enabled and not busy and model.can_submit() and _retry_timer.is_stopped(): submit_pending()

func _schedule_retry() -> void:
	if not network_enabled or not model.can_submit(): return
	_retry_timer.start(_retry_seconds)
	_retry_seconds = minf(_retry_seconds * 2.0, 60.0)

func set_nickname(value: String) -> void:
	model.nickname = value.strip_edges().left(48)
	_save()

func refresh_scores(page_offset := 0) -> void:
	if busy: return
	offset = clampi(page_offset, 0, 10000)
	_send("scores", "/v1/leaderboards/%s/scores?limit=20&offset=%d" % [configuration.board_id, offset])

func submit_pending() -> void:
	if busy or not model.can_submit(): return
	var body: Dictionary = model.submission_body()
	# Persist before transmission: timeout/restart retries use exactly the same body.
	if not _save():
		changed.emit()
		return
	_send("submit", "/v1/demo/scores", body)

func _send(operation: String, path: String, body: Dictionary = {}) -> void:
	if not network_enabled:
		status = "网络访问未启用。"
		changed.emit()
		return
	if not _tls_ready or not configuration.endpoint.begins_with("https://"):
		status = "排行榜加密连接配置无效。"
		changed.emit()
		return
	_operation = operation
	busy = true
	status = "正在自动提交成绩…" if operation == "submit" else "正在读取排行榜…"
	changed.emit()
	var headers := PackedStringArray(["Accept: application/json"])
	var method := HTTPClient.METHOD_GET
	if operation == "submit":
		method = HTTPClient.METHOD_POST
		headers.append("Content-Type: application/json")
		headers.append("Authorization: Bearer " + model.device_token)
	var result := _http.request(configuration.endpoint.trim_suffix("/") + path, headers, method,
		JSON.stringify(body) if operation == "submit" else "")
	if result != OK:
		busy = false
		status = "暂时无法连接；成绩已保留，将自动重试。"
		_schedule_retry()
		changed.emit()

func _completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	var parser := JSON.new()
	var data: Variant = null
	if parser.parse(body.get_string_from_utf8()) == OK: data = parser.data
	if result != HTTPRequest.RESULT_SUCCESS:
		status = "连接失败或超时；成绩已保留，将自动重试。"
		_schedule_retry()
	elif _operation == "personal" and code == 404:
		personal.clear()
		status = "排行榜已更新，完成挑战后将自动记录成绩。"
	elif code != 200 or not data is Dictionary:
		status = "请求失败（HTTP %d），可稍后重试。" % code
		if code == 401: status = "本机身份凭证不匹配，无法覆盖该玩家的成绩。"
		if code == 429: status = "操作较频繁，请稍后重试。"
		if code == 429 or code >= 500 or code == 200: _schedule_retry()
	elif _operation == "submit":
		if not model.confirm(data):
			status = "提交回执不匹配，待提交成绩已保留。"
			_schedule_retry()
		else:
			_retry_timer.stop()
			_retry_seconds = 2.0
			if not _save():
				changed.emit()
				return
			if model.can_submit(): _try_submit()
			else: refresh_scores()
			return
	elif _operation == "scores":
		if not data.get("entries") is Array:
			status = "排行榜响应格式不正确。"
		else:
			entries = data.entries
			total = int(data.get("total", 0))
			_send("personal", "/v1/leaderboards/%s/players/demo:%s" % [configuration.board_id, model.device_id])
			return
	elif _operation == "personal":
		personal = data
		status = "排行榜已更新。"
	changed.emit()
	# A run can finish while a read request owns the single HTTP connection.
	if _operation != "submit": _try_submit()
