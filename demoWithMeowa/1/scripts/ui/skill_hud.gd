@tool
class_name SkillHUD
extends HBoxContainer

signal slot_pressed(skill_id: String)

const SLOT_SHADER := preload("res://shaders/skill_hud.gdshader")

@export_group("技能栏")
## Meowa 提取的透明空槽组件，包含细光边、角部辉光与暗底。
@export var slot_texture: Texture2D:
	set(value): slot_texture = value; _queue_rebuild()
## 单个槽位的屏幕逻辑尺寸，包含辉光留白；独立于大界面缩放。
@export_range(36.0, 96.0, 1.0) var slot_size := 64.0:
	set(value): slot_size = value; _queue_rebuild()
## 相邻槽位之间的间隔，屏幕逻辑像素。
@export_range(0, 24, 1) var slot_spacing := 6:
	set(value): slot_spacing = value; _queue_rebuild()
## 左下角安全距离：X 距左侧，Y 距底部，屏幕逻辑像素。
@export var screen_margin := Vector2(24, 24):
	set(value): screen_margin = value; update_layout()
## 0 隐藏光边与辉光，1 为素材原有强度；不会改变场景中的灯光。
@export_range(0.0, 2.0, 0.05) var glow_strength := 1.0:
	set(value): glow_strength = value; _update_skins()
## 暗底透明度的倍率；0 完全透出场景，1 保留素材的半透明暗底。
@export_range(0.0, 1.0, 0.05) var background_opacity := 0.65:
	set(value): background_opacity = value; _update_skins()
## 当前先确认空槽，默认不显示技能图标；后续定稿时可开启。
@export var show_skill_icons := false:
	set(value): show_skill_icons = value; _queue_rebuild()
## 本局真实攻击的图标独立于旧学习目录；空槽外框沿用既有美术。
@export var show_run_skill_icons := true:
	set(value): show_run_skill_icons = value; _queue_rebuild()
@export_range(10, 24, 1) var level_font_size := 14:
	set(value): level_font_size = value; _queue_rebuild()

var _slot_ids: Array[String] = ["", "", "", ""]
var _catalog: LoadoutCatalog
var _run_slots: Array[Dictionary] = []
var _rebuild_queued := false
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(update_layout)
	minimum_size_changed.connect(update_layout)
	_rebuild()

func set_slots(ids: Array[String], catalog: LoadoutCatalog) -> void:
	_slot_ids = ids.duplicate()
	_catalog = catalog
	_run_slots.clear()
	_queue_rebuild()

func set_run_slots(slots: Array[Dictionary]) -> void:
	_run_slots = slots.duplicate()
	_catalog = null
	_slot_ids.clear()
	for slot in slots: _slot_ids.append(slot.id)
	while _slot_ids.size() < 4: _slot_ids.append("")
	_queue_rebuild()

func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()

func _rebuild() -> void:
	_rebuild_queued = false
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_theme_constant_override("separation", slot_spacing)
	for index in _slot_ids.size():
		var id := _slot_ids[index]
		var button := Button.new()
		button.name = "Slot%d" % index
		button.custom_minimum_size = Vector2.ONE * slot_size
		for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
			button.add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
		button.tooltip_text = "技能槽（Tab 打开管理界面）"
		button.pressed.connect(func(): slot_pressed.emit(id))
		add_child(button)
		var frame := TextureRect.new()
		frame.name = "Frame"
		frame.texture = slot_texture
		frame.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.stretch_mode = TextureRect.STRETCH_SCALE
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.material = ShaderMaterial.new()
		(frame.material as ShaderMaterial).shader = SLOT_SHADER
		button.add_child(frame)
		frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		button.mouse_entered.connect(_update_skins)
		button.mouse_exited.connect(_update_skins)
		button.focus_entered.connect(_update_skins)
		button.focus_exited.connect(_update_skins)
		var texture: Texture2D
		if index < _run_slots.size():
			var slot := _run_slots[index]
			if show_run_skill_icons: texture = slot.icon
			button.tooltip_text = "%s · Lv.%d / %d\n%s" % [slot.name, slot.level, slot.max_level, slot.description]
			var label := Label.new()
			label.name = "Level"
			label.text = "MAX" if slot.level == slot.max_level else "Lv.%d" % slot.level
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			label.add_theme_font_size_override("font_size", level_font_size)
			label.add_theme_color_override("font_color", Color(1.0, 0.91, 0.65))
			label.add_theme_color_override("font_outline_color", Color(0.06, 0.08, 0.07, 0.95))
			label.add_theme_constant_override("outline_size", 3)
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			button.add_child(label)
			label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			label.offset_right = -6
			label.offset_bottom = -4
		elif show_skill_icons and _catalog:
			var entry := _catalog.get_skill(id)
			if entry and entry.icon:
				texture = entry.icon
				button.tooltip_text = entry.display_name
		if texture:
			var icon := TextureRect.new()
			icon.name = "Icon"
			icon.texture = texture
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			button.add_child(icon)
			button.move_child(icon, 1)
			icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			var inset := slot_size * 0.2
			icon.offset_left = inset
			icon.offset_top = inset
			icon.offset_right = -inset
			icon.offset_bottom = -inset
	_update_skins()
	update_layout.call_deferred()

func _update_skins() -> void:
	if not is_inside_tree():
		return
	for button: Button in get_children():
		var frame := button.get_node_or_null("Frame") as TextureRect
		if not frame:
			continue
		var highlight := 1.15 if button.is_hovered() or button.has_focus() else 1.0
		var material := frame.material as ShaderMaterial
		material.set_shader_parameter("glow_strength", glow_strength * highlight)
		material.set_shader_parameter("background_opacity", background_opacity)

func update_layout() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport().get_visible_rect().size
	var minimum := get_combined_minimum_size()
	size = minimum
	var margin := screen_margin.max(Vector2.ZERO)
	var available := (viewport - margin * 2.0).max(Vector2.ONE)
	var factor := minf(1.0, minf(available.x / maxf(minimum.x, 1.0), available.y / maxf(minimum.y, 1.0)))
	scale = Vector2.ONE * factor
	position = Vector2(minf(margin.x, maxf(viewport.x - minimum.x * factor, 0.0)),
		maxf(viewport.y - margin.y - minimum.y * factor, 0.0))
