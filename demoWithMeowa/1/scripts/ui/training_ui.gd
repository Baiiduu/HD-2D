class_name TrainingUI
extends CanvasLayer

const TITLES := {"health": "体能训练", "attack": "力量训练", "defense": "反应训练"}
const ICONS := {"health": "heal", "attack": "sword", "defense": "armor"}
const LABELS := {"health": "生命", "attack": "攻击", "defense": "防御"}

@export_group("场景连接")
@export var player: Player
@export var loadout: LoadoutUI
@export var interaction_point: Node3D
@export_group("训练交互")
@export var interact_key: Key = KEY_F
## 沙袋前交互点的水平距离（米）。
@export_range(0.5,4.0,0.1) var interaction_radius := 2.2
## 脚底与交互点地面的最大高差，避免隔着台地使用设施。
@export_range(0.2,2.0,0.1) var height_tolerance := 1.0
@export_range(0.75,1.5,0.05) var ui_scale := 1.0
@export_group("交互提示美术")
## Meowa 键帽与训练徽标，均为透明底美术素材。
@export var hint_key_texture: Texture2D = preload("res://assets/meowa/ui/interaction/key.tres")
@export var hint_training_texture: Texture2D = preload("res://assets/meowa/ui/interaction/training.tres")
## 提示图标的显示尺寸，像素；文字随图标并排显示。
@export_range(24,64,8) var hint_icon_size := 40
@export_range(14,24,1) var hint_font_size := 18
## 提示相对设施交互点向上抬高的米数。
@export_range(0.0,2.0,0.05) var hint_height_offset := 0.7

var menu_open := false
var _loadout_was_visible := true
var _root: Control
var _window: PanelContainer
var _shade: ColorRect
var _hint: HBoxContainer
var _cards: HBoxContainer
var _points: Label
var _feedback: Label
var _train_buttons: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	loadout.state.changed.connect(_refresh)

func _exit_tree() -> void:
	if menu_open and get_tree():
		if is_instance_valid(loadout):
			loadout.visible = _loadout_was_visible

func can_interact() -> bool:
	if loadout and loadout.wave_session and not loadout.wave_session.management_allowed(): return false
	if not player or not loadout or not loadout.state or not interaction_point or loadout.menu_open:
		return false
	var offset := player.global_position - interaction_point.global_position
	if Vector2(offset.x,offset.z).length() > interaction_radius or absf(offset.y+0.75) > height_tolerance:
		return false
	# 墙体、柱子等静态碰撞会挡住交互；不允许隔墙打开面板。
	var query := PhysicsRayQueryParameters3D.create(player.global_position+Vector3.UP*0.75,interaction_point.global_position)
	query.exclude = [player.get_rid()]
	query.hit_from_inside = true
	return player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _process(_delta: float) -> void:
	_hint.visible = not menu_open and not get_tree().paused and can_interact()
	if _hint.visible:
		var camera := get_viewport().get_camera_3d()
		if not camera or camera.is_position_behind(interaction_point.global_position):
			_hint.hide()
			return
		var screen := camera.unproject_position(interaction_point.global_position+Vector3.UP*hint_height_offset)
		var viewport := get_viewport().get_visible_rect().size
		_hint.position = Vector2(clampf(screen.x-_hint.size.x*0.5,16,viewport.x-_hint.size.x-16),clampf(screen.y,16,viewport.y-_hint.size.y-110))

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if menu_open and event.physical_keycode in [KEY_ESCAPE,interact_key]:
		close_menu()
		get_viewport().set_input_as_handled()
	elif menu_open and event.physical_keycode == KEY_TAB:
		get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
	if menu_open:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == interact_key and not menu_open and not get_tree().paused:
		if open_menu():
			get_viewport().set_input_as_handled()

func open_menu() -> bool:
	if menu_open or get_tree().paused or not can_interact():
		return false
	menu_open = true
	add_to_group(&"gameplay_input_blockers")
	_loadout_was_visible = loadout.visible
	loadout.hide()
	_hint.hide()
	_shade.show()
	_window.show()
	_feedback.text = "选择训练项目，查看属性提升与消耗。"
	_refresh()
	_fit()
	loadout._audio.play(&"journal_open")
	return true

func close_menu() -> void:
	if not menu_open:
		return
	menu_open = false
	remove_from_group(&"gameplay_input_blockers")
	loadout.visible = _loadout_was_visible
	_shade.hide()
	_window.hide()
	loadout._audio.play(&"journal_close")

func train(attribute: String) -> bool:
	if not menu_open:
		return false
	if not can_interact() or loadout._save_blocked:
		loadout._audio.play(&"error")
		return false
	var before: float = loadout.state.get_character_attributes().get(attribute,0.0)
	var cost := loadout.state.training_rules.get_cost(loadout.state.get_training_level(attribute))
	if not loadout.state.train(attribute):
		loadout._audio.play(&"error")
		return false
	var after: float = loadout.state.get_character_attributes()[attribute]
	var saved := loadout._status.text if loadout.save_enabled else "本次运行有效"
	_feedback.text = "%s %s → %s  ·  消耗 %d 训练点  ·  %s" % [LABELS[attribute],loadout._number(before),loadout._number(after),cost,saved]
	loadout._audio.play(&"confirm")
	return true

