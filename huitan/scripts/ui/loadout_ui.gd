class_name LoadoutUI
extends CanvasLayer

const ART := "res://assets/meowa/ui/loadout/"
const JOURNAL_ART := "res://assets/meowa/ui/journal/"
const CANVAS := Vector2(2048, 1152)
const INK := Color("283121")
const SLOT_NAMES := ["武器", "防具", "饰品"]
const CREAM := Color("e8dec3")
const GOLD := Color("e5c578")
const MUTED := Color("a7b5c8")
const GREEN := Color("92d5b0")

@export_group("场景连接与角色规则")
@export var catalog: LoadoutCatalog
@export var player: Player
## 波次灰盒的管理限制；技能页先留空，不修改原有学习存档。
@export var wave_session: Node
## 角色基础属性与训练规则；与训练小屋共享。
@export var training_rules: TrainingRules = preload("res://data/rpg/training_rules.tres")
## 由地图战斗配置选择；关闭后仍载入原存档，但不应用装备属性或旧技能加成。
@export var equipment_bonuses_enabled := true
@export_group("装备与技能界面")
## 关闭玩家入口，保留角色状态、局内成长和存档；预览场景可独立开放。
@export var player_access_enabled := true:
	set(value):
		player_access_enabled = value
		if not value and menu_open and _motion:
			_motion.disable_motion()
			if menu_open: _finish_close()
		if _hud: _hud.management_enabled = value
		if _item_bar: _item_bar.player_access_enabled = value
		_sync_bottom_bars()
## 打开/关闭界面的按键；ESC 也可关闭。
@export var toggle_key: Key = KEY_TAB
## 只折叠底部快捷栏；背包、属性、战斗和输入状态不受影响。
@export var bottom_bars_collapsed := false:
	set(value):
		bottom_bars_collapsed = value
		_sync_bottom_bars()
## 可装配技能的界面槽位数量，可按后续玩法调整。
@export_range(1, 8, 1) var skill_slot_count := 4:
	set(value):
		skill_slot_count = clampi(value, 1, 8)
		if state:
			state.set_skill_slot_count(skill_slot_count)
## 优先采用的 UI 缩放；屏幕不足时自动缩小以保持完整显示。
@export_range(0.6, 1.5, 0.05) var ui_scale := 0.8:
	set(value): ui_scale = value; _fit_window()
## 中文文字的基础字号，标题及说明在此基础上分级。
@export_range(16, 28, 1) var font_size := 24
## 悬浮提示独立使用小字号，不随书页正文放大。
@export_range(12, 20, 1) var tooltip_font_size := 16:
	set(value): tooltip_font_size = value; _update_tooltip_theme()
## 悬浮提示默认全透明；需要暗底辅助阅读时可小幅增加。
@export_range(0.0, 0.5, 0.05) var tooltip_background_opacity := 0.0:
	set(value): tooltip_background_opacity = value; _update_tooltip_theme()
## 打开界面时游戏世界的压暗程度；0 完全保留，越大背景越暗。
@export_range(0.0, 0.65, 0.05) var world_dim_amount := 0.18:
	set(value):
		world_dim_amount = value
		if is_instance_valid(_shade): _shade.color.a = value * (_motion.amount if _motion else 1.0)
## 人物立绘，独立于地图角色贴图，可在检查器替换。
@export var portrait_texture: Texture2D = preload("res://assets/meowa/ui/journal/portrait.png")
## 立绘相对书页的大小；1.0 对应已确认的构图。
@export_range(0.75, 1.15, 0.05) var portrait_scale := 1.0:
	set(value):
		portrait_scale = value
		if state: _queue_refresh()
@export_group("手帐动效")
## 一键关闭动效，界面立即响应，适合减少动态或进行对比。
@export var motion_enabled := true:
	set(value):
		motion_enabled = value
		if _motion and _book and not value: _motion.disable_motion()
## 打开和关闭书本所用的秒数；0 立即完成。
@export_range(0.0, 0.8, 0.01) var open_duration := 0.24
@export_range(0.0, 0.8, 0.01) var close_duration := 0.16
## 打开时的起始比例，相对 ui_scale 的最终尺寸。
@export_range(0.85, 1.0, 0.01) var open_start_scale := 0.96
## 打开时向上浮起的距离，书本设计坐标的像素。
@export_range(0.0, 40.0, 1.0) var open_lift := 12.0
## 悬停和按压反馈的秒数。
@export_range(0.0, 0.4, 0.01) var hover_duration := 0.10
## 悬停时只放大图标，保留按钮点击区域和文字排版。
@export_range(1.0, 1.12, 0.01) var hover_scale := 1.04
@export_range(0.0, 0.3, 0.01) var hover_brightness := 0.08
## 按钮画面按下时下沉的像素，点击区域保持不变。
@export_range(0.0, 6.0, 0.5) var button_press_distance := 2.0
## 切页内容淡入的秒数和横向位移；书本边框保持固定。
@export_range(0.0, 0.6, 0.01) var page_duration := 0.18
@export_range(0.0, 32.0, 1.0) var page_slide_distance := 12.0
## 装备图标飞入槽位、属性数字过渡的秒数。
@export_range(0.0, 0.8, 0.01) var equip_duration := 0.28
@export_range(0.0, 0.8, 0.01) var attribute_duration := 0.30
@export var equip_glow_color := Color("e5c578")
@export_group("初始内容与保存")
## 首次进入时拥有的装备，后续由 acquire_equipment 接入掉落/奖励。
@export var starting_equipment: Array[String] = []
## 首次进入时已学习的技能；没有填写的技能可在技能页学习。
@export var starting_skills: Array[String] = []
## 首次进入时按顺序装配的技能 ID。
@export var starting_assignments: Array[String] = []
## 新物品演示数量，只在新存档或旧装备存档升级时初始化一次。
@export var starting_items: Dictionary[String, int] = {}
@export var starting_quick_items: Array[String] = []
## 自动保存穿戴、学习和装配状态；测试时可关闭。
@export var save_enabled := true
## 正常游戏使用 user://；验证脚本可指定独立路径。
@export var save_path := "user://equipment_skills.json"

