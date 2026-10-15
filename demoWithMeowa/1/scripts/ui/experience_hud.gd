@tool
class_name ExperienceHUD
extends CanvasLayer

const FLOW_SHADER := preload("res://shaders/ui/experience_flow.gdshader")

@export_group("布局")
## 开启跟随血蓝条，关闭后使用下面的独立屏幕位置。
@export var follow_attributes := true:
	set(value): follow_attributes = value; update_layout()
## 经验槽外框的逻辑宽度，不包含等级底片与数字。
@export_range(120.0, 480.0, 1.0) var track_width := 240.0:
	set(value): track_width = maxf(value, 1.0); _refresh_presentation()
@export_range(40.0, 100.0, 1.0) var badge_width := 64.0:
	set(value): badge_width = maxf(value, 1.0); _refresh_presentation()
## 跟随血蓝条下缘的间隔，逻辑像素。
@export_range(0.0, 48.0, 1.0) var attribute_gap := 6.0:
	set(value): attribute_gap = maxf(value, 0.0); update_layout()
## 等级底片、经验槽与数字之间的间隔。
@export_range(0.0, 24.0, 1.0) var item_gap := 8.0:
	set(value): item_gap = maxf(value, 0.0); _refresh_presentation()
## 未绑定属性条时使用的左上位置。
@export var screen_margin := Vector2(24, 132):
	set(value): screen_margin = value; update_layout()
## 填充区域相对经验槽外框的比例，可微调素材内边距。
@export var fill_region := Rect2(0.055, 0.2, 0.89, 0.6):
	set(value): fill_region = value; _refresh_presentation()
@export_group("视觉")
## 只调暗槽，不一起淡化金属边框。
@export_range(0.0, 1.0, 0.05) var background_opacity := 0.5:
	set(value): background_opacity = value; _refresh_presentation()
@export_range(0.0, 2.0, 0.05) var glow_strength := 0.7:
	set(value): glow_strength = value; _refresh_presentation()
@export_range(0.0, 2.0, 0.05) var fill_brightness := 0.9:
	set(value): fill_brightness = value; _refresh_presentation()
@export var show_values := true:
	set(value): show_values = value; _refresh_presentation()
@export_range(10, 24, 1) var font_size := 14:
	set(value): font_size = value; _refresh_presentation()
@export_group("拾取反馈")
@export_range(0.0, 0.6, 0.01, "suffix:s") var feedback_duration := 0.18
@export_range(0.0, 0.6, 0.05) var feedback_strength := 0.2

@export_group("经验条流光")
@export var flow_enabled := true:
	set(value): flow_enabled = value; _refresh_presentation()
## 两次扫光之间的秒数；拾取时立即唤醒闲置扫光，不打断正在移动的光带。
@export_range(0.2, 8.0, 0.1, "suffix:s") var flow_interval := 2.8
## 单次扫过已填充区域所需秒数，越小移动越快。
@export_range(0.1, 3.0, 0.05, "suffix:s") var flow_duration := 0.9
@export_range(2.0, 48.0, 1.0, "suffix:px") var flow_width := 18.0
@export_range(0.0, 2.0, 0.05) var flow_strength := 0.85
@export var flow_color := Color(1.0, 0.97, 0.8)
## 端点星芒尺寸，等比缩放；不随经验比例压缩。
@export_range(8.0, 40.0, 1.0, "suffix:px") var glint_size := 34.0:
	set(value): glint_size = value; _refresh_presentation()
@export_range(0.0, 1.0, 0.05) var glint_strength := 0.8
@export_range(0.0, 3.0, 0.1) var glint_pulse_speed := 0.8

var _flow_elapsed := 0.0

var state: RunGrowthState
var attribute_hud: Control
var hud_host: CanvasLayer
var progress_ratio := 0.0
var _feedback_left := 0.0
var _last_total := 0
@onready var _root: Control = $Root
@onready var _frame: TextureRect = $Root/Frame
@onready var _badge: TextureRect = $Root/Badge
@onready var _clip: Control = $Root/Progress
@onready var _fill: TextureRect = $Root/Progress/Fill
@onready var _level: Label = $Root/Level
@onready var _value: Label = $Root/Value
@onready var _glint: TextureRect = $Root/Glint

func _ready() -> void:
	get_viewport().size_changed.connect(update_layout)
	_refresh_presentation()
	_refresh_state()

func bind_state(model: RunGrowthState, anchor: Control = null, host: CanvasLayer = null) -> void:
	if state and state.changed.is_connected(_refresh_state): state.changed.disconnect(_refresh_state)
	state = model
	attribute_hud = anchor
	hud_host = host
	_feedback_left = 0.0
	_flow_elapsed = 0.0
	_last_total = state.total_experience if state else 0
	if state: state.changed.connect(_refresh_state)
	_refresh_state()
	update_layout()

func pulse(_amount: int) -> void:
	_feedback_left = feedback_duration
	if fmod(_flow_elapsed, maxf(flow_interval, 0.01)) >= minf(flow_duration, flow_interval): _flow_elapsed = 0.0

func clear_feedback() -> void:
	_feedback_left = 0.0
	_flow_elapsed = 0.0

