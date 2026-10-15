extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run_checks.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func run_checks() -> void:
	var work := "D:/.codexfile/work/training-hut"
	DirAccess.make_dir_recursive_absolute(work)
	var catalog: LoadoutCatalog = load("res://data/rpg/loadout_catalog.tres")
	var rules: TrainingRules = load("res://data/rpg/training_rules.tres").duplicate()
	var state := LoadoutState.new(catalog,4,rules)
	check(state.get_character_attributes() == {"health":100.0,"mana":100.0,"attack":10.0,"defense":5.0},"Base attributes exist without equipment")
	check(state.acquire_equipment("sword") and state.equip("sword"),"Equip existing item")
	var equipment := state.get_attribute_totals().duplicate()
	var before: float = state.get_character_attributes().attack
	check(state.train("attack"),"Upgrade attack")
	check(state.get_character_attributes().attack == before+2 and state.training_points == 11,"Attack gain and exact point debit")
	check(state.get_attribute_totals() == equipment,"Training preserves equipment bonus API")
	check(state.preview_character_attributes("staff").attack == state.preview_attribute_totals("staff").attack+12,"Equipment preview includes base and training")
	check(state.train("health") and state.train("defense"),"All three upgrades work")
	check(state.get_character_attributes().health == 110 and state.get_character_attributes().defense == 6,"Health and defense gains")
	var snapshot := state.export_state()
	check(not state.train("invalid") and state.export_state() == snapshot,"Unknown training does not mutate state")
	check(state.save_to_path(work+"/state-test.json") == OK,"Training shares normal save")
	var restored := LoadoutState.new(catalog,4,rules)
	check(restored.load_from_path(work+"/state-test.json") and restored.export_state() == state.export_state(),"Save/load retains training and equipment exactly")
	var legacy := snapshot.duplicate(true)
	legacy.erase("training")
	check(restored.import_state(legacy) and restored.training_points == 12 and restored.get_training_level("attack") == 0,"Legacy saves initialize training")
	check(restored.train("health") and restored.save_to_path(work+"/legacy-test.json") == OK,"Legacy migration is persisted")
	var migrated := LoadoutState.new(catalog,4,rules)
	check(migrated.load_from_path(work+"/legacy-test.json") and migrated.training_points == 11,"Reopening does not grant points again")
	for bad: Variant in [-1,1.2,"2",null]:
		var damaged := snapshot.duplicate(true)
		damaged.training.points = bad
		var valid := restored.export_state()
		check(not restored.import_state(damaged) and restored.export_state() == valid,"Invalid points preserve existing state")
	var damaged := snapshot.duplicate(true)
	damaged.training.levels.health = -1
	check(not restored.import_state(damaged),"Invalid training level is rejected")
	rules.initial_points = 20
	rules.level_cap = 2
	var capped := LoadoutState.new(catalog,4,rules)
	check(capped.train("health") and capped.train("health") and capped.training_points == 17,"Cost rises with level")
	check(not capped.train("health") and capped.training_points == 17,"Level cap rejects without debit")
	var empty := LoadoutState.new(catalog)
	empty.training_points = 0
	check(not empty.train("attack") and empty.get_training_level("attack") == 0,"Insufficient funds reject upgrade")
	var scene: Node3D = load("res://scenes/world/world.tscn").instantiate()
	var loadout: LoadoutUI = scene.get_node("LoadoutUI")
	loadout.save_path = work+"/interaction-%d.json" % OS.get_process_id()
	root.add_child(scene)
	current_scene = scene
	for frame in 15:
		await physics_frame
	var ui: TrainingUI = scene.get_node("TrainingUI")
	var player: Player = scene.get_node("Player")
	var hut: Node3D = scene.get_node("TrainingHut")
	check(scene.get_node("SpawnPoint").position.is_equal_approx(Vector3(-1.6,1.05,5.6)),"Original world spawn is preserved")
	check(hut.position.is_equal_approx(Vector3(9.6,0,-4.8)),"Training hut is placed in the actual world")
	var dressing := scene.get_node("GroundDressing")
	var clear_entrance := true
	for placement: Dictionary in dressing._placements():
		var point: Vector3 = placement.point
		clear_entrance = clear_entrance and not Rect2(5.8,-8,7.6,14.4).has_point(Vector2(point.x,point.z))
	check(clear_entrance,"Building and approach have no generated grass or flowers")
	check(player.character_state == loadout.state,"Player consumes shared character attributes")
	check(not ui.open_menu(),"Out-of-range interaction is denied")
	player.position = ui.interaction_point.global_position + Vector3(0,-0.73,1.0)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	for frame in 10:
		await physics_frame
	check(ui.can_interact(),"Front of punching bag is reachable")
	key(KEY_F,true)
	key(KEY_F,false)
	check(ui.menu_open and not paused and not loadout.visible and ui.is_in_group(&"gameplay_input_blockers"),"F opens training with a live world and blocks gameplay input")
	key(KEY_TAB,true)
	key(KEY_TAB,false)
	check(ui.menu_open and not loadout.menu_open and not paused,"Tab cannot overlap equipment menu")
	var initial: float = player.get_attributes().health
	(ui._train_buttons["health"] as Button).pressed.emit()
	check(player.get_attributes().health == initial+10 and loadout.state.training_points == 11,"UI button applies actual player attribute change")
	var reloaded := LoadoutState.new(catalog)
	check(reloaded.load_from_path(loadout.save_path) and reloaded.get_training_level("health") == 1,"UI upgrade auto-saves")
	key(KEY_ESCAPE,true)
	key(KEY_ESCAPE,false)
	check(not ui.menu_open and not paused and loadout.visible and not ui.is_in_group(&"gameplay_input_blockers"),"ESC restores gameplay input and HUD")
	check(not ui.train("health"),"Closed training panel cannot upgrade")
	player.position = hut.global_position+Vector3(ui.interaction_point.position.x,0.02,1.7)
	player.reset_physics_interpolation()
	check(not ui.can_interact(),"Cannot use facility through house body")
	player.position = ui.interaction_point.global_position+Vector3(0,2.0,0.8)
	check(not ui.can_interact(),"Other elevation cannot interact")
	var generated := hut.get_node("Geometry")
	var triangles := 0
	for child in generated.get_children():
		if child is MeshInstance3D:
			var mesh: Mesh = child.mesh
			var arrays := mesh.surface_get_arrays(0)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			triangles += indices.size()/3 if indices != null and not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size()/3
			check(mesh.surface_get_material(0).albedo_texture != null,"Every surface uses Meowa material")
	check(triangles == hut.get_meta("triangle_count"),"Model triangle accounting")
	hut.export_glb()
	var document := GLTFDocument.new()
	var gltf := GLTFState.new()
	check(document.append_from_file("res://assets/meowa/training/training.glb",gltf) == OK,"GLB loads after export")
	var imported := document.generate_scene(gltf)
	check(imported != null and imported.get_child_count() == 10,"GLB preserves ten material meshes")
	imported.free()
	player.set_physics_process(false)
	player.position = hut.global_position+Vector3(hut.width*0.5+1.0,0.02,0)
	for frame in 45:
		await physics_frame
		player.velocity = Vector3(-4,player.velocity.y-20.0/60.0,0)
		player.move_and_slide()
	check(player.position.x >= hut.global_position.x+hut.width*0.5+0.2,"Hut wall blocks player")
	check(player.is_on_floor(),"World terrain supports player")
	var camera: FollowCamera = scene.get_node("MapEffects").get_map_camera()
	check(camera.distance == 11 and camera.pitch_degrees == 10 and camera.fov == 30 and camera.dof_enabled and camera.dof_amount == 0.02,"World retains development camera and DOF")
	print("Training validation: %d checks, %d failures; %d triangles" % [checks,failures.size(),triangles])
	scene.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