var state: LoadoutState
var menu_open := false
var current_page := 0
var selected_equipment := ""
var selected_skill := ""
var _root: Control
var _shade: ColorRect
var _window: Control
var _book: Control
var _content: Control
var _fx: Control
var _input_guard: Control
var _motion: JournalEffects
var _stat_labels: Dictionary = {}
var _hud: SkillHUD
var _attribute_hud: AttributeHUD
var _left: Control
var _entries: Control
var _details: VBoxContainer
var _actions: VBoxContainer
var _search: LineEdit
var _legacy_search: LineEdit
var _foundation: TextureRect
var _inventory_book: InventoryBookPage
var _item_bar: ItemQuickbar
var _bottom_toggle: Button
var _audio: UIAudio
var _filter: OptionButton
var _status: Label
var _title: Label
var _count: Label
var _detail_name: Label
var _detail_icon: TextureRect
var _detail_scroll: ScrollContainer
var _left_scroll: ScrollContainer
var _left_scroll_y := 0
var _chips: Control
var _inventory_page := 0
var _equipment_tab := 1
var _tabs: Array[Button] = []
var _theme: Theme
var _normal: StyleBox
var _active: StyleBox
var _refresh_queued := false
var _save_blocked := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	if not catalog or not catalog.validation_errors().is_empty():
		push_error("装备与技能目录配置无效。")
		return
	state = LoadoutState.new(catalog, skill_slot_count, training_rules)
	state.equipment_bonuses_enabled = equipment_bonuses_enabled
	var had_save := save_enabled and FileAccess.file_exists(save_path)
	var loaded := had_save and state.load_from_path(save_path)
	_save_blocked = had_save and not loaded
	if not loaded:
		for id in starting_equipment:
			state.acquire_equipment(id)
		for id in starting_skills:
			state.learn_skill(id)
		for slot in mini(starting_assignments.size(), skill_slot_count):
			state.assign_skill(starting_assignments[slot], slot)
		if not starting_equipment.is_empty():
			for entry in catalog.equipment:
				if state.owns_equipment(entry.id) and state.get_equipped_id(entry.slot).is_empty():
					state.equip(entry.id)
	if loaded and state.loaded_save_version < LoadoutState.SAVE_VERSION:
		var backup := save_path + ".v%d.bak" % state.loaded_save_version
		if not FileAccess.file_exists(backup):
			DirAccess.copy_absolute(ProjectSettings.globalize_path(save_path), ProjectSettings.globalize_path(backup))
	if not state.inventory_initialized:
		for id in starting_items:
			state.add_item(id,starting_items[id])
		for slot in mini(LoadoutState.QUICK_SLOT_COUNT,starting_quick_items.size()):
			if not starting_quick_items[slot].is_empty(): state.assign_item(starting_quick_items[slot],slot)
		state.inventory_initialized = true
	selected_equipment = state.get_equipped_id(EquipmentDefinition.Slot.WEAPON)
	if selected_equipment.is_empty() and not state.get_owned_equipment().is_empty():
		selected_equipment = state.get_owned_equipment()[0]
	if not catalog.skills.is_empty():
		selected_skill = catalog.skills[0].id
	if player:
		player.character_state = state
	_motion = JournalEffects.new()
	_motion.configure(self)
	add_child(_motion)
	_audio = $UIAudio as UIAudio
	_build_theme()
	_build_ui()
	state.changed.connect(_on_state_changed)
	_refresh()
	_save()

func _input(event: InputEvent) -> void:
	if not player_access_enabled or not visible or not state or not event is InputEventKey or not event.pressed or event.echo:
		return
	if not menu_open and get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null:
		return
	if event.physical_keycode == toggle_key:
		close_menu() if menu_open and not _motion.closing else open_menu()
		get_viewport().set_input_as_handled()
	elif menu_open and event.keycode == KEY_ESCAPE:
		close_menu()
		get_viewport().set_input_as_handled()

func _unhandled_key_input(_event: InputEvent) -> void:
	if menu_open:
		get_viewport().set_input_as_handled()

func open_menu(page := 0) -> void:
	if not player_access_enabled: return
	if not menu_open and get_tree().get_first_node_in_group(&"gameplay_input_blockers") != null:
		return
	if wave_session and not wave_session.management_allowed():
		wave_session.show_notice("战斗期间不打开管理页；休整时按 %s。" % OS.get_keycode_string(toggle_key))
		return
	if not menu_open or _motion.closing: _audio.play(&"journal_open")
	if not menu_open:
		add_to_group(&"gameplay_input_blockers")
	menu_open = true
	_shade.show()
	_window.show()
	_hud.hide()
	_attribute_hud.hide()
	_switch_page(page, false)
	_motion.open()

func close_menu() -> void:
	if not menu_open or _motion.closing:
		return
	_audio.play(&"journal_close")
	_motion.close()

## 仅由界面操作调用，程序初始化和存档加载不触发音效。
func _ui_action(callback: Callable, cue: StringName) -> bool:
	var result: Variant = callback.call()
	var success: bool = not (result is bool and not result)
	if not cue.is_empty(): _audio.play(cue if success else &"error")
	return success

