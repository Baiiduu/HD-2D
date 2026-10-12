extends SceneTree

var checks := 0
var failures: Array[String] = []
var world: Node3D
var slime: SlimeEnemy
var player: Player
var original_home: Vector3

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool,message: String) -> void:
	checks += 1
	if not condition: failures.append(message); print("FAIL: ",message)

func frames(count: int) -> void:
	for i in count: await physics_frame

func reset_slime() -> void:
	slime.home_position = original_home
	slime.global_position = original_home
	slime.velocity = Vector3.ZERO
	slime.patrol_radius = 0.0
	slime._set_state(SlimeEnemy.State.IDLE)
	slime._idle_clock = 30.0

func wall_at(position: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3,2,0.2)
	collision.shape = box
	wall.position = position+Vector3.UP
	wall.add_child(collision)
	world.add_child(wall)
	return wall

func navigation_checks() -> void:
	var terrain := Terrain.new()
	var data := TerrainData.new()
	data.size = Vector2i.ZERO
	data.resize(Vector2i.ZERO,Vector2i(3,1))
	terrain.data = data
	terrain.position.x = 60.0
	root.add_child(terrain)
	await frames(4)
	var path := TerrainPath.new()
	var exclude: Array[RID] = []
	data.set_level(Vector2i(1,0),1)
	data.set_level(Vector2i(2,0),1)
	await frames(3)
	path.build(terrain,0.28,exclude)
	check(path.route(Vector3(60,0,0),Vector3(63.2,0.8,0)).is_empty(),"Cliff cannot be crossed without a ramp")
	data.set_level(Vector2i(1,0),0)
	data.set_overlay(Vector2i(1,0),TerrainData.OVERLAY_RAMP,true)
	await frames(3)
	path.build(terrain,0.28,exclude)
	check(not path.route(Vector3(60,0,0),Vector3(63.2,0.8,0)).is_empty(),"Ramp connects low ground to the platform")
	data.set_overlay(Vector2i(1,0),TerrainData.OVERLAY_RAMP,false)
	data.set_level(Vector2i(2,0),0)
	data.set_overlay(Vector2i(1,0),TerrainData.OVERLAY_WATER,true)
	await frames(3)
	path.build(terrain,0.28,exclude)
	check(path.route(Vector3(60,0,0),Vector3(63.2,0,0)).is_empty(),"Water is excluded from walking routes")
	terrain.free()

