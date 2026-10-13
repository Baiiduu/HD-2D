@tool
class_name GrowthChoiceCard
extends Button

var option: GrowthChoiceOption
var selected := false
var hover_duration := 0.12
var selection_strength := 1.0
var _hovered := false
var _highlight: Tween

@onready var _frame: TextureRect = $Frame
@onready var _socket: TextureRect = $IconSlot
@onready var _icon: TextureRect = $IconSlot/Icon
@onready var _title: Label = $Title
@onready var _description: Label = $Description

func _ready() -> void:
	resized.connect(_layout)
	mouse_entered.connect(func(): _hovered = true; _update_highlight())
	mouse_exited.connect(func(): _hovered = false; _update_highlight())
	_layout()
	_update_highlight(false)

func configure(value: GrowthChoiceOption, opacity: float, strength: float, duration: float, font_size: int, text_color := Color(0.98, 0.91, 0.73)) -> void:
	option = value
	disabled = not value.enabled
	selection_strength = strength
	hover_duration = duration
	_title.text = value.title
	_description.text = value.description
	_title.visible = not value.title.is_empty()
	_description.visible = not value.description.is_empty()
	_icon.texture = value.icon
	_icon.visible = value.icon != null
	_title.add_theme_font_size_override("font_size", font_size + 4)
	_description.add_theme_font_size_override("font_size", font_size)
	for label in [_title, _description]:
		label.add_theme_color_override("font_color", text_color)
		label.add_theme_color_override("font_shadow_color", Color(0.05, 0.08, 0.03, 0.9))
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
	(_frame.material as ShaderMaterial).set_shader_parameter("background_opacity", opacity)
	self_modulate = Color(1, 1, 1, 0.45 if disabled else 1.0)
	_update_highlight(false)

func set_selected(value: bool) -> void:
	selected = value
	_update_highlight()

func _exit_tree() -> void:
	if _highlight:
		_highlight.kill()
		_highlight = null

func _update_highlight(animate := true) -> void:
	if not is_node_ready(): return
	if _highlight: _highlight.kill()
	var skin := _frame.material as ShaderMaterial
	var amount := selection_strength if selected else selection_strength * 0.45 if _hovered and not disabled else 0.0
	if animate and hover_duration > 0.0 and not Engine.is_editor_hint():
		_highlight = create_tween()
		_highlight.tween_method(func(value: float): skin.set_shader_parameter("selected_mix", value), float(skin.get_shader_parameter("selected_mix")), amount, hover_duration)
	else:
		skin.set_shader_parameter("selected_mix", amount)

func _layout() -> void:
	if not is_node_ready(): return
	_frame.size = size
	var diameter := size.x * 0.42
	_socket.size = Vector2.ONE * diameter
	_socket.position = Vector2((size.x - diameter) * 0.5, size.y * 0.13)
	_icon.position = Vector2.ONE * diameter * 0.12
	_icon.size = Vector2.ONE * diameter * 0.76
	_title.position = Vector2(size.x * 0.15, size.y * 0.40)
	_title.size = Vector2(size.x * 0.70, size.y * 0.11)
	_description.position = Vector2(size.x * 0.16, size.y * 0.52)
	_description.size = Vector2(size.x * 0.68, size.y * 0.30)
