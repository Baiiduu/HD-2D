class_name FarmingUI
extends CanvasLayer

const FRAME_SHADER := preload("res://shaders/attribute_hud.gdshader")

@export var farming: Farming
@export_group("像素交互素材")
@export var frame_texture: Texture2D
@export var left_mouse_texture: Texture2D
@export var right_mouse_texture: Texture2D
@export var sprout_texture: Texture2D
@export var water_texture: Texture2D
@export var success_texture: Texture2D
@export var error_texture: Texture2D
@export_group("纯图标提示")
## 仅关闭提示，不影响现有种植操作。
@export var enabled := true
@export_range(0.75, 1.5, 0.05) var ui_scale := 1.0
## 工具小框的逻辑像素大小；鼠标图示保持原图比例。
@export_range(24, 48, 4) var icon_size := 32.0
@export_range(8, 18, 1) var badge_size := 12.0
@export_range(0, 12, 1) var icon_gap := 4
## 相对地块屏幕投影的偏移；X 向右，Y 向下。
@export var screen_offset := Vector2(12, -44)
@export_range(0.0, 1.0, 0.05) var frame_opacity := 0.65
@export_group("操作反馈")
@export_range(0.3, 2.0, 0.1) var feedback_duration := 0.7
@export_range(0.0, 0.4, 0.01) var fade_duration := 0.10
@export_range(0.0, 32.0, 1.0) var feedback_lift := 8.0
@export_range(12, 28, 1) var feedback_size := 18.0

var _root: Control
var _hint: HBoxContainer
var _mouse: TextureRect
var _tool_frame: NinePatchRect
var _tool_icon: TextureRect
var _sown: TextureRect
var _wet: TextureRect
var _invalid: TextureRect
var _feedback: TextureRect
var _feedback_remaining := 0.0
var _feedback_origin := Vector2.ZERO
var _hint_alpha := 0.0

func _ready() -> void:
	if not farming or not farming.loadout:
		set_process(false)
		return
	_root = Control.new()
	_root.name = "Interaction"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_root)
	_hint = HBoxContainer.new()
	_hint.name = "IconHint"
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hint)
	_mouse = _picture(_hint)
	_tool_frame = NinePatchRect.new()
	_tool_frame.texture = frame_texture
	_tool_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]: _tool_frame.set_patch_margin(side, 8)
	var skin := ShaderMaterial.new()
	skin.shader = FRAME_SHADER
	_tool_frame.material = skin
	_hint.add_child(_tool_frame)
	_tool_icon = _picture(_tool_frame)
	_tool_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tool_icon.offset_left = 5
	_tool_icon.offset_top = 5
	_tool_icon.offset_right = -5
	_tool_icon.offset_bottom = -5
	_sown = _picture(_tool_frame, sprout_texture)
	_wet = _picture(_tool_frame, water_texture)
	_invalid = _picture(_tool_frame, error_texture)
	_feedback = _picture(_root)
	_hint.hide()
	_feedback.hide()
	farming.interaction_feedback.connect(_show_feedback)

func _picture(parent: Control, texture: Texture2D = null) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = texture
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	parent.add_child(picture)
	return picture

func _process(delta: float) -> void:
	var viewport := get_viewport().get_visible_rect().size
	_root.size = viewport
	var view := farming.get_interaction_state()
	var camera := get_viewport().get_camera_3d()
	var show_hint: bool = enabled and view.visible and view.has_target and view.in_reach and camera != null and not camera.is_position_behind(view.position)
	_hint_alpha = move_toward(_hint_alpha, 1.0 if show_hint else 0.0, delta / fade_duration if fade_duration > 0 else 1.0)
	if farming._blocked() or not enabled:
		_hint_alpha = 0
		_feedback_remaining = 0
	_hint.visible = _hint_alpha > 0
	_hint.modulate.a = _hint_alpha
	_hint.scale = Vector2.ONE * ui_scale
	_hint.add_theme_constant_override("separation", icon_gap)
	_mouse.custom_minimum_size = Vector2(icon_size * 0.775, icon_size)
	_tool_frame.custom_minimum_size = Vector2.ONE * icon_size
	(_tool_frame.material as ShaderMaterial).set_shader_parameter("background_opacity", frame_opacity)
	if show_hint:
		var restoring: bool = view.can_restore and (view.restore_error.is_empty() or view.cooldown)
		var button: MouseButton = farming.restore_button if restoring else farming.use_button
		_mouse.texture = left_mouse_texture if button == MOUSE_BUTTON_LEFT else (right_mouse_texture if button == MOUSE_BUTTON_RIGHT else null)
		_tool_icon.texture = (view.item as ItemDefinition).icon
		_mouse.modulate.a = 0.5 if view.cooldown else (1.0 if view.target_valid else 0.35)
		_tool_icon.modulate.a = 1.0 if view.target_valid else 0.5
		_sown.visible = view.sown
		_wet.visible = view.watered
		_invalid.visible = not view.target_valid and not view.cooldown
		for badge in [_sown, _wet, _invalid]: badge.size = Vector2.ONE * badge_size
		_sown.position = Vector2(icon_size - badge_size * 0.6, -2)
		_wet.position = Vector2(icon_size - badge_size * 0.6, icon_size - badge_size * 0.6)
		_invalid.position = (Vector2.ONE * icon_size - _invalid.size) * 0.5
		_place(_hint, camera.unproject_position(view.position) + screen_offset * ui_scale, viewport)
	_update_feedback(delta, viewport)

func _place(control: Control, point: Vector2, viewport: Vector2) -> void:
	control.size = control.get_combined_minimum_size() if control is Container else Vector2.ONE * feedback_size
	control.position = point.clamp(Vector2(16, 16), viewport - control.size * ui_scale - Vector2(16, 16)).round()
	var bar := farming.loadout._item_bar.get_global_rect()
	if control.get_global_rect().grow(4).intersects(bar.grow(8)):
		control.position.y = maxf(16, bar.position.y - control.size.y * ui_scale - 12)

func _show_feedback(_message: String, success: bool) -> void:
	if not enabled or farming._blocked(): return
	_feedback.texture = success_texture if success else error_texture
	_feedback_remaining = feedback_duration
	var camera := get_viewport().get_camera_3d()
	_feedback_origin = camera.unproject_position(farming.cell_position(farming._target)) + Vector2(12, -4) if camera and farming._has_target else get_viewport().get_mouse_position() + Vector2(12, -24)

func _update_feedback(delta: float, viewport: Vector2) -> void:
	_feedback_remaining = maxf(0, _feedback_remaining - delta)
	_feedback.visible = _feedback_remaining > 0
	if not _feedback.visible: return
	_feedback.scale = Vector2.ONE * ui_scale
	var elapsed := feedback_duration - _feedback_remaining
	var alpha := minf(elapsed / fade_duration, _feedback_remaining / fade_duration) if fade_duration > 0 else 1.0
	_feedback.modulate.a = clampf(alpha, 0, 1)
	_place(_feedback, _feedback_origin - Vector2(0, feedback_lift * elapsed / maxf(feedback_duration, 0.01)), viewport)
