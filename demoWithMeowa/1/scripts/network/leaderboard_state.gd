extends RefCounted
## Local anonymous credentials and frozen, retryable run submissions.

var device_id := ""
var device_token := ""
var nickname := ""
var pending: Dictionary = {}
var frozen_body: Dictionary = {}
var submitted := false
var outbox: Array[Dictionary] = []
var _run_ticket := ""

static func uuid() -> String:
	var bytes := Crypto.new().generate_random_bytes(16)
	bytes[6] = (bytes[6] & 15) | 64
	bytes[8] = (bytes[8] & 63) | 128
	var hex := bytes.hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20)]

func create_identity() -> void:
	if device_id.length() == 36 and device_token.length() == 64: return
	device_id = uuid()
	device_token = Crypto.new().generate_random_bytes(32).hex_encode()
	nickname = "玩家-%s" % device_id.left(4)

func begin_run() -> void:
	_run_ticket = uuid()

func capture(snapshot: Dictionary) -> bool:
	if snapshot.get("active", true) or snapshot.get("simulation", true) or not snapshot.get("eligible_for_submission", false): return false
	var score: Variant = snapshot.get("total")
	if not score is int or score < 0 or score > 9007199254740991: return false
	if _run_ticket.is_empty(): _run_ticket = uuid()
	if pending.get("submission_id") == _run_ticket: return false
	create_identity()
	if not pending.is_empty() and not submitted:
		outbox.append(_freeze_pending())
	pending = snapshot.duplicate(true)
	pending.submission_id = _run_ticket
	frozen_body.clear()
	submitted = false
	return true

func can_submit() -> bool:
	return not outbox.is_empty() or (not pending.is_empty() and not submitted)

func submission_body() -> Dictionary:
	if not can_submit(): return {}
	if not outbox.is_empty(): return outbox[0].duplicate(true)
	return _freeze_pending()

func _freeze_pending() -> Dictionary:
	if frozen_body.is_empty():
		var display_name := nickname.strip_edges().left(48)
		if display_name.is_empty(): display_name = "玩家-%s" % device_id.left(4)
		frozen_body = {"submission_id": pending.submission_id, "device_id": device_id,
			"score": pending.total, "display_name": display_name,
			"metadata": {"rules_version": pending.get("rules_version", ""),
				"kills": pending.get("kills", 0), "completed_waves": pending.get("completed_waves", 0),
				"kill_score": pending.get("kill_score", 0), "wave_score": pending.get("wave_score", 0),
				"performance_score": pending.get("performance_score", 0),
				"combo_score": pending.get("combo_score", 0), "burst_score": pending.get("burst_score", 0),
				"eligible_kills": pending.get("eligible_kills", 0),
				"peak_multiplier_milli": pending.get("peak_multiplier_milli", 1000)}}
	return frozen_body.duplicate(true)

func confirm(receipt: Dictionary) -> bool:
	if not outbox.is_empty():
		if receipt.get("submission_id") != outbox[0].submission_id: return false
		outbox.pop_front()
		return true
	if pending.is_empty() or receipt.get("submission_id") != pending.submission_id: return false
	submitted = true
	return true

func save_to(path: String) -> Error:
	var config := ConfigFile.new()
	for property in ["device_id", "device_token", "nickname", "pending", "frozen_body", "submitted", "outbox"]:
		config.set_value("demo", property, get(property))
	return config.save(path)

func load_from(path: String) -> Error:
	var config := ConfigFile.new()
	var result := config.load(path)
	if result != OK: return result
	var identity: Variant = config.get_value("demo", "device_id", "")
	var token: Variant = config.get_value("demo", "device_token", "")
	if not identity is String or identity.length() != 36 or not token is String or token.length() != 64: return ERR_INVALID_DATA
	device_id = identity
	device_token = token
	var name_value: Variant = config.get_value("demo", "nickname", "玩家")
	nickname = name_value.left(48) if name_value is String else "玩家"
	var saved: Variant = config.get_value("demo", "pending", {})
	if saved is Dictionary and saved.get("total") is int and saved.get("submission_id") is String:
		pending = saved
	var body: Variant = config.get_value("demo", "frozen_body", {})
	if body is Dictionary and body.get("device_id") == device_id and body.get("submission_id") == pending.get("submission_id"):
		frozen_body = body
	submitted = config.get_value("demo", "submitted", false) == true
	var queued: Variant = config.get_value("demo", "outbox", [])
	outbox.clear()
	if queued is Array:
		for item in queued:
			if item is Dictionary and item.get("device_id") == device_id and item.get("submission_id") is String and item.get("score") is int:
				outbox.append(item)
	return OK
