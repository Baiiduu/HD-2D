extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(25.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("FAIL: ", label)

func run() -> void:
	var catalog: LoadoutCatalog = load("res://data/loadout_catalog.tres")
	var state := LoadoutState.new(catalog)
	state.add_item("tomato_seed", 2)
	state.assign_item("tomato_seed", 3)
	state.toggle_favorite("tomato_seed")
	var cell := Vector2i(-2, 4)
	check(not state.plant_farm_plot("test", cell, "tomato_seed") and state.get_quantity("tomato_seed") == 2, "Untilled soil rejects planting without consuming seeds")
	check(not state.water_farm_plot("test", cell), "Untilled soil rejects watering")
	check(state.till_farm_plot("test", cell) and not state.till_farm_plot("test", cell), "Till once without resetting an existing plot")
	check(not state.plant_farm_plot("test", cell, "wood"), "Materials cannot be planted as seeds")
	var emissions: Array[Dictionary] = []
	var observe := func(): emissions.append(state.export_state())
	state.changed.connect(observe)
	check(state.plant_farm_plot("test", cell, "tomato_seed"), "Plant a configured seed")
	check(emissions.size() == 1 and emissions[0].items.tomato_seed == 1 and emissions[0].farming.test["-2,4"].seed == "tomato_seed", "Stock debit and planting are committed in one complete notification")
	check(not state.plant_farm_plot("test", cell, "tomato_seed") and state.get_quantity("tomato_seed") == 1, "Double sowing cannot debit inventory")
	check(state.water_farm_plot("test", cell) and not state.water_farm_plot("test", cell), "Water a plot once and retain its crop")
	var second := cell + Vector2i.RIGHT
	state.till_farm_plot("test", second)
	state.water_farm_plot("test", second)
	check(state.plant_farm_plot("test", second, "tomato_seed") and state.get_farm_plot("test", second).watered, "Sowing on already-watered soil retains wetness")
	check(state.get_quantity("tomato_seed") == 0 and state.get_quick_slots()[3].is_empty() and not state.is_favorite("tomato_seed"), "Exhausted seeds clear stale shortcuts and favorite references")
	var saved := state.export_state()
	var restored := LoadoutState.new(catalog)
	check(restored.import_state(saved) and restored.export_state() == saved, "Plots, seed debit and watering roundtrip together")
	var damaged := saved.duplicate(true)
	damaged.farming.test["-2,4"].watered = "yes"
	check(not restored.import_state(damaged) and restored.export_state() == saved, "Invalid farm data cannot partially replace a valid save")
	var legacy := saved.duplicate(true)
	legacy.version = 2
	legacy.erase("farming")
	check(restored.import_state(legacy) and restored.inventory_initialized and restored.get_quantity("tomato_seed") == 0 and restored.get_farm_plots("test").is_empty(), "Version 2 upgrade preserves depleted stock and initializes only farmland")
	check(state.get_farm_plots("other").is_empty(), "Each map has independent plots")
	emissions.clear()
	check(state.restore_farm_plot("test", cell) and state.get_farm_plot("test", cell).is_empty() and state.get_quantity("tomato_seed") == 1, "Restore removes planting and watering while refunding one seed")
	check(emissions.size() == 1 and emissions[0].items.tomato_seed == 1 and not emissions[0].farming.test.has("-2,4"), "Refund and plot removal are saved in one complete transaction")
	check(not state.restore_farm_plot("test", cell) and state.get_quantity("tomato_seed") == 1, "Repeated restoration cannot create extra seeds")
	check(state.restore_farm_plot("test", second, false) and state.get_quantity("tomato_seed") == 1, "Refund can be disabled without leaving a stale plot")
	check(restored.import_state(state.export_state()) and restored.get_farm_plots("test").is_empty() and restored.get_quantity("tomato_seed") == 1, "A restored save cannot recreate cancelled farmland")
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	var terrain_source_path: String = world.get_node("Homestead").data.resource_path
	var terrain_source_hash := FileAccess.get_sha256(terrain_source_path)
	var original_paints: PackedByteArray = world.get_node("Homestead").data.paints.duplicate()
	var ui: LoadoutUI = world.get_node("LoadoutUI")
	ui.save_enabled = false
	ui.motion_enabled = false
	root.add_child(world)
	await create_timer(0.6).timeout
	var farm: Farming = world.get_node("Farming")
	farm.action_interval = 0.0
	var terrain: Terrain = world.get_node("Homestead")
	var player: Player = world.get_node("Player")
	var candidates: Array[Vector2i] = []
	for z in range(1, 6):
		for x in range(-4, 2):
			var point := Vector2i(x, z)
			if farm.action_error(point).is_empty(): candidates.append(point)
	check(candidates.size() >= 2, "The real spawn map has reachable unblocked grass for farming")
	if candidates.size() >= 2:
		var target := candidates[0]
		var untouched := candidates[1]
		farm._target = target
		farm._has_target = true
		var interaction := farm.get_interaction_state()
		check(interaction.visible and interaction.target_valid and not interaction.tilled and interaction.item.id == "hoe", "Interaction UI reports the selected tool and reachable untouched grass")
		var index := terrain.data._index(target)
		var original_paint := farm._base_data.paint_at_index(index)
		check(farm.use_at(target), "Actual selected hoe tills spawn grass")
		interaction = farm.get_interaction_state()
		check(interaction.tilled and not interaction.sown and interaction.can_restore and interaction.restore_error.is_empty(), "Tilled soil exposes restore independently of the blocked repeated till action")
		check(terrain.data.paint_at_index(index) == farm.soil_paint_id and terrain.data != farm._base_data and farm._base_data.paint_at_index(index) == original_paint, "Only the runtime surface receives the existing soil paint")
		check(not farm.use_at(target), "Repeated hoe use preserves farmland")
		ui.state.select_quick_slot(3)
		var before := ui.state.get_quantity("tomato_seed")
		check(not farm.use_at(untouched) and ui.state.get_quantity("tomato_seed") == before, "Seed use on grass cannot consume stock")
		check(farm.use_at(target) and ui.state.get_quantity("tomato_seed") == before - 1 and farm._seeds.multimesh.instance_count == 1, "Actual seed use updates stock and renders the planted seed")
		interaction = farm.get_interaction_state()
		check(interaction.sown and interaction.quantity == before - 1 and not interaction.watered and not interaction.primary_error.is_empty(), "Interaction UI reads committed seed quantity and sowing state")
		ui.state.select_quick_slot(1)
		check(farm.use_at(target), "Actual selected watering can waters the planted plot")
		check(farm.get_interaction_state().watered, "Interaction UI reads actual watered state")
		check(ui.state.get_farm_plot(farm.world_id, target).watered and ui.state.get_quantity("watering_can") == 1, "Watering commits moisture without consuming the tool")
		ui.state.select_quick_slot(0)
		ui.open_menu()
		check(not farm.get_interaction_state().visible, "Interaction UI hides while a blocking menu owns input")
		check(not farm.use_at(untouched) and not paused, "An open inventory blocks farming while the world keeps running")
		ui.close_menu()
		check(not farm.use_at(Vector2i(8, 14)), "Faraway grass cannot be tilled")
		var blocker := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.5, 0.8, 1.5)
		shape.shape = box
		blocker.add_child(shape)
		world.add_child(blocker)
		blocker.global_position = farm.cell_position(untouched) + Vector3.UP * 0.4
		await create_timer(0.1).timeout
		check(not farm.use_at(untouched), "A building-sized collider prevents tilling its footprint")
		blocker.free()
		var road := terrain.data.world_to_cell(terrain.to_local(player.global_position))
		check(terrain.data.has_overlay(road, TerrainData.OVERLAY_PATH) and not farm.use_at(road), "The real road under the player cannot be tilled")
		var cliff := Vector2i(-7, 2)
		check(not farm.use_at(cliff), "Different terrace heights cannot be farmed remotely")
		for point in [terrain.data.origin, terrain.data.origin + terrain.data.size - Vector2i.ONE]:
			check(not farm.use_at(point), "Map edges remain subject to reach and height checks")
		var seed_quantity := ui.state.get_quantity("tomato_seed")
		check(farm.use_at(target, true) and ui.state.get_quantity("tomato_seed") == seed_quantity + 1, "The selected hoe restores the actual watered and planted plot")
		check(terrain.data.paint_at_index(index) == original_paint and farm._seeds.multimesh.instance_count == 0 and farm._applied.is_empty(), "Restoration clears soil paint, seed instances and the vegetation mask")
		check(not farm.use_at(target, true) and ui.state.get_quantity("tomato_seed") == seed_quantity + 1, "Repeated map restoration does not duplicate stock")
		ui.open_menu()
		check(ui.take_inventory_item("tomato_seed"), "Backpack can pick up a usable item")
		check(not ui.menu_open and ui.state.get_quick_slots()[ui.state.active_quick_slot] == "tomato_seed", "Picking up closes the book and selects the correct shortcut")
	check(FileAccess.get_sha256(terrain_source_path) == terrain_source_hash and farm._base_data.paints == original_paints, "The saved editor terrain resource is unchanged")
	world.free()
	state.changed.disconnect(observe)
	for frame in 6: await process_frame
	print("Farming: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