func take_inventory_item(id: String) -> bool:
	var entry := catalog.get_item(id)
	if not entry or entry.farm_action == ItemDefinition.FarmAction.NONE or state.get_quantity(id) <= 0: return false
	var bindings := state.get_quick_slots()
	var slot := bindings.find(id)
	if slot < 0:
		slot = bindings.find("")
		if slot < 0: slot = state.active_quick_slot
		if not state.assign_item(id, slot): return false
	state.select_quick_slot(slot)
	close_menu()
	return true

func _finish_close() -> void:
	menu_open = false
	_motion.closing = false
	remove_from_group(&"gameplay_input_blockers")
	_window.hide()
	_shade.hide()
	_hud.show()
	_attribute_hud.show()
	_item_bar.show()
	_item_bar.update_layout.call_deferred()
	_sync_bottom_bars()
	_input_guard.hide()
	_save()

const PAPER := Color("ede2bf")
const GILT := Color("76602e")
const FADED := Color("736b54")
const POSITIVE := Color("35684c")

func _skin(file: String, padding := 6.0, tint := Color.WHITE) -> StyleBoxTexture:
	var skin := StyleBoxTexture.new()
	skin.texture = load(JOURNAL_ART + file)
	skin.modulate_color = tint
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		skin.set_texture_margin(side, 0.0)
		skin.set_content_margin(side, padding)
	return skin

func _outline(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(color, 0.04)
	box.border_color = color
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_border_width(side, 2)
	return box

func _font_size(design_size: int) -> int:
	return roundi(design_size * font_size / 20.0)

## 保留训练窗口使用的标签接口，避免书页的自动换行撑大其容器。
func _label(words: String, size := 0, color := CREAM) -> Label:
	var label := Label.new()
	label.text = words
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", color)
	if size > 0:
		label.add_theme_font_size_override("font_size", size)
	return label

func _button(words: String, callback: Callable) -> Button:
	var button := _journal_button(words, callback, false, false, &"")
	button.custom_minimum_size.y = 48
	button.add_theme_font_size_override("font_size", font_size)
	return button

func _build_theme() -> void:
	_theme = Theme.new()
	_theme.default_font_size = _font_size(28)
	_normal = _skin("controls/slot.png")
	_active = _skin("controls/slot-active.png")
	for state_name in ["normal", "disabled"]:
		_theme.set_stylebox(state_name, "Button", _skin("controls/equip-button.png", 12))
	for state_name in ["hover", "pressed", "focus", "hover_pressed"]:
		_theme.set_stylebox(state_name, "Button", _skin("controls/equip-button.png", 12, Color(1.12, 1.1, 1.02)))
	for state_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_theme.set_color(state_name, "Button", PAPER)
	_theme.set_color("font_disabled_color", "Button", FADED)
	_theme.set_color("font_color", "Label", INK)
	for search_state in ["normal", "focus"]:
		var search_skin := _skin("controls/category.png", 12, Color(1.1, 1.08, 0.95) if search_state == "focus" else Color.WHITE)
		search_skin.set_content_margin(SIDE_TOP, 6)
		search_skin.set_content_margin(SIDE_BOTTOM, 6)
		_theme.set_stylebox(search_state, "LineEdit", search_skin)
	_theme.set_color("font_color", "LineEdit", INK)
	_theme.set_color("font_selected_color", "LineEdit", PAPER)
	_theme.set_color("font_placeholder_color", "LineEdit", FADED)
	_theme.set_stylebox("panel", "PopupMenu", _skin("controls/details.png", 14))
	_theme.set_color("font_color", "PopupMenu", INK)
	_theme.set_color("font_color_hover", "PopupMenu", GILT)
	_update_tooltip_theme()

func _update_tooltip_theme() -> void:
	if not _theme: return
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.05, 0.07, 0.06, tooltip_background_opacity)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		panel.set_content_margin(side, 4.0 if side in [SIDE_LEFT, SIDE_RIGHT] else 2.0)
	_theme.set_stylebox("panel", "TooltipPanel", panel)
	_theme.set_color("font_color", "TooltipLabel", Color.BLACK)
	_theme.set_constant("outline_size", "TooltipLabel", 0)
	_theme.set_font_size("font_size", "TooltipLabel", tooltip_font_size)

func _at(control: Control, rect: Rect2, parent: Node = null) -> Control:
	control.position = rect.position
	control.size = rect.size
	(parent if parent else _content).add_child(control)
	return control

func _icon(texture: Texture2D, side := 0.0) -> TextureRect:
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture = texture
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(side, side)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon

func _picture(file: String, rect: Rect2, parent: Node = null, fill := false) -> TextureRect:
	var image := _icon(load(JOURNAL_ART + file))
	if fill:
		image.stretch_mode = TextureRect.STRETCH_SCALE
	_at(image, rect, parent)
	return image

func _journal_label(words: String, size := 28, color := INK) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = words
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", _font_size(size))
	label.add_theme_color_override("font_color", color)
	return label

func _text(words: String, rect: Rect2, size: int, parent: Node = null, color := INK, centered := false) -> Label:
	var label := _journal_label(words, size, color)
	if centered:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_at(label, rect, parent)
	return label

