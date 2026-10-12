class_name InventoryBookPage
extends Control

const ART := "res://assets/meowa/ui/inventory/"
const CATEGORIES := ["全部","装备","工具","材料","种植","消耗"]
@export_range(4,8,1) var columns := 6
@export_range(3,6,1) var rows := 5
var state: LoadoutState
var search: LineEdit
var selected_item := "tomato_seed"
var _host: CanvasLayer
var _filter := 0
var _page := 0
var _grid := Control.new()
var _category_buttons: Array[Button] = []
var _name: Label
var _type: Label
var _description: Label
var _quantity: Label
var _capacity := Label.new()
var _page_label := Label.new()
var _hero: TextureRect
var _actions := VBoxContainer.new()
var _previous: Button
var _next: Button

func build(host: CanvasLayer) -> void:
	_host = host
	state = host.state
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 沿用原手帐底图，只用原纸面的裁片遮住旧页内固定装饰。
	for rect in [Rect2(211,172,744,796),Rect2(1030,270,830,700)]:
		var paper := _image(load(ART+"page-paper.png"))
		paper.stretch_mode = TextureRect.STRETCH_SCALE
		paper.material = ShaderMaterial.new()
		(paper.material as ShaderMaterial).shader = load("res://shaders/inventory_paper.gdshader")
		_at(paper,rect)
	_at(_label("背包",52),Rect2(235,185,260,70))
	search = LineEdit.new()
	search.placeholder_text = "搜索物品"
	search.add_theme_font_size_override("font_size",_host._font_size(24))
	var search_skin := skin("search",18)
	search_skin.set_content_margin(SIDE_LEFT,62)
	for style in ["normal","focus"]: search.add_theme_stylebox_override(style,search_skin)
	search.text_changed.connect(func(_text): _page=0; refresh.call_deferred())
	_at(search,Rect2(548,218,390,60))
	for category in CATEGORIES.size():
		var button := _button(CATEGORIES[category],func(): _filter=category; _page=0; refresh.call_deferred(),true)
		_at(button,Rect2(235+category*117,291,108,52))
		_category_buttons.append(button)
	_at(_grid,Rect2(225,358,720,535))
	_at(_image(load(ART+"controls/backpack.png")),Rect2(235,925,34,40))
	_at(_capacity,Rect2(282,925,430,45))
	_capacity.add_theme_font_size_override("font_size",_host._font_size(22))
	var sort := _button("整理",state.sort_inventory,false,&"confirm")
	_at(sort,Rect2(775,918,170,58))
	_previous = _button("‹",func(): _page-=1; refresh.call_deferred(),true,&"page_turn")
	_next = _button("›",func(): _page+=1; refresh.call_deferred(),true,&"page_turn")
	_at(_previous,Rect2(580,1000,50,42))
	_at(_page_label,Rect2(632,1000,160,42))
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_at(_next,Rect2(795,1000,50,42))
	_name = _label("",48)
	_at(_name,Rect2(1140,208,560,72))
	_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_type = _label("",25,LoadoutUI.FADED)
	_at(_type,Rect2(1140,284,570,45))
	_hero = _image(null)
	_at(_hero,Rect2(1185,340,560,346))
	_description = _label("",26,LoadoutUI.INK)
	_at(_description,Rect2(1140,706,570,118))
	_quantity = _label("",26)
	_at(_quantity,Rect2(1140,830,570,45))
	_at(_actions,Rect2(1140,890,570,125))
	_actions.add_theme_constant_override("separation",8)
	refresh()

func skin(file: String, margin := 12) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(ART+"controls/"+file+".png")
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:
		style.set_texture_margin(side,margin)
		style.set_content_margin(side,margin)
	return style

func _at(control: Control, rect: Rect2, parent: Control = null) -> void:
	control.position = rect.position
	control.size = rect.size
	(parent if parent else self).add_child(control)

func _image(texture: Texture2D) -> TextureRect:
	var image: TextureRect = _host._icon(texture)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image

func _label(text: String, font_size: int, color := LoadoutUI.INK) -> Label:
	return _host._journal_label(text,font_size,color)

func _button(text: String, callback: Callable, small := false, cue: StringName = &"select") -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 54 if small else 62
	button.add_theme_font_size_override("font_size",_host._font_size(23 if small else 26))
	for style in ["normal","disabled"]:
		button.add_theme_stylebox_override(style,skin("category" if small else "button"))
	for style in ["hover","pressed","focus"]:
		button.add_theme_stylebox_override(style,skin("category-active" if small else "button"))
	button.add_theme_color_override("font_color",LoadoutUI.INK if small else LoadoutUI.PAPER)
	button.add_theme_color_override("font_hover_color",LoadoutUI.PAPER)
	button.add_theme_color_override("font_pressed_color",LoadoutUI.PAPER)
	button.pressed.connect(_host._ui_action.bind(callback,cue))
	_host._motion.attach_button(button)
	return button

func select_item(id: String) -> void:
	_host._audio.play(&"select")
	selected_item = id
	refresh.call_deferred()