func _run() -> void:
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	slime = world.get_node("Slime")
	slime.patrol_radius = 0.0
	slime.idle_seconds = Vector2(30,30)
	root.add_child(world)
	player = world.get_node("Player")
	await frames(20)
	original_home = slime.home_position
	check(slime._ready_for_ai and slime._path.graph.get_point_count() > 1000,"Current-map navigation and actor initialize")
	check(Vector2(original_home.x,original_home.z).distance_to(Vector2(8,12.8)) < 0.001,"Confirmed south grass placement")
	check(slime.state == SlimeEnemy.State.IDLE,"Initial player spawn does not trigger detection")
	slime.terrain.data.emit_changed()
	await frames(5)
	check(slime._path._segment_clear(Vector3(-1.2,0.6,7.6),Vector3(-1.2,0.8,6.8)),"Terrain rebuild preserves ramp navigation with the new physics body")
	check(slime.animations.get_animation_names().size() == 16,"Eight idle and eight hopping animations")
	check(slime.sprite.occlusion_outline_enabled and slime.sprite.has_node("OcclusionOutline"),"Monster enables the shared occlusion outline")
	var outline := slime.sprite.get_node("OcclusionOutline") as MeshInstance3D
	check(outline.is_in_group("occlusion_outlines") and outline.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,"Monster outline is excluded from reflections and shadows")
	for clip in slime.animations.get_animation_names():
		var texture := slime.animations.get_frame_texture(clip,0) as AtlasTexture
		check(slime.animations.get_frame_count(clip) == 8 and texture.region.size == Vector2(80,80),"Native animation frames: "+clip)
	player.set_physics_process(false)
	player.position = Vector3(-1.6,0.8,5.6)
	slime.patrol_radius = 3.0
	slime._idle_clock = 0.0
	var furthest := 0.0
	for i in 240:
		await frames(1)
		furthest = maxf(furthest,TerrainPath.horizontal_distance(slime.position,original_home))
	check(furthest > 0.5 and furthest <= 3.1,"Patrol moves and stays inside its radius")
	reset_slime()
	player.position = original_home+Vector3(0,0,4)
	await frames(8)
	check(slime.state == SlimeEnemy.State.CHASE,"Visible nearby player triggers chase")
	await frames(250)
	var distance := TerrainPath.horizontal_distance(slime.position,player.position)
	check(distance <= slime.stop_distance+0.05 and distance >= slime.stop_distance-0.08,"Chase stops in front of player")
	var health := player.current_health
	await frames(60)
	check(player.current_health == health and Vector2(slime.velocity.x,slime.velocity.z).length() < 0.05,"Close encounter holds still without damage")
	player.position = original_home+Vector3(0,0,12)
	await frames(5)
	check(slime.state == SlimeEnemy.State.RETURN,"Exceeding home leash triggers return")
	await frames(550)
	check(slime.state == SlimeEnemy.State.IDLE and TerrainPath.horizontal_distance(slime.position,original_home) <= 0.16,"Return reaches original home and rests")
	reset_slime()
	player.position = original_home+Vector3(0,0,4)
	var wall := wall_at(original_home+Vector3(0,0,2))
	await frames(120)
	check(slime.state == SlimeEnemy.State.IDLE and not slime._can_see_target(),"Opaque wall blocks initial detection")
	slime._rebuild_path()
	var detour := slime._path.route(original_home,player.position)
	var deviates := false
	for point in detour: deviates = deviates or absf(point.x-original_home.x) > 1.5
	check(detour.size() > 2 and deviates,"Route detours around an intervening wall")
	wall.free()
	await frames(3)
	slime._rebuild_path()
	reset_slime()
	await frames(8)
	check(slime.state == SlimeEnemy.State.CHASE,"Detection resumes after wall removal")
	wall = wall_at(original_home+Vector3(0,0,2))
	var returned := false
	slime.state_changed.connect(func(state):
		if state == SlimeEnemy.State.RETURN: set_meta("lost_sight_return",true))
	await frames(130)
	returned = get_meta("lost_sight_return",false)
	check(returned,"Losing sight triggers return after its grace time")
	wall.free()
	await frames(3)
	slime._rebuild_path()
	reset_slime()
	player.position = original_home+Vector3(4,0,0)
	player.set_physics_process(true)
	var menu := world.get_node("LoadoutUI") as LoadoutUI
	menu.open_menu()
	var before := slime.position
	var player_before := player.position
	var event := InputEventKey.new()
	event.physical_keycode = KEY_D
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await frames(90)
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	check(not paused and slime.position.distance_to(before) > 0.5,"Monster keeps chasing while the menu is open")
	check(TerrainPath.horizontal_distance(player.position,player_before) < 0.02,"Open menu still blocks player movement")
	menu._finish_close()
	player.set_physics_process(false)
	reset_slime()
	slime.home_position = Vector3(-1.2,0.02,9.6)
	slime.position = slime.home_position
	player.position = Vector3(-1.2,0.8,6.0)
	await frames(260)
	check(slime.position.y > 0.75 and TerrainPath.horizontal_distance(slime.position,player.position) <= 1.0,"Physical chase climbs the existing south ramp")
	slime.set_physics_process(false)
	var camera := slime.camera
	camera.set_process(false)
	slime._look = Vector3.BACK
	slime.velocity = Vector3.ZERO
	slime._clip = &"idle_front"
	slime._frame = 3
	slime._elapsed = 0.04
	for direction in 8:
		camera.rotation = Vector3(deg_to_rad(-10),-direction*TAU/8,0)
		slime._process(0)
		check(slime._clip == StringName("idle_"+SlimeEnemy.DIRECTIONS[direction]) and slime._frame == 3,"Camera rotation selects direction without restarting motion: %d" % direction)
	await navigation_checks()
	world.queue_free()
	await frames(3)
	print("Slime: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