func _journal_button(words: String, callback: Callable, small := false, animated := true, cue: StringName = &"select") -> Button:
	var button := Button.new()
	button.text = words
	button.custom_minimum_size.y = 46 if small else 64
	button.add_theme_font_size_override("font_size", _font_size(26 if small else 30))
	if small:
		for state_name in ["normal", "disabled"]:
			button.add_theme_stylebox_override(state_name, _skin("controls/category.png"))
		for state_name in ["hover", "pressed", "focus"]:
			button.add_theme_stylebox_override(state_name, _skin("controls/category-active.png"))
		button.add_theme_color_override("font_color", INK)
	button.pressed.connect(_ui_action.bind(callback, cue))
	if animated: _motion.attach_button(button)
	return button

func _scroll(rect: Rect2, parent: Node = null) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_at(scroll, rect, parent)
	return scroll

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_root.theme = _theme
	add_child(_root)
	_root.resized.connect(_fit_window)
	_shade = ColorRect.new()
	_shade.color = Color(0.025, 0.045, 0.035, world_dim_amount)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.hide()
	_root.add_child(_shade)
	_window = Control.new()
	_window.name = "Window"
	_window.size = CANVAS
	_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.hide()
	_root.add_child(_window)
	_book = Control.new()
	_book.name = "Book"
	_book.size = CANVAS
	_book.pivot_offset = CANVAS * 0.5
	_book.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_window.add_child(_book)
	_foundation = _picture("foundation.png", Rect2(Vector2.ZERO, CANVAS), _book, true)
	_content = Control.new()
	_content.name = "PageContent"
	_content.size = CANVAS
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book.add_child(_content)
	_inventory_book = InventoryBookPage.new()
	_inventory_book.name = "InventoryBookPage"
	_inventory_book.size = CANVAS
	_content.add_child(_inventory_book)
	_inventory_book.build(self)
	_left = Control.new()
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_left)
	_entries = Control.new()
	_entries.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_entries)
	_detail_scroll = _scroll(Rect2(1552, 579, 305, 230))
	_details = VBoxContainer.new()
	_details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_details.add_theme_constant_override("separation", 6)
	_detail_scroll.add_child(_details)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	_at(_actions, Rect2(1552, 832, 313, 95))
	_title = _text("背包", Rect2(1090, 165, 240, 70), 48)
	_count = _text("", Rect2(1638, 196, 207, 38), 23)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_count.autowrap_mode = TextServer.AUTOWRAP_OFF
	_detail_name = _text("", Rect2(1555, 525, 296, 48), 36)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	_detail_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_detail_icon = _icon(null)
	_at(_detail_icon, Rect2(1544, 337, 291, 180))
	_search = LineEdit.new()
	_search.placeholder_text = "搜索装备或技能"
	_search.add_theme_font_size_override("font_size", _font_size(23))
	_search.text_changed.connect(func(_value): _inventory_page = 0; _queue_refresh())
	_at(_search, Rect2(1490, 252, 343, 56))
	_legacy_search = _search
	_filter = OptionButton.new()
	_filter.hide()
	_filter.item_selected.connect(_filter_changed)
	_content.add_child(_filter)
	_chips = Control.new()
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(_chips)
	# 三页沿用同一书本底图与页签，背包页独立显示通用物品。
	for tab in 3:
		var button := _journal_button(["人物", "背包", "技能"][tab], _tab_pressed.bind(tab), false, true, &"")
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size", _font_size(34))
		var rect: Rect2 = [Rect2(278, 30, 238, 88), Rect2(521, 48, 218, 81), Rect2(744, 62, 204, 78)][tab]
		_at(button, rect, _book)
		_tabs.append(button)
	var close := _journal_button("", close_menu, false, true, &"")
	for state_name in ["normal", "hover", "pressed", "focus"]:
		close.add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
	close.tooltip_text = "返回地图（ESC）"
	_at(close, Rect2(1870, 81, 98, 96), _book)
	_text("关闭", Rect2(1870, 151, 90, 34), 23, _book, PAPER, true)
	# 保存反馈供训练窗口读取，不在书页右下角显示文字。
	_status = Label.new()
	_status.hide()
	_book.add_child(_status)
	_fx = Control.new()
	_fx.name = "Effects"
	_fx.size = CANVAS
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_book.add_child(_fx)
	_hud = $SkillHUD as SkillHUD
	_hud.management_enabled = player_access_enabled
	_hud.reparent(_root)
	_hud.slot_pressed.connect(_open_skill_from_hud)
	_item_bar = $ItemQuickbar as ItemQuickbar
	_item_bar.player_access_enabled = player_access_enabled
	_item_bar.audio = _audio
	_item_bar.reparent(_root)
	_item_bar.bind_state(state,_hud)
	_bottom_toggle = Button.new()
	_bottom_toggle.name = "BottomBarsToggle"
	_bottom_toggle.focus_mode = Control.FOCUS_NONE
	_bottom_toggle.theme = _theme
	_bottom_toggle.add_theme_font_size_override("font_size", 16)
	_bottom_toggle.pressed.connect(func(): bottom_bars_collapsed = not bottom_bars_collapsed)
	_root.add_child(_bottom_toggle)
	_attribute_hud = $AttributeHUD as AttributeHUD
	_attribute_hud.reparent(_root)
	_attribute_hud.player = player
	_input_guard = Control.new()
	_input_guard.name = "OpeningClosingInputGuard"
	_input_guard.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_input_guard.hide()
	_root.add_child(_input_guard)
	_motion.apply_open(0.0)
	_populate_filter()
	_fit_window()