func refresh() -> void:
	if not state or not search: return
	_host._clear(_grid)
	_host._clear(_actions)
	var ids := state.get_inventory_ids()
	var matches: Array[String] = []
	for id in ids:
		var entry := state.catalog.get_inventory_entry(id)
		if (_filter == 0 or state.catalog.get_item_category(id) == _filter-1) and (search.text.is_empty() or search.text.to_lower() in entry.display_name.to_lower() or search.text.to_lower() in entry.description.to_lower()):
			matches.append(id)
	if selected_item not in ids:
		selected_item = matches[0] if not matches.is_empty() else ""
	for index in _category_buttons.size():
		_category_buttons[index].add_theme_stylebox_override("normal",skin("category-active" if _filter == index else "category"))
		_category_buttons[index].add_theme_color_override("font_color",LoadoutUI.PAPER if _filter == index else LoadoutUI.INK)
	var page_size := columns * rows
	var pages := maxi(1,ceili(matches.size()/float(page_size)))
	_page = clampi(_page,0,pages-1)
	var spacing := Vector2(12,12)
	var cell := (_grid.size - spacing*Vector2(columns-1,rows-1))/Vector2(columns,rows)
	for index in page_size:
		var entry_index := _page*page_size+index
		var id := matches[entry_index] if entry_index < matches.size() else ""
		var entry := state.catalog.get_inventory_entry(id)
		var tile := LoadoutTile.new()
		tile.audio = _host._audio
		tile.name = "InventorySlot%d" % index
		tile.loadout = state
		tile.add_theme_stylebox_override("normal",skin("slot-active" if id == selected_item and not id.is_empty() else "slot",8))
		for style in ["hover","pressed","focus"]:
			tile.add_theme_stylebox_override(style,skin("slot-active",8))
		_at(tile,Rect2(Vector2(index%columns,index/columns)*(cell+spacing),cell),_grid)
		if not entry:
			tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
			continue
		tile.drag_icon = entry.icon
		tile.payload = {"kind":"equipment" if entry is EquipmentDefinition else "item","id":id}
		tile.pressed.connect(select_item.bind(id))
		tile.gui_input.connect(func(event):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
				if entry is EquipmentDefinition: _host._ui_action(state.equip.bind(id),&"equip")
				else: _host._ui_action(state.assign_item.bind(id,state.active_quick_slot),&"item_drop"))
		tile.tooltip_text = entry.display_name+"\n"+entry.description+"\n拖到物品快捷栏，数量与背包共用。"
		_at(_image(entry.icon),Rect2(Vector2.ONE*10,cell-Vector2.ONE*20),tile)
		if entry is ItemDefinition and entry.stackable:
			var amount := _label(str(state.get_quantity(id)),24,Color("fff6df"))
			amount.name = "Quantity"
			amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			amount.add_theme_color_override("font_outline_color",Color("333020"))
			amount.add_theme_constant_override("outline_size",3)
			_at(amount,Rect2(8,cell.y-36,cell.x-16,32),tile)
		if state.is_favorite(id): _at(_label("★",16,LoadoutUI.GILT),Rect2(8,2,30,24),tile)
	_capacity.text = "%d种物品 · 每页%d格" % [ids.size(),page_size]
	_page_label.text = "%d / %d" % [_page+1,pages]
	for control in [_previous,_next,_page_label]: control.visible = pages>1
	_previous.disabled = _page==0
	_next.disabled = _page==pages-1
	if matches.is_empty():
		_at(_label("没有匹配的物品",28,LoadoutUI.FADED),Rect2(170,240,430,60),_grid)
	_refresh_details()

func _refresh_details() -> void:
	var entry := state.catalog.get_inventory_entry(selected_item)
	_name.text = entry.display_name if entry else "物品详情"
	_hero.texture = entry.illustration if entry is ItemDefinition and entry.illustration else (entry.icon if entry else null)
	_description.text = entry.description if entry else "选择物品，查看用途与数量。"
	_quantity.text = "持有数量                         %d" % state.get_quantity(selected_item) if entry else ""
	_type.text = CATEGORIES[state.catalog.get_item_category(selected_item)+1]+(" · 可堆叠" if entry is ItemDefinition and entry.stackable else "") if entry else ""
	if not entry: return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",18)
	var assign := _button("加入快捷栏 %d" % (state.active_quick_slot+1),func(): return state.assign_item(selected_item,state.active_quick_slot),false,&"item_drop")
	assign.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(assign)
	var favorite := Button.new()
	favorite.custom_minimum_size = Vector2(66,66)
	favorite.tooltip_text = "取消收藏" if state.is_favorite(selected_item) else "收藏物品"
	for style in ["normal","hover","pressed","focus"]: favorite.add_theme_stylebox_override(style,skin("favorite",8))
	favorite.modulate = Color(1.12,1.08,0.8) if state.is_favorite(selected_item) else Color.WHITE
	favorite.pressed.connect(_host._ui_action.bind(state.toggle_favorite.bind(selected_item),&"confirm"))
	row.add_child(favorite)
	_actions.add_child(row)
	if entry is ItemDefinition and entry.farm_action != ItemDefinition.FarmAction.NONE:
		var take := _button("拿起使用", _host.take_inventory_item.bind(entry.id))
		take.tooltip_text = "选中这个物品并返回地图。未绑定时放入空快捷槽；槽位已满则使用当前槽。"
		_actions.add_child(take)
	if entry is EquipmentDefinition:
		var worn: bool = state.get_equipped_id(entry.slot)==entry.id
		_actions.add_child(_button("卸下装备" if worn else "穿戴装备",state.unequip.bind(entry.slot) if worn else state.equip.bind(entry.id),false,&"equip"))
