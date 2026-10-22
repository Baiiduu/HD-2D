extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle() -> void:
	for frame in 12: await physics_frame

func run() -> void:
	AudioServer.set_bus_mute(0, true)
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	# 本用例验证战区与开战；独立入场用例覆盖用户开启的人工镜头预览。
	world.get_node("WorldEntry").preview_on_direct_run = false
	world.get_node("WorldMainMenu").show_on_world_start = false
	world.get_node("WavePresentation").enabled = false
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	world.get_node("MapEffects/BGM").music_enabled = false
	# Exercise the normal start interaction even when the editor selects a stress simulation.
	var profile := world.get_node("BattleConfiguration").configuration as SceneCombatConfiguration
	profile = profile.duplicate() as SceneCombatConfiguration
	world.get_node("BattleConfiguration").configuration = profile
	var population := profile.population_rules.duplicate(true) as WavePopulationRules
	population.simulation_mode = false
	profile.population_rules = population
	var authored_kinds := {}
	for prop in world.get_node("WorldDetails/BattleCourts").get_children():
		if prop is TownDetailProp: authored_kinds[prop.detail_kind] = true
	var surface_hash := FileAccess.get_sha256("res://data/world/world_surface.res")
	var terrain_hash := FileAccess.get_sha256("res://data/world/world_terrain.tres")
	root.add_child(world)
	current_scene = world
	await settle()
	check(world.get_meta("battle_only", false), "Formal scene uses battle-only layout")
	for path in ["HouseSite", "TrainingHut", "TrainingUI", "GardenSite", "CityPlaza", "Farming", "GreenLights", "Slime", "WorldDetails/EastPlaza"]:
		check(not world.has_node(path), "Removed region stays absent: " + path)
	var area: BattleArea = world.get_node("BattleArea")
	var terrain: Terrain = world.get_node("Homestead")
	check(area.get_core_rect().size == Vector2(32, 32), "Existing battle core size preserved")
	check(area.loop_width == 0.0 and area.get_activity_rect().is_equal_approx(area.get_core_rect()), "Non-combat outer loop removed")
	check(terrain.data.get_world_rect().is_equal_approx(Rect2(-16.8, 28, 33.6, 33.6)), "Terrain cropped to the cells covering the unchanged core")
	check(terrain.data.get_world_rect().encloses(area.get_activity_rect()), "Battle area stays on real ground")
	for key in terrain.surface_canvas._active_keys():
		check(Rect2(Vector2(key) * 6.4, Vector2(6.4, 6.4)).intersects(terrain.data.get_world_rect()), "Only battle surface chunks are uploaded")
	var rebuilt := area.make_terrain(terrain.data)
	check(rebuilt.to_image().get_data() == terrain.data.to_image().get_data(), "Editor terrain rebuild preserves all battle paints and heights")
	check(rebuilt.origin == terrain.data.origin and rebuilt.size == terrain.data.size, "Editor rebuild cannot restore removed districts")
	var player: Player = world.get_node("Player")
	var capsule: CapsuleShape3D = player.get_node("Collision").shape
	var wave: WavePrototype = world.get_node("WavePrototype")
	player.set_physics_process(false)
	wave.set_physics_process(false)
	check(TerrainPath.horizontal_distance(player.global_position, area.get_entry_position()) < 0.01, "Player begins at the relocated start interaction")
	check(area.get_core_rect().grow(-capsule.radius).has_point(Vector2(player.position.x, player.position.z)), "Player begins safely inside the battle core")
	check(player.is_on_floor(), "New spawn settles on the existing ground")
	check(player.bounds.is_equal_approx(area.get_core_rect()), "Walking and body ricochet stay within the battle core")
	check(wave.battle_area.is_equal_approx(area.get_core_rect()), "Combat boundary follows the retained battle core")
	check(wave.can_start_run(), "Existing start interaction is immediately available at spawn")
	for zone in area.get_node("SpawnCandidates").get_children():
		check(area.get_core_rect().has_point(Vector2(zone.global_position.x, zone.global_position.z)), "Spawn region moved inside retained ground: " + zone.name)
	check(wave._path_ready and wave._spawn_points.size() > 100, "Navigation and real spawn candidates are ready")
	for point in [Vector3(-10, 0, 35.2), Vector3(0, 0, 40), Vector3(10, 0, 40), Vector3(-12, 0, 60), Vector3(0, 0, 60), Vector3(12, 0, 60)]:
		check(not wave._path.route(wave._ground_target(), point).is_empty(), "Spawn reaches retained battle ground: " + str(point))
	for point in [Vector3(-10, 0, 35.2), Vector3(0, 0, 40), Vector3(12, 0, 60)]:
		player.global_position = wave._path.ground_position(point) + Vector3.UP * 0.03
		check(wave.can_start_run(), "World can start away from the old entrance: " + str(point))
	var chosen_start := player.global_position
	var blocker := Node.new()
	world.add_child(blocker)
	blocker.add_to_group(&"gameplay_input_blockers")
	check(not wave.can_start_run() and not wave.start_run(), "Starting anywhere still respects management and menu input ownership")
	blocker.free()
	wave.set_combat_frozen(true)
	check(not wave.can_start_run(), "Starting anywhere still respects combat freeze")
	wave.set_combat_frozen(false)
	var navigation_ready := wave._path_ready
	wave._path_ready = false
	check(not wave.can_start_run(), "Starting anywhere still waits for real navigation")
	wave._path_ready = navigation_ready
	player.global_position.x = wave.battle_area.end.x + 1.0
	check(not wave.can_start_run(), "Invalid positions outside the combat map remain rejected")
	player.global_position = chosen_start
	var court := world.get_node("WorldDetails/BattleCourts")
	check(court.get_child_count() > 0, "Battle layout retains its existing detail objects")
	var kinds := {}
	for prop in court.get_children():
		check(area.get_activity_rect().has_point(Vector2(prop.position.x, prop.position.z)), "Prop stays inside battle area: " + prop.name)
		if prop is TownDetailProp: kinds[prop.detail_kind] = true
		if prop is RicochetProp:
			check(prop._collision_body != null and prop._collision_body.is_in_group(&"ricochet_surfaces"), "Obstacle has real ricochet collision: " + prop.name)
	check(not authored_kinds.is_empty() and kinds == authored_kinds, "Startup retains the authored detail families without requiring an old layout")
	var camera: FollowCamera = world.get_node("MapEffects/Camera3D")
	camera.set_process(false)
	camera.snap_to_target()
	var camera_pose := camera.global_transform
	var camera_settings := [camera.fov, camera.distance, camera.pitch_degrees, camera.dof_amount]
	var mesh: Node3D = terrain._generated
	var dressing := world.get_node("GroundDressing")
	var plants: Node3D = dressing._generated
	var sample: SpawnVisualSample = world.get_node("VisualSample")
	for style in [1, 2, 3, 0]:
		sample.style = style
		await settle()
		check(terrain._generated == mesh and dressing._generated == plants, "Style preserves geometry and vegetation distribution")
		check(camera.global_transform == camera_pose and camera_settings == [camera.fov, camera.distance, camera.pitch_degrees, camera.dof_amount], "Style preserves actual camera configuration")
		check(dressing.stable_shadows and sample._window_lights.is_empty(), "Stable soft shadows work without removed house lights")
	var start_input := InputEventKey.new()
	start_input.physical_keycode = wave.interact_key
	start_input.pressed = true
	wave._unhandled_key_input(start_input)
	var initial: GrowthChoiceUI = wave.get_node("SkillDraft/InitialSkillChoice")
	initial.reveal_now()
	check(not initial._options.is_empty(), "Existing interaction key opens the actual initial skill draw")
	if initial._options.is_empty():
		world.queue_free()
		await settle()
		quit(1)
		return
	check(initial.select_option(initial._options[0].id), "Battle entrance offers the actual initial skill draw")
	initial.confirm_selection()
	check(player.global_position.is_equal_approx(chosen_start), "Starting from a chosen location does not teleport the player to the old entrance")
	# 正式出怪队列包含分帧创建与出生影子，等待真实进程而非强求同帧建怪。
	wave.set_physics_process(true)
	var spawn_deadline := Time.get_ticks_msec() + 2500
	while wave.enemies.is_empty() and Time.get_ticks_msec() < spawn_deadline:
		await create_timer(0.05).timeout
	wave.set_physics_process(false)
	check(wave.phase == WavePrototype.Phase.BATTLE and not wave.enemies.is_empty(), "Configured wave spawns real enemies")
	wave.retreat()
	wave.return_home()
	check(TerrainPath.horizontal_distance(player.global_position, area.get_entry_position()) < 0.01, "Retreat returns inside the battle area")
	check(FileAccess.get_sha256("res://data/world/world_surface.res") == surface_hash, "Runtime leaves hand-painted surface file unchanged")
	check(FileAccess.get_sha256("res://data/world/world_terrain.tres") == terrain_hash, "Runtime leaves saved terrain unchanged")
	world.queue_free()
	await settle()
	print("Battle-only world: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