func _fit_window() -> void:
	if not is_instance_valid(_window) or not is_instance_valid(_root):
		return
	var viewport := get_viewport().get_visible_rect().size
	var available := minf(viewport.x / CANVAS.x, viewport.y / CANVAS.y)
	var factor := minf(available, available * 0.96 * ui_scale)
	_window.scale = Vector2.ONE * factor
	_window.position = (viewport - CANVAS * factor) * 0.5
	if _hud:
		_hud.update_layout()
	if _item_bar:
		_item_bar.update_layout()
	if _bottom_toggle:
		_bottom_toggle.position = Vector2(maxf(8.0, viewport.x - 132.0), maxf(8.0, viewport.y - 42.0))
		_bottom_toggle.size = Vector2(120, 32)
	_sync_bottom_bars()

func _sync_bottom_bars() -> void:
	if not is_instance_valid(_bottom_toggle): return
	_bottom_toggle.text = "展开装备栏" if bottom_bars_collapsed else "隐藏装备栏"
	_bottom_toggle.visible = player_access_enabled and not menu_open
	if _hud: _hud.visible = not bottom_bars_collapsed and not menu_open
	if _item_bar: _item_bar.visible = player_access_enabled and not bottom_bars_collapsed and (not menu_open or (current_page == 0 and _equipment_tab == 1))

func _tab_pressed(tab: int) -> void:
	var previous_tab := 2 if current_page == 1 else _equipment_tab
	if tab < 2: _equipment_tab = tab
	_switch_page(1 if tab == 2 else 0, false)
	if tab != previous_tab:
		_audio.play(&"page_turn")
		_motion.turn_page(1 if tab > previous_tab else -1)
	if tab == 1:
		_search.grab_focus()

func _switch_page(page: int, animated := true) -> void:
	var previous := current_page
	_motion.reset_page()
	_motion.clear_equipment_effects()
	current_page = clampi(page, 0, 1)
	_search.text = ""
	if _legacy_search: _legacy_search.text = ""
	if _inventory_book: _inventory_book.search.text = ""
	_inventory_page = 0
	_left_scroll_y = 0
	_populate_filter()
	_refresh()
	if animated and current_page != previous:
		_motion.turn_page(1 if current_page > previous else -1)

func _populate_filter() -> void:
	_filter.clear()
	if current_page == 1 and wave_session:
		_filter.add_item("方案待讨论")
		return
	for title in ["全部", "武器", "防具", "饰品"] if current_page == 0 else ["全部", "已学习", "未学习"]:
		_filter.add_item(title)

func _filter_changed(index: int) -> void:
	_filter.select(index)
	_inventory_page = 0
	_queue_refresh()

func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_refresh.call_deferred()

func _on_state_changed() -> void:
	_motion.state_changed()
	_save()
	_queue_refresh()

func _save() -> void:
	if not save_enabled or not _status:
		return
	if _save_blocked:
		_status.text = "存档未读取，更改未保存"
		return
	_status.text = "已保存" if state.save_to_path(save_path) == OK else "保存失败"

func _refresh() -> void:
	_refresh_queued = false
	if not _left:
		return
	if is_instance_valid(_left_scroll):
		_left_scroll_y = _left_scroll.scroll_vertical
	_clear(_left)
	_clear(_entries)
	_clear(_details)
	_clear(_actions)
	_clear(_chips)
	_stat_labels.clear()
	_left_scroll = null
	_detail_scroll.scroll_vertical = 0
	var inventory_mode := current_page==0 and _equipment_tab==1
	_inventory_book.visible = inventory_mode
	_search = _inventory_book.search if inventory_mode else _legacy_search
	for control in [_left,_entries,_detail_scroll,_actions,_title,_count,_detail_name,_detail_icon,_legacy_search,_chips]:
		control.visible = not inventory_mode
	_sync_bottom_bars()
	_title.text = "背包" if current_page == 0 else "技能"
	for tab in 3:
		var active := (tab == _equipment_tab and current_page == 0) or (tab == 2 and current_page == 1)
		_tabs[tab].set_pressed_no_signal(active)
		var skin := _skin("controls/tab-active.png" if active else "controls/tab.png")
		_tabs[tab].add_theme_stylebox_override("normal", skin)
		_tabs[tab].add_theme_stylebox_override("pressed", skin)
		_tabs[tab].add_theme_stylebox_override("hover", _skin("controls/tab-active.png"))
		_tabs[tab].add_theme_color_override("font_color", INK if active else PAPER)
		_tabs[tab].add_theme_color_override("font_pressed_color", INK if active else PAPER)
		_tabs[tab].add_theme_color_override("font_hover_color", INK)
	if inventory_mode:
		_inventory_book.refresh()
		_refresh_hud()
		_motion.after_refresh()
		_fit_window.call_deferred()
		return
	for index in _filter.item_count:
		var chip := _journal_button(_filter.get_item_text(index), _filter_changed.bind(index), true)
		chip.add_theme_font_size_override("font_size", _font_size(20 if chip.text.length() > 2 else 24))
		var active := index == _filter.selected
		chip.add_theme_stylebox_override("normal", _skin("controls/category-active.png" if active else "controls/category.png"))
		chip.add_theme_color_override("font_color", PAPER if active else INK)
		_at(chip, Rect2(1048 + index * 108, 252, 100, 56), _chips)
	_refresh_equipment() if current_page == 0 else _refresh_skills()
	_refresh_hud()
	_motion.after_refresh()
	_fit_window.call_deferred()

func _tile(icon: Texture2D, selected := false, framed := false) -> LoadoutTile:
	var tile := LoadoutTile.new()
	tile.audio = _audio
	tile.loadout = state
	tile.drag_icon = icon
	tile.add_theme_stylebox_override("normal", _active if selected else (_normal if framed else StyleBoxEmpty.new()))
	for state_name in ["hover", "pressed", "focus"]:
		tile.add_theme_stylebox_override(state_name, _active)
	_motion.attach_button(tile)
	return tile