func _panel(color: Color, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color("43536a")
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		style.set_border_width(side,1)
		style.set_content_margin(side,padding)
	return style

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = loadout._theme
	_root.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_root)
	_root.resized.connect(_fit)
	_shade = ColorRect.new()
	_shade.color = Color(0.02,0.03,0.05,0.7)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.hide()
	_root.add_child(_shade)
	_window = PanelContainer.new()
	_window.size = Vector2(940,660)
	_window.add_theme_stylebox_override("panel",_panel(Color("142033"),30))
	_window.hide()
	_root.add_child(_window)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation",18)
	_window.add_child(content)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",18)
	header.add_child(loadout._icon(load("res://assets/meowa/training/sign.png"),70))
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(loadout._label("幸存者训练小屋",30,LoadoutUI.GOLD))
	heading.add_child(loadout._label("让每一次训练成为你的力量",18,LoadoutUI.MUTED))
	header.add_child(heading)
	header.add_child(loadout._button("返回  [ESC]",close_menu))
	content.add_child(header)
	_points = loadout._label("",22,LoadoutUI.GOLD)
	content.add_child(_points)
	_cards = HBoxContainer.new()
	_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("separation",16)
	content.add_child(_cards)
	_feedback = loadout._label("",18,LoadoutUI.GREEN)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.custom_minimum_size.y = 48
	content.add_child(_feedback)
	content.add_child(loadout._label("训练提升永久保留，可与装备加成叠加。",17,LoadoutUI.MUTED))
	_hint = _build_hint()
	_hint.hide()
	_root.add_child(_hint)
	_fit()

func _build_hint() -> HBoxContainer:
	var hint := HBoxContainer.new()
	hint.name = "InteractionHint"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_theme_constant_override("separation",8)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	var key := Control.new()
	key.custom_minimum_size = Vector2.ONE*hint_icon_size
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.add_child(key)
	var key_art := loadout._icon(hint_key_texture,hint_icon_size)
	key_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	key.add_child(key_art)
	var key_label := loadout._label(OS.get_keycode_string(interact_key),hint_font_size+2,Color("243449"))
	key_label.add_theme_font_override("font",font)
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	key_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 字母对齐键帽的浅色顶面，而非底部阴影。
	key_label.offset_top = -hint_icon_size*0.12
	key_label.offset_bottom = -hint_icon_size*0.12
	key.add_child(key_label)
	hint.add_child(loadout._icon(hint_training_texture,hint_icon_size))
	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_theme_constant_override("separation",0)
	hint.add_child(text)
	for item in [{"text":"训练", "size":hint_font_size, "color":LoadoutUI.CREAM}, {"text":"生命 · 攻击 · 防御", "size":maxi(12,hint_font_size-4), "color":LoadoutUI.GOLD}]:
		var label := loadout._label(item.text,item.size,item.color)
		label.add_theme_font_override("font",font)
		label.add_theme_color_override("font_outline_color",Color("101923"))
		label.add_theme_constant_override("outline_size",2)
		text.add_child(label)
	return hint

func _refresh() -> void:
	if not _cards or not loadout.state:
		return
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	_train_buttons.clear()
	var state := loadout.state
	var rules := state.training_rules
	_points.text = "可用训练点  %d" % state.training_points
	var attributes := state.get_character_attributes()
	for attribute: String in TrainingRules.ATTRIBUTES:
		var card := PanelContainer.new()
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel",_panel(Color("1c2b40"),20))
		_cards.add_child(card)
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation",14)
		card.add_child(column)
		column.add_child(loadout._icon(load(LoadoutUI.ART+ICONS[attribute]+".png"),66))
		column.add_child(loadout._label(TITLES[attribute],23,LoadoutUI.CREAM))
		var level := state.get_training_level(attribute)
		column.add_child(loadout._label("训练等级  %d / %d" % [level,rules.level_cap],17,LoadoutUI.MUTED))
		column.add_child(loadout._label("%s  %s" % [LABELS[attribute],loadout._number(attributes[attribute])],28,LoadoutUI.CREAM))
		var full := level >= rules.level_cap
		column.add_child(loadout._label("已达到训练上限" if full else "下一级  %s → %s" % [loadout._number(attributes[attribute]),loadout._number(attributes[attribute]+rules.get_gain(attribute))],18,LoadoutUI.GREEN))
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		column.add_child(spacer)
		var cost := rules.get_cost(level)
		var button := loadout._button("已满级" if full else "训练  ·  %d 点" % cost,train.bind(attribute))
		button.disabled = not state.can_train(attribute) or loadout._save_blocked
		button.tooltip_text = "训练点不足" if state.training_points < cost else ""
		_train_buttons[attribute] = button
		column.add_child(button)
	if loadout._save_blocked:
		_feedback.text = "角色存档无法读取，训练暂不可用。"

func _fit() -> void:
	if not _window:
		return
	var viewport := get_viewport().get_visible_rect().size
	var factor := minf(ui_scale,minf((viewport.x-40)/940.0,(viewport.y-40)/660.0))
	_window.scale = Vector2.ONE*factor
	_window.position = (viewport-Vector2(940,660)*factor)*0.5
