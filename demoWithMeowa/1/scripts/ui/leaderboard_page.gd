extends VBoxContainer

const PrivacyDialog = preload("res://scripts/ui/privacy_policy_dialog.gd")
var client: Node
var nickname: LineEdit
var status: Label
var mine: Label
var pending: Label
var _refresh: Button
var _previous: Button
var _next: Button
var _rows: GridContainer
var _upload_choice: CheckBox
var _publish_choice: CheckBox
var _enable: Button
var _withdraw: Button
var _delete: Button
var _read: Button
var _delete_confirmation: ConfirmationDialog
var _privacy_dialog: AcceptDialog
var _was_authorized := false

func _ready() -> void:
	client = get_node("/root/LeaderboardClient")
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	var note := _label("试玩榜 · 成绩未经审核")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color("bdc4cc"))
	var explanation := _label("联网会处理必要的 IP 连接信息。启用后，随机玩家标识、昵称、成绩、达成时间及击杀／波次摘要将上传至北京服务器并用于公开榜单，同一身份已有的最好成绩也会展示；不参与不影响本地游玩。")
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_privacy_dialog = PrivacyDialog.new()
	add_child(_privacy_dialog)
	var privacy_actions := HBoxContainer.new()
	add_child(privacy_actions)
	_button(privacy_actions, "隐私政策", func(): _privacy_dialog.popup_centered(Vector2i(760, 580)))
	_read = _button(privacy_actions, "只查看排行榜", client.allow_reading)
	_upload_choice = CheckBox.new()
	_upload_choice.text = "允许上传排行榜成绩"
	add_child(_upload_choice)
	_publish_choice = CheckBox.new()
	_publish_choice.text = "同意向其他玩家公开上述榜单信息"
	add_child(_publish_choice)
	_upload_choice.toggled.connect(func(_value: bool): sync())
	_publish_choice.toggled.connect(func(_value: bool): sync())
	var consent_actions := HBoxContainer.new()
	add_child(consent_actions)
	_enable = _button(consent_actions, "启用自动上传", func():
		if client.set_upload_consent(_upload_choice.button_pressed, _publish_choice.button_pressed): client.refresh_scores())
	_withdraw = _button(consent_actions, "停止自动上传", func():
		client.withdraw_consent()
		_upload_choice.set_pressed_no_signal(false)
		_publish_choice.set_pressed_no_signal(false)
		sync())
	_delete_confirmation = ConfirmationDialog.new()
	_delete_confirmation.title = "删除排行榜数据"
	_delete_confirmation.dialog_text = "停止上传，并删除本机身份对应的服务器成绩、回执、授权与身份。\n游戏存档和设置保留；删除后无法找回原排行榜身份。\n服务器仅保留防止旧请求恢复记录的凭据撤销摘要。"
	_delete_confirmation.ok_button_text = "确认删除"
	_delete_confirmation.cancel_button_text = "取消"
	_delete_confirmation.exclusive = true
	_delete_confirmation.confirmed.connect(client.request_deletion)
	add_child(_delete_confirmation)
	_delete = _button(consent_actions, "撤回并删除数据", func(): _delete_confirmation.popup_centered())
	var row := HBoxContainer.new()
	add_child(row)
	var caption := Label.new()
	caption.text = "昵称"
	row.add_child(caption)
	nickname = LineEdit.new()
	nickname.text = client.model.nickname
	nickname.max_length = 48
	nickname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nickname)
	nickname.text_changed.connect(client.set_nickname)
	_refresh = _button(row, "刷新", func(): client.refresh_scores(client.offset))
	mine = _label("")
	pending = _label("")
	pending.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status = _label("")
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows = GridContainer.new()
	_rows.columns = 3
	_rows.add_theme_constant_override("h_separation", 18)
	_rows.add_theme_constant_override("v_separation", 8)
	add_child(_rows)
	for column in 3:
		var header := _cell(["排名", "玩家", "最高分"][column], column)
		header.add_theme_color_override("font_color", Color("fff0d4"))
	var paging := HBoxContainer.new()
	add_child(paging)
	_previous = _button(paging, "上一页", func(): client.refresh_scores(client.offset - 20))
	_next = _button(paging, "下一页", func(): client.refresh_scores(client.offset + 20))
	client.changed.connect(sync)
	sync()

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 38
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _cell(text: String, column: int) -> Label:
	var cell := Label.new()
	cell.text = text
	match column:
		0:
			cell.custom_minimum_size.x = 64
		1:
			cell.custom_minimum_size.x = 80
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.clip_text = true
			cell.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		2:
			cell.custom_minimum_size.x = 128
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_rows.add_child(cell)
	return cell

func activate() -> void:
	if not is_node_ready(): return
	sync()
	if not client.busy: client.refresh_scores(client.offset)

func sync() -> void:
	if not is_node_ready(): return
	var authorized: bool = client.model.upload_authorized()
	if authorized or _was_authorized or client.model.deletion_pending:
		_upload_choice.set_pressed_no_signal(authorized)
		_publish_choice.set_pressed_no_signal(authorized)
	_was_authorized = authorized
	_enable.disabled = client.busy or authorized or client.model.deletion_pending or not (_upload_choice.button_pressed and _publish_choice.button_pressed)
	_withdraw.disabled = client.model.deletion_pending or not (authorized or client.read_allowed)
	_delete.disabled = client.busy or client.model.device_id.is_empty()
	_delete.text = "重试删除" if client.model.deletion_pending else "撤回并删除数据"
	_read.disabled = client.busy or client.model.deletion_pending
	nickname.editable = authorized and not client.busy
	if not nickname.has_focus(): nickname.text = client.model.nickname
	status.text = client.status
	mine.text = "最好：暂无　排名：—" if client.personal.is_empty() else "最好：%d　排名：%d" % [int(client.personal.get("score", 0)), int(client.personal.get("rank", 0))]
	var state = client.model
	pending.text = "授权后，挑战结算自动上传成绩" if authorized else "未授权，不会自动上传成绩。"
	if client.model.deletion_pending: pending.text = "删除请求已保存在本机，联网后会继续处理。"
	if not state.pending.is_empty():
		pending.text = "上局：%d · %s" % [state.pending.total, "已自动提交" if state.submitted else "等待自动上传"]
	_refresh.disabled = client.busy or not client.read_allowed
	_previous.disabled = client.busy or not client.read_allowed or client.offset <= 0
	_next.disabled = client.busy or not client.read_allowed or client.offset + 20 >= client.total or client.offset >= 10000
	# Rows are rebuilt only when response/state changes, never in the frame loop.
	for child in _rows.get_children().slice(3):
		_rows.remove_child(child)
		child.queue_free()
	for entry in client.entries:
		if not entry is Dictionary: continue
		var display_name: Variant = entry.get("display_name")
		var texts := [str(int(entry.get("rank", 0))), display_name if display_name is String else "玩家", str(int(entry.get("score", 0)))]
		for column in 3:
			_cell(texts[column], column)