func _refresh_equipment() -> void:
	_text("人物", Rect2(225, 180, 235, 78), 62, _left)
	_text("在旅途中\n慢慢成长。", Rect2(225, 279, 238, 70), 25, _left)
	var size := Vector2(306, 690) * portrait_scale
	_at(_icon(portrait_texture), Rect2(Vector2(503, 525) - size * 0.5, size), _left)
	var rects := [Rect2(756, 193, 193, 205), Rect2(769, 410, 179, 220), Rect2(757, 645, 191, 214)]
	for slot in 3:
		var id := state.get_equipped_id(slot)
		var entry := catalog.get_equipment(id)
		var tile := _tile(entry.icon if entry else null)
		tile.equipment_slot = slot
		tile.add_theme_stylebox_override("normal", _outline(Color("719caa")) if entry and id == selected_equipment else StyleBoxEmpty.new())
		for style in ["hover", "pressed", "focus"]:
			tile.add_theme_stylebox_override(style, _outline(Color("559bbb")))
		if entry:
			tile.payload = {"kind": "equipment", "id": id}
			tile.pressed.connect(_select_equipment.bind(id))
		tile.dropped.connect(func(data): _ui_action(state.equip.bind(data.id), &"equip"))
		_at(tile, rects[slot], _left)
		var name_height := _font_size(21) + 2
		var name_y: float = rects[slot].size.y - 20 - name_height
		var caption_height := _font_size(24) + 2
		var caption_y: float = name_y - caption_height - 4
		_at(_icon(entry.icon if entry else null), Rect2(22, 12, rects[slot].size.x - 44, caption_y - 20), tile)
		var caption := _text(SLOT_NAMES[slot], Rect2(18, caption_y, rects[slot].size.x - 36, caption_height), 24, tile, INK, true)
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		var name := _text(entry.display_name if entry else "未穿戴", Rect2(18, name_y, rects[slot].size.x - 36, name_height), 21, tile, FADED, true)
		name.autowrap_mode = TextServer.AUTOWRAP_OFF
		name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tile.tooltip_text = SLOT_NAMES[slot] + ("：" + entry.display_name if entry else "：未穿戴") + "\n拖入对应装备，点击查看详情。"
	var attributes := state.get_character_attributes()
	for index in 3:
		var key: String = ["health", "attack", "defense"][index]
		var x := 261 + index * 220
		_picture("symbols/" + ["heart", "sword", "shield"][index] + ".png", Rect2(x, 899, 39, 40), _left)
		_text(_attribute_label(key), Rect2(x + 48, 900, 150, 32), 25, _left)
		_stat_labels[key] = _text(_number(_motion.numbers.get(key, attributes.get(key, 0.0))), Rect2(x + 48, 935, 150, 37), 30, _left)
	_text("装备搭配，记录每一次成长。", Rect2(415, 991, 464, 33), 23, _left, FADED)
	var matches: Array[EquipmentDefinition] = []
	for entry in catalog.equipment:
		if state.owns_equipment(entry.id) and (_filter.selected == 0 or entry.slot == _filter.selected - 1) and _matches_search(entry.display_name, entry.description):
			matches.append(entry)
	var pages := maxi(1, ceili(matches.size() / 16.0))
	_inventory_page = clampi(_inventory_page, 0, pages - 1)
	_count.text = "%d 件装备" % state.get_owned_equipment().size()
	for index in mini(16, maxi(0, matches.size() - _inventory_page * 16)):
		var entry := matches[_inventory_page * 16 + index]
		var tile := _tile(entry.icon, entry.id == selected_equipment)
		tile.payload = {"kind": "equipment", "id": entry.id}
		tile.pressed.connect(_select_equipment.bind(entry.id))
		tile.gui_input.connect(_equipment_double_click.bind(entry.id))
		_at(tile, Rect2(1038 + 118 * (index % 4), 328 + 142 * (index / 4), 111, 136), _entries)
		_at(_icon(entry.icon), Rect2(8, 8, 95, 119), tile)
		var worn := state.get_equipped_id(entry.slot) == entry.id
		if worn:
			_text("◆", Rect2(6, 2, 24, 28), 19, tile, GILT)
		tile.tooltip_text = entry.display_name + "\n" + SLOT_NAMES[entry.slot] + (" · 已装备" if worn else "") + "\n双击穿戴，或拖到对应槽位。"
	if matches.is_empty():
		_text("没有匹配的装备", Rect2(1060, 519, 416, 93), 30, _entries, FADED, true)
	if pages > 1:
		var previous := _journal_button("‹", _inventory_turn.bind(-1), true, true, &"page_turn")
		previous.disabled = _inventory_page == 0
		_at(previous, Rect2(1068, 909, 75, 48), _entries)
		_text("%d / %d" % [_inventory_page + 1, pages], Rect2(1161, 919, 190, 35), 26, _entries, INK, true)
		var next := _journal_button("›", _inventory_turn.bind(1), true, true, &"page_turn")
		next.disabled = _inventory_page == pages - 1
		_at(next, Rect2(1380, 909, 75, 48), _entries)
	_equipment_details()

func _inventory_turn(direction: int) -> void:
	_inventory_page += direction
	_queue_refresh()

func _select_equipment(id: String) -> void:
	_audio.play(&"select")
	selected_equipment = id
	_queue_refresh()

