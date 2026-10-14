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
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	world.get_node("MapEffects/BGM").music_enabled = false
	var surface_hash := FileAccess.get_sha256("res://data/world/world_surface.tres")
	var terrain_hash := FileAccess.get_sha256("res://data/world/world_terrain.tres")
	root.add_child(world)
	current_scene = world
	await settle()
	check(world.get_meta("battle_only", false), "Formal scene uses battle-only layout")
	for path in ["HouseSite", "TrainingHut", "TrainingUI", "GardenSite", "CityPlaza", "Farming", "GreenLights", "WorldDetails/EastPlaza"]:
		check(not world.has_node(path), "Removed region stays absent: " + path)
	var area: BattleArea = world.get_node("BattleArea")
	var terrain: Terrain = world.get_node("Homestead")
	check(area.get_core_rect().size == Vector2(32, 32), "Existing battle core size preserved")
	check(area.get_activity_rect().size == Vector2(48, 48), "Eight-metre loop retained")
	check(terrain.data.get_world_rect().is_equal_approx(Rect2(-24.8, 20, 49.6, 49.6)), "Terrain cropped to battle cells")
	check(terrain.data.get_world_rect().encloses(area.get_activity_rect()), "Activity loop stays on real ground")
	for key in terrain.surface_canvas._active_keys():
		check(Rect2(Vector2(key) * 6.4, Vector2(6.4, 6.4)).intersects(terrain.data.get_world_rect()), "Only battle surface chunks are uploaded")
	var rebuilt := area.make_terrain(terrain.data)
	check(rebuilt.to_image().get_data() == terrain.data.to_image().get_data(), "Editor terrain rebuild preserves all battle paints and heights")
	check(rebuilt.origin == terrain.data.origin and rebuilt.size == terrain.data.size, "Editor rebuild cannot restore removed districts")
	var player: Player = world.get_node("Player")
	var wave: WavePrototype = world.get_node("WavePrototype")
	player.set_physics_process(false)
	wave.set_physics_process(false)
	check(TerrainPath.horizontal_distance(player.global_position, area.get_entry_position()) < 0.01, "Player begins at battle entrance")
	check(player.bounds.encloses(area.get_core_rect()) and terrain.data.get_world_rect().encloses(player.bounds), "Movement bounds fit cropped terrain")
	check(wave._path_ready and wave._spawn_points.size() > 100, "Navigation and real spawn candidates are ready")
	for point in [Vector3(-12, 0, 32), Vector3(12, 0, 32), Vector3(-12, 0, 60), Vector3(12, 0, 60), Vector3(-22, 0, 62), Vector3(22, 0, 62)]:
		check(not wave._path.route(wave._ground_target(), point).is_empty(), "Entrance reaches battle and outer loop: " + str(point))
	var court := world.get_node("WorldDetails/BattleCourts")
	check(court.get_child_count() == 26, "Detail objects remain concentrated in battle area")
	var kinds := {}
	for prop in court.get_children():
		check(area.get_activity_rect().has_point(Vector2(prop.position.x, prop.position.z)), "Prop stays inside battle area: " + prop.name)
		if prop is TownDetailProp: kinds[prop.detail_kind] = true
		if prop is RicochetProp:
			check(prop._collision_body != null and prop._collision_body.is_in_group(&"ricochet_surfaces"), "Obstacle has real ricochet collision: " + prop.name)
	check(kinds.size() == 8, "All eight existing detail families reused")
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
	check(wave.start_run(), "Battle starts at cropped entrance")
	var initial: GrowthChoiceUI = wave.get_node("RunSkills/InitialSkillChoice")
	initial.reveal_now()
	check(initial.select_option(initial._options[0].id), "Battle entrance offers the actual initial skill draw")
	initial.confirm_selection()
	wave._physics_process(1.0)
	check(wave.phase == WavePrototype.Phase.BATTLE and not wave.enemies.is_empty(), "Configured wave spawns real enemies")
	wave.retreat()
	wave.return_home()
	check(TerrainPath.horizontal_distance(player.global_position, area.get_entry_position()) < 0.01, "Retreat returns to battle entrance")
	check(FileAccess.get_sha256("res://data/world/world_surface.tres") == surface_hash, "Runtime leaves hand-painted surface file unchanged")
	check(FileAccess.get_sha256("res://data/world/world_terrain.tres") == terrain_hash, "Runtime leaves saved terrain unchanged")
	world.queue_free()
	await settle()
	print("Battle-only world: %d checks, %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)
