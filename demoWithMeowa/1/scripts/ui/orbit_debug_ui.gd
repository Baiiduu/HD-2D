extends CanvasLayer

## 非阻塞的实机诊断。仅读取实际规划和运动，不调用预览、寻路或攻击接口。
@export var player: Player
@export var session: WavePrototype
@export var loadout: LoadoutUI

const TRAIL := Color("e4dcfa")
const PLAN := Color("ffd263")
const OUTLINE := Color("4cdde3")
const MEMBER := Color("82d68d")
const SWORD := Color("ed9780")
const STORM := Color("a89aff")
const END_REASONS := {&"speed_depleted": "余速耗尽", &"cancelled": "移动接管／取消弹射",
	&"ground_edge": "水面／断层／场地边缘", &"blocked_surface": "不可反弹表面",
	&"blocked_contact": "连续无位移接触", &"ground_contact": "贴地接触无位移"}
const MAX_SEGMENTS := 2048

class Overlay extends Control:
	var owner_ui: CanvasLayer
	func _draw() -> void: owner_ui.draw_world(self)

var debug_enabled := false
var locked := false
var snapshot: Dictionary = {}
var trail := PackedVector3Array()
var _body: PlayerRicochet
var _storm: RicochetStorm
var _overlay: Overlay
var _launcher: Button
var _details_button: Button
var _panel: PanelContainer
var _drag_handle: Label
var _details_visible := false
var _panel_moved := false
var _dragging := false
var _status: Label
var _events: Label
var _lock: CheckBox
var _show_members := true
var _show_path := true
var _show_ranges := true
var _end_reason := ""
var _distance := 0.0
var _elapsed := 0.0

func _ready() -> void:
	layer = 24
	if not player or not session: return
	_body = player.body_ricochet
	_storm = session.get_node_or_null("RicochetStorm") as RicochetStorm
	_overlay = Overlay.new()
	_overlay.owner_ui = self
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_overlay)
	_build_ui()
	_body.launched.connect(_launched)
	_body.state_changed.connect(_state_changed)
	_body.flight_segment_travelled.connect(_travelled)
	_body.finished.connect(_finished)
	session.phase_changed.connect(_phase_changed)
	get_viewport().size_changed.connect(_fit)
	_fit()
	set_debug_enabled(false)

func _button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	button.pressed.connect(callback)
	return button

func _check(text: String, initial: bool, callback: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = initial
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(callback)
	return check

func _build_ui() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	var theme := Theme.new()
	theme.default_font = loadout._theme.default_font if loadout and loadout._theme else font
	theme.default_font_size = 16
	_launcher = _button("环绕调试", func(): set_debug_enabled(not debug_enabled))
	_launcher.theme = theme
	add_child(_launcher)
	_details_button = _button("读数", func(): set_details_visible(not _details_visible))
	_details_button.theme = theme
	_details_button.tooltip_text = "展开诊断读数；收起不影响线路与记录。"
	add_child(_details_button)
	_panel = PanelContainer.new()
	_panel.theme = theme
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color(0.035, 0.055, 0.085, 0.92)
	skin.set_content_margin_all(13)
	skin.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", skin)
	add_child(_panel)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 5)
	_panel.add_child(content)
	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(header)
	_drag_handle = Label.new()
	_drag_handle.text = "环绕诊断 · 拖动移动"
	_drag_handle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	_drag_handle.mouse_default_cursor_shape = Control.CURSOR_DRAG
	_drag_handle.gui_input.connect(_drag_input)
	header.add_child(_drag_handle)
	header.add_child(_button("收起", func(): set_details_visible(false)))
	_lock = _check("锁定记录（世界继续运行）", false, func(value):
		locked = value
		if not locked: clear_record())
	content.add_child(_lock)
	content.add_child(_check("轮廓与群成员", true, func(value): _show_members = value))
	content.add_child(_check("规划路线与真实轨迹", true, func(value): _show_path = value))
	var ranges := _check("接触、剑术与奔雷范围", true, func(value): _show_ranges = value)
	ranges.tooltip_text = "范围圈表示水平距离；实际命中仍受剑向、动作时机、高差、挡墙及技能预算限制。"
	content.add_child(ranges)
	_status = Label.new()
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.x = 332
	content.add_child(_status)
	var legend := Label.new()
	legend.text = "青：规划时外沿　绿：成员／支点\n黄：当前待走路线　浅白：真实轨迹\n橙：剑术距离　紫：奔雷切入距离\n灰圈：普通接触　青虚圈：提前捕获\n诊断线穿透遮挡，仅显示已规划的一段。"
	legend.add_theme_font_size_override("font_size", 14)
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(legend)
	_events = Label.new()
	_events.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_events.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_events.add_theme_font_size_override("font_size", 14)
	content.add_child(_events)
	content.add_child(_button("清空记录", clear_record))