func _equipment_double_click(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
		_ui_action(state.equip.bind(id), &"equip")

func _equipment_details() -> void:
	_detail_scroll.position.y = 579
	_detail_scroll.size.y = 234
	_actions.position.y = 832
	var entry := catalog.get_equipment(selected_equipment)
	_detail_icon.texture = entry.icon if entry else null
	_detail_name.text = entry.display_name if entry else "装备详情"
	if not entry:
		_description("选择装备，查看属性与穿戴后的变化。")
		return
	_description(entry.description)
	for key in entry.attribute_bonuses:
		_details.add_child(_journal_label("%s  +%s" % [_attribute_label(key), _number(entry.attribute_bonuses[key])], 25))
	for id in entry.skill_bonuses:
		_details.add_child(_journal_label("%s  +%s%%" % [catalog.get_skill(id).display_name, _number(entry.skill_bonuses[id])], 24, POSITIVE))
	var worn := state.get_equipped_id(entry.slot) == entry.id
	if not worn:
		_details.add_child(_journal_label("穿戴后的变化", 25, GILT))
		var before := state.get_character_attributes()
		var after := state.preview_character_attributes(entry.id)
		var keys: Array = before.keys()
		for key in after:
			if key not in keys:
				keys.append(key)
		var differences := 0
		for key in keys:
			var change: float = after.get(key, 0.0) - before.get(key, 0.0)
			if is_zero_approx(change):
				continue
			differences += 1
			var difference := ("+" if change > 0 else "") + _number(change)
			_details.add_child(_journal_label("%s  %s → %s (%s)" % [_attribute_label(key), _number(before.get(key, 0.0)), _number(after.get(key, 0.0)), difference], 23, POSITIVE if change > 0 else Color("a14736")))
		if differences == 0:
			_details.add_child(_journal_label("角色属性保持不变", 23, FADED))
	_actions.add_child(_journal_button("卸下装备" if worn else "穿戴装备", state.unequip.bind(entry.slot) if worn else state.equip.bind(entry.id), false, true, &"equip"))

func _refresh_skills() -> void:
	if wave_session:
		_refresh_session_skills()
		return
	_picture("controls/details.png", Rect2(211, 172, 744, 684), _left, true)
	_text("技能装配", Rect2(263, 195, 630, 65), 51, _left)
	_text("拖入已学习的技能 · 移动时交换位置", Rect2(265, 258, 617, 42), 26, _left, FADED)
	_left_scroll = _scroll(Rect2(260, 311, 662, 511), _left)
	var assignments := GridContainer.new()
	assignments.columns = 2
	assignments.add_theme_constant_override("h_separation", 30)
	assignments.add_theme_constant_override("v_separation", 22)
	_left_scroll.add_child(assignments)
	var slots := state.get_skill_slots()
	# 两行槽位需要同时容纳图标和说明，较大字号时略缩图标区。
	var tile_height := minf(202, floorf((_left_scroll.size.y - 22) * 0.5) - 8 - (_font_size(27) + 2))
	for slot in slots.size():
		var holder := VBoxContainer.new()
		holder.custom_minimum_size.x = 295
		holder.add_theme_constant_override("separation", 8)
		var entry := catalog.get_skill(slots[slot])
		var tile := _tile(entry.icon if entry else null, entry != null and entry.id == selected_skill, true)
		tile.custom_minimum_size = Vector2(295, tile_height)
		tile.skill_slot = slot
		if entry:
			tile.payload = {"kind": "skill", "id": entry.id}
			tile.pressed.connect(_select_skill.bind(entry.id))
		tile.dropped.connect(func(data): _ui_action(state.assign_skill.bind(data.id, slot), &"item_drop"))
		var icon := _icon(entry.icon if entry else null)
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 30
		icon.offset_right = -30
		icon.offset_top = 18
		icon.offset_bottom = -18
		tile.add_child(icon)
		tile.tooltip_text = "拖入已学习的技能；拖到已占用槽位会交换位置。"
		holder.add_child(tile)
		holder.add_child(_journal_label("%d · %s" % [slot + 1, entry.display_name if entry else "未装配"], 27, FADED))
		assignments.add_child(holder)
	_left_scroll.set_deferred("scroll_vertical", _left_scroll_y)
	_text("已学习 %d / %d" % [state.get_learned_skills().size(), catalog.skills.size()], Rect2(293, 906, 591, 44), 31, _left)
	_text("选择技能，记录你的冒险方式。", Rect2(354, 991, 551, 34), 23, _left, FADED)
	_count.text = "%d 个技能" % catalog.skills.size()
	_picture("controls/details.png", Rect2(1034, 326, 475, 568), _entries, true)
	var scroll := _scroll(Rect2(1055, 344, 438, 529), _entries)
	var library := VBoxContainer.new()
	library.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	library.add_theme_constant_override("separation", 12)
	scroll.add_child(library)
	var shown := 0
	for entry in catalog.skills:
		var learned := state.has_learned_skill(entry.id)
		if (_filter.selected == 1 and not learned) or (_filter.selected == 2 and learned) or not _matches_search(entry.display_name, entry.description):
			continue
		shown += 1
		var tile := _tile(entry.icon, entry.id == selected_skill, true)
		tile.custom_minimum_size = Vector2(410, 116)
		if learned:
			tile.payload = {"kind": "skill", "id": entry.id}
		tile.pressed.connect(_select_skill.bind(entry.id))
		tile.gui_input.connect(_skill_double_click.bind(entry.id))
		tile.tooltip_text = entry.display_name + "\n双击学习；已学习技能可拖入装配槽。"
		_at(_icon(entry.icon), Rect2(10, 10, 94, 96), tile)
		_text(entry.display_name, Rect2(123, 17, 265, 42), 34, tile)
		_text("已学习" if learned else "尚未学习", Rect2(123, 66, 265, 34), 26, tile, FADED)
		library.add_child(tile)
	if shown == 0:
		library.add_child(_journal_label("没有匹配的技能", 28, FADED))
	_skill_details()

func _select_skill(id: String) -> void:
	_audio.play(&"select")
	selected_skill = id
	_queue_refresh()

func _skill_double_click(event: InputEvent, id: String) -> void:
	if wave_session: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
		_ui_action(state.learn_skill.bind(id), &"confirm")

func _skill_details() -> void:
	if wave_session:
		_session_skill_details()
		return
	var entry := catalog.get_skill(selected_skill)
	_detail_icon.texture = entry.icon if entry else null
	_detail_name.text = entry.display_name if entry else "技能详情"
	var many_slots := state.get_skill_slots().size() > 4
	_actions.position.y = 738 if many_slots else 787
	_detail_scroll.position.y = 579
	_detail_scroll.size.y = _actions.position.y - 595
	if not entry:
		_description("选择技能查看说明，学习后即可装配。")
		return
	_description(entry.description)
	for key in state.get_skill_values(entry.id):
		var suffix := " 秒" if key == "cooldown" else ""
		_details.add_child(_journal_label("%s  %s%s" % [catalog.skill_value_labels.get(key, key), _number(state.get_skill_values(entry.id)[key]), suffix], 25))
	_details.add_child(_journal_label("装备加成  +%s%%" % _number(state.get_skill_bonus(entry.id)), 24, POSITIVE))
	if not state.has_learned_skill(entry.id):
		_actions.add_child(_journal_button("学习技能", state.learn_skill.bind(entry.id), false, true, &"confirm"))
	else:
		_actions.add_child(_journal_label("装配到槽位", 24, GILT))
		var row := GridContainer.new()
		row.columns = mini(4, state.get_skill_slots().size())
		row.add_theme_constant_override("h_separation", 8)
		row.add_theme_constant_override("v_separation", 8)
		for slot in state.get_skill_slots().size():
			var button := _journal_button(str(slot + 1), state.assign_skill.bind(entry.id, slot), true, true, &"item_drop")
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			button.custom_minimum_size.x = 68
			row.add_child(button)
		_actions.add_child(row)
		var assigned := state.get_skill_slots().find(entry.id)
		if assigned >= 0:
			_actions.add_child(_journal_button("移出槽位 %d" % (assigned + 1), state.unassign_skill.bind(assigned), true, true, &"cancel"))

func _description(words: String) -> void:
	_details.add_child(_journal_label(words, 23, FADED))

func _matches_search(title: String, description: String) -> bool:
	var query := _search.text.strip_edges().to_lower()
	return query.is_empty() or query in title.to_lower() or query in description.to_lower()

func _attribute_label(key: String) -> String:
	return catalog.attribute_labels.get(key, key)

func _number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value

func _refresh_hud() -> void:
	if wave_session:
		_hud.set_run_slots(wave_session.get_run_skill_slots())
	else:
		_hud.set_slots(state.get_skill_slots(), catalog)

func _refresh_session_skills() -> void:
	_picture("controls/details.png", Rect2(211, 172, 744, 684), _left, true)
	_text("本局自动技能", Rect2(263, 195, 630, 65), 51, _left)
	_text("开战选择初始技能，升级学习或强化", Rect2(265, 258, 617, 42), 26, _left, FADED)
	_left_scroll = _scroll(Rect2(260, 311, 662, 511), _left)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.custom_minimum_size.x = 600.0
	content.add_theme_constant_override("separation", 24)
	_left_scroll.add_child(content)
	var slots: Array[Dictionary] = wave_session.get_run_skill_slots()
	if slots.is_empty(): content.add_child(_journal_label("尚未选择技能，按 %s 开始挑战时选择。" % OS.get_keycode_string(wave_session.interact_key), 28))
	for slot in slots:
		content.add_child(_journal_label("%s · Lv.%d / %d\n%s" % [slot.name, slot.level, slot.max_level, slot.description], 28))
	content.add_child(_journal_label("当前第 %d 波\n已完成 %d 波 · 击败 %d 个敌人" % [wave_session.wave, wave_session.completed_waves, wave_session.kills], 28))
	content.add_child(_journal_label("清波后直接休整，准备好后按 %s 继续。" % OS.get_keycode_string(wave_session.interact_key), 25, FADED))
	_text("本局技能与等级", Rect2(293, 906, 591, 44), 31, _left)
	_text("升级选择立即生效，无需重复学习或装配。", Rect2(300, 991, 630, 34), 23, _left, FADED)
	_count.text = "%d 种技能" % slots.size()
	_picture("controls/details.png", Rect2(1034, 326, 475, 568), _entries, true)
	_text("本局技能来自实际战斗组件。\n\n后续继续扩充技能与增益；这里不免费学习目录技能。", Rect2(1080, 375, 390, 330), 28, _entries, FADED)
	_session_skill_details()

func _session_skill_details() -> void:
	var slots: Array[Dictionary] = wave_session.get_run_skill_slots()
	_detail_icon.texture = slots[0].icon if not slots.is_empty() else null
	_detail_name.text = "%s · Lv.%d" % [slots[0].name, slots[0].level] if not slots.is_empty() else "暂无技能"
	_detail_scroll.position.y = 579
	_detail_scroll.size.y = 300
	_description(slots[0].description if not slots.is_empty() else "开始战斗时选择一个初始技能，升级时可学习其它技能或强化已有技能。")

func _open_skill_from_hud(id: String) -> void:
	if not player_access_enabled: return
	selected_skill = id
	open_menu(1)