func _process(delta: float) -> void:
	_feedback_left = maxf(0.0, _feedback_left - delta)
	_root.visible = (Engine.is_editor_hint() or state != null) and (not is_instance_valid(attribute_hud) or attribute_hud.is_visible_in_tree()) and (not is_instance_valid(hud_host) or hud_host.visible)
	if visible and _root.visible and progress_ratio > 0.0: _flow_elapsed += delta
	update_layout()
	_update_skin()

func _refresh_state() -> void:
	if not is_node_ready(): return
	var required := state.required_experience() if state else 0
	var capped := state != null and state.rules != null and state.level >= state.rules.level_cap
	progress_ratio = 1.0 if capped else (clampf(float(state.experience) / required, 0.0, 1.0) if state and required > 0 else 0.0)
	if Engine.is_editor_hint() and not state: progress_ratio = 0.4
	_level.text = "Lv. %d" % (state.level if state else 1)
	_value.text = "MAX" if capped else ("%d / %d" % [state.experience, required] if state else "0 / 10")
	if state:
		if state.total_experience < _last_total: clear_feedback()
		_last_total = state.total_experience
	_refresh_presentation()

func _refresh_presentation() -> void:
	if not is_node_ready(): return
	for label: Label in [_level, _value]:
		label.add_theme_font_size_override("font_size", font_size)
	var height := track_width * _frame.texture.get_height() / _frame.texture.get_width()
	var badge_height := badge_width * _badge.texture.get_height() / _badge.texture.get_width()
	var row_height := maxf(height, badge_height)
	_badge.position = Vector2(0, (row_height - badge_height) * 0.5)
	_badge.size = Vector2(badge_width, badge_height)
	_frame.position = Vector2(badge_width + item_gap, (row_height - height) * 0.5)
	_frame.size = Vector2(track_width, height)
	_clip.position = _frame.position + fill_region.position * _frame.size
	_fill.size = fill_region.size * _frame.size
	_clip.size.y = _fill.size.y
	_level.position = _badge.position
	_level.size = _badge.size
	_value.position = Vector2(_frame.position.x + track_width + item_gap, 0)
	var value_width := maxf(64.0, _value.get_minimum_size().x)
	_value.size = Vector2(value_width, row_height)
	_value.visible = show_values
	_root.size = Vector2(_value.position.x + (value_width if show_values else 0.0), row_height)
	_glint.size = Vector2(glint_size, glint_size * _glint.texture.get_height() / _glint.texture.get_width())
	_apply_progress()
	_update_skin()
	update_layout()

func _apply_progress() -> void:
	_clip.size.x = _fill.size.x * progress_ratio
	_clip.visible = progress_ratio > 0.0
	_glint.visible = progress_ratio > 0.0 and glint_strength > 0.0
	_glint.position = _clip.position + Vector2(_clip.size.x, _clip.size.y * 0.5) - _glint.size * 0.5

func _update_skin() -> void:
	var pulse_amount := feedback_strength * _feedback_left / feedback_duration if feedback_duration > 0.0 else 0.0
	var skin := _frame.material as ShaderMaterial
	skin.set_shader_parameter("background_opacity", background_opacity)
	skin.set_shader_parameter("glow_strength", glow_strength + pulse_amount)
	_fill.self_modulate = Color.WHITE * (fill_brightness + pulse_amount)
	_fill.self_modulate.a = 1.0
	var duration := minf(maxf(flow_duration, 0.01), maxf(flow_interval, 0.01))
	var phase := fmod(_flow_elapsed, maxf(flow_interval, 0.01))
	var head := clampf(phase / duration, 0.0, 1.0)
	var sweep := sin(head * PI) * flow_strength if flow_enabled and progress_ratio > 0.0 and phase < duration else 0.0
	var flow := _fill.material as ShaderMaterial
	# 已打开的 @tool 实例可能仍保留旧场景的无材质 Fill；热更新不保证重新实例化。
	if not flow or not flow.shader:
		flow = ShaderMaterial.new()
		flow.resource_local_to_scene = true
		flow.shader = FLOW_SHADER
		_fill.material = flow
	flow.set_shader_parameter("visible_fraction", progress_ratio)
	flow.set_shader_parameter("sweep_position", head)
	flow.set_shader_parameter("sweep_width", flow_width / maxf(_fill.size.x, 1.0))
	flow.set_shader_parameter("sweep_strength", sweep)
	flow.set_shader_parameter("sweep_color", flow_color)
	_glint.visible = progress_ratio > 0.0 and glint_strength > 0.0
	var breath := 0.82 + 0.18 * sin(_flow_elapsed * TAU * glint_pulse_speed)
	_glint.self_modulate.a = clampf(glint_strength * breath + pulse_amount, 0.0, 1.0)

func update_layout() -> void:
	if not is_node_ready(): return
	var viewport := get_viewport().get_visible_rect().size
	var desired := screen_margin.max(Vector2.ZERO)
	if follow_attributes and is_instance_valid(attribute_hud):
		var anchor := attribute_hud.get_global_rect()
		desired = Vector2(anchor.position.x, anchor.end.y + attribute_gap)
	var available := maxf(1.0, viewport.x - desired.x * 2.0)
	_root.scale = Vector2.ONE * minf(1.0, available / maxf(_root.size.x, 1.0))
	_root.position = desired.min((viewport - _root.size * _root.scale).max(Vector2.ZERO))

func _exit_tree() -> void:
	if state and state.changed.is_connected(_refresh_state): state.changed.disconnect(_refresh_state)
