@tool
class_name AttributeHUD
extends Control

const FRAME_SHADER := preload("res://shaders/ui/attribute_hud.gdshader")
const REFERENCE_WIDTH := 320.0

@export_group("人物连接")
@export var player: Player:
	set(value):
		if player == value:
			return
		if not Engine.is_editor_hint() and is_instance_valid(player) and player.vitals_changed.is_connected(_refresh_values):
			player.vitals_changed.disconnect(_refresh_values)
		player = value
		if not Engine.is_editor_hint() and is_instance_valid(player):
			player.vitals_changed.connect(_refresh_values)
		_refresh_values()
@export_group("属性条素材")
@export var health_frame: Texture2D:
	set(value): health_frame = value; _queue_rebuild()
@export var mana_frame: Texture2D:
	set(value): mana_frame = value; _queue_rebuild()
@export var health_fill: Texture2D:
	set(value): health_fill = value; _queue_rebuild()
@export var mana_fill: Texture2D:
	set(value): mana_fill = value; _queue_rebuild()
@export_group("布局")
## 只控制蓝条显示；隐藏后收起所占高度，经验条沿实际下缘跟随。
@export var show_mana := true:
	set(value): show_mana = value; _queue_rebuild()
## 每条外框的逻辑像素宽度，包含辉光留白；360 在当前窗口中约为 320 像素。
@export_range(160.0, 720.0, 1.0, "or_greater") var bar_width := 360.0:
	set(value): bar_width = maxf(value, 1.0); _queue_rebuild()
## 左上角安全距离，X 距左侧、Y 距顶部，逻辑像素。
@export var screen_margin := Vector2(24, 32):
	set(value): screen_margin = value; update_layout()
## 上下两条之间的逻辑像素间隔；负值使辉光留白重叠。
@export_range(-20.0, 64.0, 1.0) var bar_gap := -10.0:
	set(value): bar_gap = value; _queue_rebuild()
## 填充相对外框的位置与大小，按 320 像素参考宽度填写，随整条尺寸缩放。
@export var fill_rect := Rect2(22, 13, 276, 22):
	set(value): fill_rect = value; _queue_rebuild()
@export_group("视觉")
## 1 为 Meowa 原有光边与辉光强度，0 隐藏亮边；独立于场景灯光。
@export_range(0.0, 2.0, 0.05) var glow_strength := 1.0:
	set(value): glow_strength = value; _update_skins()
## 暗槽透明度倍率；0 完全透出场景，1 保留素材原有半透明暗底。
@export_range(0.0, 1.0, 0.05) var background_opacity := 1.0:
	set(value): background_opacity = value; _update_skins()
## 红蓝填充的亮度倍率，1 保留素材颜色。
@export_range(0.0, 2.0, 0.05) var fill_brightness := 1.0:
	set(value): fill_brightness = value; _update_skins()
## 数字由人物实时数值生成，未烘焙在美术中；关闭后只显示属性条。
@export var show_values := true:
	set(value): show_values = value; _update_skins()
@export_range(10, 28, 1) var value_font_size := 16:
	set(value): value_font_size = value; _update_skins()
@export var value_color := Color(1.0, 0.96, 0.88):
	set(value): value_color = value; _update_skins()

var _bars: Array[Control] = []
var _rebuild_queued := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(update_layout)
	_rebuild()

func _queue_rebuild() -> void:
	if not is_inside_tree() or _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()

func _picture(texture: Texture2D) -> TextureRect:
	var picture := TextureRect.new()
	picture.texture = texture
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return picture

func _rebuild() -> void:
	_rebuild_queued = false
	for row in _bars:
		remove_child(row)
		row.queue_free()
	_bars.clear()
	var frame_textures := [health_frame, mana_frame]
	var fill_textures := [health_fill, mana_fill]
	var factor := bar_width / REFERENCE_WIDTH
	var region := Rect2(fill_rect.position * factor, fill_rect.size.max(Vector2.ZERO) * factor)
	var y := 0.0
	for index in 2:
		var row := Control.new()
		row.name = "Health" if index == 0 else "Mana"
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var texture := frame_textures[index] as Texture2D
		var height := bar_width * texture.get_height() / texture.get_width() if texture else 46.0 * factor
		row.position.y = y
		row.size = Vector2(bar_width, height)
		add_child(row)
		_bars.append(row)
		var frame := _picture(texture)
		frame.name = "Frame"
		frame.size = row.size
		frame.material = ShaderMaterial.new()
		(frame.material as ShaderMaterial).shader = FRAME_SHADER
		row.add_child(frame)
		var clip := Control.new()
		clip.name = "Progress"
		clip.position = region.position
		clip.size = region.size
		clip.clip_contents = true
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(clip)
		var fill := _picture(fill_textures[index])
		fill.name = "Fill"
		fill.size = region.size
		clip.add_child(fill)
		var label := Label.new()
		label.name = "Value"
		label.position = region.position
		label.size = region.size
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.add_theme_color_override("font_outline_color", Color(0.02, 0.01, 0.01, 0.9))
		label.add_theme_constant_override("outline_size", 2)
		row.add_child(label)
		y += maxf(1.0, height + bar_gap) if index == 0 else height
	_bars[1].visible = show_mana
	size = Vector2(bar_width, y if show_mana else _bars[0].size.y)
	_update_skins()
	_refresh_values()
	update_layout()

func _update_skins() -> void:
	for row in _bars:
		var frame: TextureRect = row.get_node("Frame")
		var skin := frame.material as ShaderMaterial
		skin.set_shader_parameter("glow_strength", glow_strength)
		skin.set_shader_parameter("background_opacity", background_opacity)
		var fill: TextureRect = row.get_node("Progress/Fill")
		fill.self_modulate = Color(fill_brightness, fill_brightness, fill_brightness)
		var label: Label = row.get_node("Value")
		label.visible = show_values
		label.add_theme_font_size_override("font_size", value_font_size)
		label.add_theme_color_override("font_color", value_color)

func _refresh_values() -> void:
	if _bars.size() != 2:
		return
	if Engine.is_editor_hint():
		_apply_value(0, 100.0, 100.0)
		_apply_value(1, 100.0, 100.0)
	elif is_instance_valid(player):
		_apply_value(0, player.current_health, player.max_health)
		_apply_value(1, player.current_mana, player.max_mana)
	else:
		_apply_value(0, 0.0, 0.0)
		_apply_value(1, 0.0, 0.0)

func _apply_value(index: int, value: float, maximum: float) -> void:
	var row := _bars[index]
	var clip: Control = row.get_node("Progress")
	var fill: TextureRect = row.get_node("Progress/Fill")
	var ratio := clampf(value / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0
	clip.size.x = fill.size.x * ratio
	clip.visible = ratio > 0.0
	(row.get_node("Value") as Label).text = "%s / %s" % [_number(value), _number(maximum)]

func _number(value: float) -> String:
	var rounded := snappedf(value, 0.01)
	return str(int(rounded)) if rounded == floorf(rounded) else str(rounded)

func update_layout() -> void:
	if not is_inside_tree():
		return
	var viewport := get_viewport().get_visible_rect().size
	var margin := screen_margin.max(Vector2.ZERO)
	var available := (viewport - margin * 2.0).max(Vector2.ONE)
	var factor := minf(1.0, minf(available.x / maxf(size.x, 1.0), available.y / maxf(size.y, 1.0)))
	scale = Vector2.ONE * factor
	position = margin.min((viewport - size * factor).max(Vector2.ZERO))
