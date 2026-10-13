class_name WavePrototypeUI
extends CanvasLayer

var controller: Node3D
var _root: Control
var _status: Label
var _status_panel: PanelContainer
var _modal: PanelContainer
var _title: Label
var _description: Label
var _shade: ColorRect
var _rest_actions: HBoxContainer

func _ready() -> void:
	layer = 22
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "SimSun"])
	theme.default_font = font
	theme.default_font_size = 20
	_root.theme = theme
	add_child(_root)
	_status_panel = PanelContainer.new()
	_status_panel.add_theme_stylebox_override("panel", _panel())
	_root.add_child(_status_panel)
	var status_content := VBoxContainer.new()
	_status_panel.add_child(status_content)
	_status = _label("", 20)
	status_content.add_child(_status)
	_rest_actions = HBoxContainer.new()
	_rest_actions.alignment = BoxContainer.ALIGNMENT_CENTER
	_rest_actions.add_theme_constant_override("separation", 12)
	status_content.add_child(_rest_actions)
	_rest_actions.add_child(_button("开始下一波 [F]", controller.start_next_wave))
	_rest_actions.add_child(_button("撤退并结算", controller.retreat))
	_shade = ColorRect.new()
	_shade.color = Color(0.04, 0.05, 0.07, 0.3)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_shade)
	_modal = PanelContainer.new()
	_modal.add_theme_stylebox_override("panel", _panel())
	_root.add_child(_modal)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	_modal.add_child(content)
	_title = _label("", 28)
	content.add_child(_title)
	_description = _label("", 20)
	content.add_child(_description)
	content.add_child(_button("重新开始", controller.retry))
	content.add_child(_button("结束挑战，返回小院 [ESC]", controller.return_home))
	_root.resized.connect(_fit)
	controller.changed.connect(refresh)
	refresh()

func _panel() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.15, 0.94)
	style.border_color = Color(0.55, 0.58, 0.62)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_border_width(side, 1)
		style.set_content_margin(side, 18)
	return style

func _label(words: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = words
	label.add_theme_font_size_override("font_size", font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(words: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = words
	button.custom_minimum_size.y = 56
	button.pressed.connect(action)
	return button

func _process(_delta: float) -> void:
	if controller:
		_status.text = controller.status_text()
		_status_panel.visible = not (controller.loadout and controller.loadout.menu_open)

func refresh() -> void:
	var result: bool = controller.phase == controller.Phase.RESULT
	_modal.visible = result
	_shade.visible = result
	_rest_actions.visible = controller.phase == controller.Phase.REST
	_title.text = controller.result_reason
	_description.text = "%s · 已完成 %d 波\n击败 %d 个敌人" % ["无尽挑战" if controller.is_endless() else "波次挑战", controller.completed_waves, controller.kills]
	_fit.call_deferred()

func _fit() -> void:
	if not _root: return
	var viewport := _root.size
	_status_panel.position = Vector2(maxf((viewport.x - 720.0) * 0.5, 12.0), 20.0)
	_status_panel.size.x = minf(720.0, viewport.x - 24.0)
	_status_panel.size.y = 0.0
	_modal.size = Vector2(minf(700.0, viewport.x - 32.0), 0.0)
	_modal.position = (viewport - _modal.get_combined_minimum_size()) * 0.5
