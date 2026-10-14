extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("FAIL: ",label)

func settle() -> void:
	for frame in 6: await process_frame

func run() -> void:
	var catalog: LoadoutCatalog = load("res://data/rpg/loadout_catalog.tres")
	check(catalog.validation_errors().is_empty(),"Inventory catalog is valid")
	var state := LoadoutState.new(catalog)
	check(state.add_item("tomato_seed",20) and state.add_item("hoe"),"Add a stack and a non-stackable tool")
	check(not state.add_item("hoe") and not state.add_item("missing") and not state.add_item("wood",-1),"Reject duplicate tool, unknown item and invalid quantity")
	check(state.assign_item("tomato_seed",3),"Assign seed stack to the quickbar")
	check(state.remove_item("tomato_seed",2) and state.get_quantity(state.get_quick_slots()[3])==18,"Quickbar references the same inventory quantity")
	check(not state.remove_item("tomato_seed",19) and state.get_quantity("tomato_seed")==18,"No overdraft or partial debit")
	check(state.assign_item("hoe",0) and state.assign_item("tomato_seed",0),"Moving assigned items swaps occupied slots")
	check(state.get_quick_slots()[0]=="tomato_seed" and state.get_quick_slots()[3]=="hoe","Bindings swap without copying items")
	state.toggle_favorite("tomato_seed")
	state.select_quick_slot(3)
	var snapshot := state.export_state()
	var restored := LoadoutState.new(catalog)
	check(restored.import_state(snapshot) and restored.export_state()==snapshot,"Quantities, quickbar, active slot and favorites roundtrip")
	var damaged := snapshot.duplicate(true)
	damaged.items.tomato_seed = -1
	check(not restored.import_state(damaged) and restored.export_state()==snapshot,"Malformed new data cannot partially replace saved state")
	check(state.remove_item("tomato_seed",18) and state.get_quick_slots()[0].is_empty() and not state.is_favorite("tomato_seed"),"Depletion removes stale quickbar/favorite references")
	var legacy := snapshot.duplicate(true)
	legacy.version=1
	for field in ["items","quick_slots","favorites","active_quick_slot"]: legacy.erase(field)
	legacy.owned_equipment=["sword","armor"]
	legacy.equipped=["sword","armor",""]
	legacy.learned_skills=["fire"]
	legacy.skill_slots=["fire","","",""]
	legacy.training.points=7
	legacy.training.levels.attack=2
	check(restored.import_state(legacy) and restored.get_equipped_id(0)=="sword" and restored.has_learned_skill("fire") and restored.training_points==7 and restored.get_training_level("attack")==2 and not restored.inventory_initialized,"Legacy equipment/skills/training survive migration")
	var ui: LoadoutUI = load("res://scenes/ui/loadout_ui.tscn").instantiate()
	ui.save_enabled=false
	ui.motion_enabled=false
	root.add_child(ui)
	await settle()
	check(ui.state.get_quantity("tomato_seed")==20 and ui._item_bar._slots.get_child_count()==8,"Native UI initializes demo inventory and eight quick slots")
	ui.open_menu()
	await settle()
	check(ui._inventory_book.visible and not ui._left.visible and not paused,"Backpack has an independent page and keeps the world live")
	check(ui._inventory_book._grid.get_child_count()==30,"Six by five reusable item slots")
	var seed_tile: LoadoutTile
	for tile in ui._inventory_book._grid.get_children():
		if tile is LoadoutTile and tile.payload.get("id")=="tomato_seed": seed_tile=tile
	var target: LoadoutTile = ui._item_bar._slots.get_child(6)
	check(seed_tile!=null and target._can_drop_data(Vector2.ZERO,seed_tile.payload),"Native drag target accepts an owned inventory item")
	target._drop_data(Vector2.ZERO,seed_tile.payload)
	await settle()
	check(ui.state.get_quick_slots()[6]=="tomato_seed" and ui.state.get_quantity("tomato_seed")==20,"Drop changes only the binding")
	ui.state.remove_item("tomato_seed",1)
	await settle()
	check(ui._item_bar._slots.get_child(6).get_node("Quantity").text=="19" and ui._inventory_book._quantity.text.ends_with("19"),"Stack changes refresh quickbar and detail quantities")
	ui._inventory_book.search.text="番茄种子"
	ui._inventory_book.search.text_changed.emit(ui._inventory_book.search.text)
	await settle()
	var shown := 0
	for tile in ui._inventory_book._grid.get_children():
		if tile is LoadoutTile and not tile.payload.is_empty(): shown+=1
	check(shown==1,"Generic inventory search works")
	ui._inventory_book.search.text=""
	ui._inventory_book.search.text_changed.emit("")
	ui._inventory_book._category_buttons[2].pressed.emit()
	await settle()
	shown=0
	for tile in ui._inventory_book._grid.get_children():
		if tile is LoadoutTile and not tile.payload.is_empty():
			shown+=1
			check(ui.catalog.get_item_category(tile.payload.id)==ItemDefinition.Category.TOOL,"Tool filter excludes other categories")
	check(shown==3,"All three tools are available")
	ui._tab_pressed(0)
	await settle()
	check(ui._left.visible and not ui._inventory_book.visible,"Character and equipment page remains available")
	ui._tab_pressed(2)
	await settle()
	check(ui.current_page==1 and not ui._inventory_book.visible,"Existing skills page remains available")
	ui.close_menu()
	await settle()
	check(ui._hud.visible and ui._item_bar.visible and not ui._hud.show_skill_icons,"The existing empty skill HUD remains intact")
	root.size=Vector2i(640,400)
	root.content_scale_size=Vector2i(640,400)
	ui._hud.update_layout()
	ui._item_bar.update_layout()
	await settle()
	check(not ui._item_bar.get_global_rect().intersects(ui._hud.get_global_rect()),"A narrow window keeps item and skill bars separate")
	ui.free()
	await settle()
	print("Inventory: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