func _fit() -> void:
	var size := get_viewport().get_visible_rect().size
	_launcher.position = Vector2(maxf(8, size.x - 286), 22)
	_launcher.size = Vector2(126, 42)
	_details_button.position = Vector2(maxf(8, size.x - 352), 22)
	_details_button.size = Vector2(60, 42)
	_panel.size.x = 366
	_panel.position = _clamp_panel(_panel.position) if _panel_moved else Vector2(maxf(8, size.x - 382), 76)

func _clamp_panel(point: Vector2) -> Vector2:
	var size := get_viewport().get_visible_rect().size
	return Vector2(clampf(point.x, 8, maxf(8, size.x - _panel.size.x - 8)), clampf(point.y, 8, maxf(8, size.y - _panel.size.y - 8)))

func _drag_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_drag_handle.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_panel.position = _clamp_panel(_panel.position + event.relative)
		_panel_moved = true
		_drag_handle.accept_event()

func set_details_visible(value: bool) -> void:
	_details_visible = value and debug_enabled
	_panel.visible = _details_visible
	_details_button.text = "收起" if _details_visible else "读数"
	_dragging = false
	if _details_visible:
		_fit()
		_update_text()

func set_debug_enabled(value: bool) -> void:
	debug_enabled = value
	if not _body: return
	_body.orbit_debug_enabled = value
	if _body._crowd: _body._crowd.debug_enabled = value
	_details_button.visible = value
	set_details_visible(false)
	_overlay.visible = value
	_launcher.text = "关闭环绕调试" if value else "环绕调试"
	clear_record()
	if not value:
		_body.orbit_debug_last = {}
		if _body._crowd: _body._crowd.debug_events.clear()
	set_process(value)
	if value: _process(0.0)

func clear_record() -> void:
	locked = false
	if _lock: _lock.set_pressed_no_signal(false)
	trail.clear()
	snapshot = {}
	if _body: _body.orbit_debug_last = {}
	if _body and _body._crowd:
		_body._crowd.debug_events.clear()
		_body._crowd.debug_revision = 0
		_body._crowd.debug_replans = 0
		_body._crowd.debug_reason = "重新记录，沿用当前实际路线"
	_distance = 0.0
	_elapsed = 0.0
	_end_reason = ""
	if _overlay: _overlay.queue_redraw()

func _state_changed(state: PlayerRicochet.State) -> void:
	if debug_enabled and not locked and state == PlayerRicochet.State.CHARGING: clear_record()

func _launched(_heading: Vector3, _speed: float, _charge: float) -> void:
	if debug_enabled and not locked: clear_record()

func _phase_changed(_phase: int) -> void:
	locked = false
	_lock.set_pressed_no_signal(false)
	clear_record()
	_body.orbit_debug_last = {}

func _travelled(start: Vector3, end: Vector3, _heading: Vector3, seconds: float) -> void:
	if not debug_enabled or locked: return
	_distance += TerrainPath.horizontal_distance(start, end)
	_elapsed += seconds
	if trail.size() >= MAX_SEGMENTS * 2:
		trail = trail.slice(2)
	trail.append(start)
	trail.append(end)

func _finished(reason: StringName) -> void:
	if debug_enabled and not locked:
		_end_reason = END_REASONS.get(reason, String(reason))
		snapshot = _read_snapshot()

func _process(_delta: float) -> void:
	if not debug_enabled: return
	if not locked and (_body.flying or _body.charging or _end_reason.is_empty()): snapshot = _read_snapshot()
	if _details_visible: _update_text()
	_overlay.queue_redraw()

func _read_snapshot() -> Dictionary:
	var data := _body._crowd.debug_snapshot() if _body._crowd else _body.orbit_debug_last.duplicate()
	var settings: PlayerRicochetRules = _body._settings if _body._settings else player.ricochet_rules
	var phase := "蓄力" if _body.charging else ("持续环绕" if _body.orbiting else ("基础短弧" if _body._crowd and not _body._crowd._points.is_empty() else "直线飞行"))
	if not _body.flying and not _body.charging: phase = "待机／收势"
	data.merge({"position": player.global_position, "heading": _body.direction, "speed": _body.flight_speed,
		"phase": phase, "frozen": session.combat_frozen, "end": _end_reason, "distance": _distance, "seconds": _elapsed,
		"minimum_speed": settings.minimum_bounce_speed, "contact": settings.crowd_contact_radius,
		"capture": settings.crowd_contact_radius + (settings.eccentric_capture_margin if settings.eccentric_enabled else 0.0),
		"clearance": settings.eccentric_edge_clearance, "wall_count": _body.bounce_count, "crowd_count": _body.crowd_deflection_count}, true)
	data.sword = float(player.sword.get_stats(true).get("range", 0.0)) if player.sword and player.sword.enabled else 0.0
	var storm_stats: Dictionary = _storm._flight_stats if is_instance_valid(_storm) and not _storm._flight_stats.is_empty() else (_storm.get_attack_stats() if is_instance_valid(_storm) else {})
	data.storm = float(storm_stats.get("range", 0.0)) if is_instance_valid(_storm) and _storm.enabled and _storm.skill_level > 0 else 0.0
	return data

