extends Control
## Standalone leaderboard for the main menu.

signal closed

const Page = preload("res://scripts/ui/leaderboard_page.gd")
const PANEL_SIZE := Vector2(720, 660)

var page: VBoxContainer
var panel: PanelContainer
var _back: Button
var _previous_focus: WeakRef

func _ready() -> void:
	name = "LeaderboardWindow"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var window_theme := Theme.new()
	window_theme.default_font = preload("res://assets/fonts/maoken_assorted_sans/MaokenAssortedSans.ttf")
	window_theme.default_font_size = 22
	theme = window_theme
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.02, 0.035, 0.80)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = PanelContainer.new()
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color("101c2b")
	skin.border_color = Color("a98650")
	skin.set_border_width_all(1)
	skin.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", skin)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	panel.add_child(column)
	var heading := Label.new()
	heading.text = "排行榜"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 36)
	column.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	page = Page.new()
	scroll.add_child(page)
	_back = Button.new()
	_back.text = "返回"
	_back.custom_minimum_size.y = 48
	_back.pressed.connect(close)
	column.add_child(_back)
	panel.minimum_size_changed.connect(_fit, CONNECT_DEFERRED)
	get_viewport().size_changed.connect(_fit)
	_fit()
	hide()

func _fit() -> void:
	var viewport := get_viewport_rect().size
	var fit := maxf(0.1, minf(1.0, minf((viewport.x - 32) / PANEL_SIZE.x, (viewport.y - 32) / PANEL_SIZE.y)))
	panel.size = PANEL_SIZE
	panel.scale = Vector2.ONE * fit
	panel.position = (viewport - PANEL_SIZE * fit) * 0.5

func open() -> bool:
	if visible: return false
	var focus := get_viewport().gui_get_focus_owner()
	_previous_focus = weakref(focus) if focus else null
	show()
	page.activate()
	_back.grab_focus()
	return true

func close() -> void:
	if not visible: return
	hide()
	var focus: Control = _previous_focus.get_ref() if _previous_focus else null
	if is_instance_valid(focus) and focus.is_visible_in_tree(): focus.grab_focus()
	closed.emit()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		close()
		get_viewport().set_input_as_handled()

func _unhandled_input(_event: InputEvent) -> void:
	if is_visible_in_tree(): get_viewport().set_input_as_handled()

func _unhandled_key_input(_event: InputEvent) -> void:
	if is_visible_in_tree(): get_viewport().set_input_as_handled()
