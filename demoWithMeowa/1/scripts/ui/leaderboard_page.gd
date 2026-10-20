extends VBoxContainer

var client: Node
var nickname: LineEdit
var status: Label
var mine: Label
var pending: Label
var _refresh: Button
var _previous: Button
var _next: Button
var _rows: VBoxContainer

func _ready() -> void:
	client = get_node("/root/LeaderboardClient")
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	var note := _label("试玩榜 · 成绩未经审核")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", Color("bdc4cc"))
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
	var header := _label("排名　　玩家　　　　　　　　　　最高分")
	header.add_theme_color_override("font_color", Color("fff0d4"))
	_rows = VBoxContainer.new()
	add_child(_rows)
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

func activate() -> void:
	if not is_node_ready(): return
	sync()
	if not client.busy: client.refresh_scores(client.offset)

func sync() -> void:
	if not is_node_ready(): return
	if not nickname.has_focus(): nickname.text = client.model.nickname
	status.text = client.status
	mine.text = "最好：暂无　排名：—" if client.personal.is_empty() else "最好：%d　排名：%d" % [int(client.personal.get("score", 0)), int(client.personal.get("rank", 0))]
	var state = client.model
	pending.text = "挑战结算后自动上传成绩"
	if not state.pending.is_empty():
		pending.text = "上局：%d · %s" % [state.pending.total, "已自动提交" if state.submitted else "等待自动上传"]
	_refresh.disabled = client.busy
	_previous.disabled = client.busy or client.offset <= 0
	_next.disabled = client.busy or client.offset + 20 >= client.total or client.offset >= 10000
	# Rows are rebuilt only when response/state changes, never in the frame loop.
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	for entry in client.entries:
		if not entry is Dictionary: continue
		var row := HBoxContainer.new()
		_rows.add_child(row)
		var display_name: Variant = entry.get("display_name")
		var texts := [str(int(entry.get("rank", 0))), display_name if display_name is String else "玩家", str(int(entry.get("score", 0)))]
		for text in texts:
			var cell := Label.new()
			cell.text = text
			cell.custom_minimum_size.x = 80
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			row.add_child(cell)