func _update_text() -> void:
	if snapshot.is_empty(): return
	var data := snapshot
	var nearest := INF
	for actor in data.get("members", []): nearest = minf(nearest, TerrainPath.horizontal_distance(data.position, actor.point))
	_status.text = "%s%s%s\n余速 %.2f / 下限 %.2f 米每秒\n记录路程 %.2f 米 · %.2f 秒\n成员 %d · 记录规划 %d · 群接触 %d · 墙反弹 %d\n最近成员 %s · 额外留白 %.2f 米\n剑术 %.2f 米 · 奔雷 %s\n同群锁 %d · 已忽略 %d\n当前：%s\n判群：%s" % [
		data.phase, " · 战斗冻结" if data.frozen else "", " · 记录锁定" if locked else "",
		data.speed, data.minimum_speed, data.distance, data.seconds, data.get("members", []).size(),
		data.get("replans", 0), data.crowd_count, data.wall_count, "%.2f 米" % nearest if is_finite(nearest) else "—",
		data.clearance, data.sword, "%.2f 米" % data.storm if data.storm > 0.0 else "未启用",
		data.get("locks", 0), data.get("ignored", 0), data.end if not data.end.is_empty() else data.get("reason", "等待接群"), data.get("capture_reason", "尚未判群")]
	_events.text = "最近判定\n" + "\n".join(data.get("events", []).slice(-4))

func _line(canvas: Control, camera: Camera3D, start: Vector3, end: Vector3, color: Color, width := 1.5) -> void:
	start.y += 0.07
	end.y += 0.07
	if camera.is_position_behind(start) or camera.is_position_behind(end): return
	canvas.draw_line(camera.unproject_position(start), camera.unproject_position(end), color, width, true)

func _circle(canvas: Control, camera: Camera3D, center: Vector3, radius: float, color: Color, dashed := false) -> void:
	for index in 48:
		if dashed and index % 2 == 1: continue
		var a := TAU * index / 48.0
		var b := TAU * (index + 1) / 48.0
		_line(canvas, camera, center + Vector3(cos(a), 0, sin(a)) * radius, center + Vector3(cos(b), 0, sin(b)) * radius, color)

func draw_world(canvas: Control) -> void:
	if snapshot.is_empty(): return
	var camera := player.movement_camera if is_instance_valid(player.movement_camera) else get_viewport().get_camera_3d()
	if not camera: return
	var point: Vector3 = snapshot.position
	if _show_path:
		for index in range(0, trail.size(), 2): _line(canvas, camera, trail[index], trail[index + 1], TRAIL * Color(1, 1, 1, 0.65))
		var previous := point
		for target in snapshot.get("planned", PackedVector3Array()):
			_line(canvas, camera, previous, target, PLAN, 2.5)
			previous = target
		var tip: Vector3 = point + snapshot.heading * 0.8
		_line(canvas, camera, point, tip, Color.WHITE, 2.5)
		var side: Vector3 = snapshot.heading.cross(Vector3.UP)
		_line(canvas, camera, tip, tip - snapshot.heading * 0.2 + side * 0.12, Color.WHITE, 2.5)
		_line(canvas, camera, tip, tip - snapshot.heading * 0.2 - side * 0.12, Color.WHITE, 2.5)
	if _show_members:
		var outline: PackedVector3Array = snapshot.get("outline", PackedVector3Array())
		for index in outline.size(): _line(canvas, camera, outline[index], outline[(index + 1) % outline.size()], OUTLINE, 2.0)
		for actor in snapshot.get("members", []):
			_circle(canvas, camera, actor.point, actor.radius, MEMBER)
			if actor.seed:
				_line(canvas, camera, actor.point - Vector3.RIGHT * 0.15, actor.point + Vector3.RIGHT * 0.15, PLAN, 3.0)
				_line(canvas, camera, actor.point - Vector3.FORWARD * 0.15, actor.point + Vector3.FORWARD * 0.15, PLAN, 3.0)
	if _show_ranges:
		_circle(canvas, camera, point, snapshot.contact, Color(0.8, 0.8, 0.8, 0.65), true)
		_circle(canvas, camera, point, snapshot.capture, OUTLINE * Color(1, 1, 1, 0.55), true)
		if snapshot.sword > 0.0: _circle(canvas, camera, point, snapshot.sword, SWORD * Color(1, 1, 1, 0.65))
		if snapshot.storm > 0.0: _circle(canvas, camera, point, snapshot.storm, STORM)

func _exit_tree() -> void:
	if is_instance_valid(_body):
		_body.orbit_debug_enabled = false
		if _body._crowd: _body._crowd.debug_enabled = false
