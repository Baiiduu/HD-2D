extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("FAIL: ", message)

func settle(count := 4) -> void:
	for frame in count: await physics_frame

func finish(scene: Node) -> void:
	var wave: WavePrototype = scene.get_node("WavePrototype")
	if wave.phase == WavePrototype.Phase.BATTLE: wave.retreat()
	await settle()
	scene.queue_free()
	await settle()
	print("Rooftop pursuit: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func navigation_checks() -> void:
	var terrain := Terrain.new()
	var data := TerrainData.new()
	data.size = Vector2i.ZERO
	data.resize(Vector2i.ZERO, Vector2i(3, 1))
	terrain.data = data
	terrain.position.x = 100.0
	root.add_child(terrain)
	await settle()
	var path := TerrainPath.new()
	var exclude: Array[RID] = []
	data.set_level(Vector2i(1, 0), 1)
	data.set_level(Vector2i(2, 0), 1)
	await settle()
	path.build(terrain, 0.28, exclude)
	check(path.pursuit_route(Vector3(100, 0, 0), Vector3(103.2, 0.8, 0)).is_empty(), "Pursuit preserves disconnected cliff rejection")
	check(not path.shared_reachable(Vector3(100.79, 0, 0), Vector3(101.6, 0.8, 0)), "Shared endpoint fallback cannot cross a nearby cliff")
	var building := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.0, 1.2)
	collision.shape = box
	building.add_child(collision)
	building.position = Vector3(103.2, 1.3, 0)
	root.add_child(building)
	await settle()
	path.build(terrain, 0.28, exclude)
	check(path.pursuit_route(Vector3(100, 0, 0), Vector3(103.2, 1.8, 0)).is_empty(), "Spawn/reachability reject a building on a disconnected platform")
	check(not path.shared_reachable(Vector3(100, 0, 0), Vector3(103.2, 1.8, 0)), "Shared reachability rejects a disconnected rooftop")
	check(not path.pursuit_route(Vector3(100, 0, 0), Vector3(103.2, 1.8, 0), true).is_empty(), "Existing slime may approach the reachable side of a building")
	building.queue_free()
	await settle()
	data.set_level(Vector2i(1, 0), 0)
	data.set_overlay(Vector2i(1, 0), TerrainData.OVERLAY_RAMP, true)
	await settle()
	path.build(terrain, 0.28, exclude)
	var route := path.pursuit_route(Vector3(100, 0, 0), Vector3(103.2, 1.4, 0))
	check(not route.is_empty() and route[-1].is_equal_approx(Vector3(103.2, 0.8, 0)), "Jumping target still uses exact ramp surface")
	check(path.shared_reachable(Vector3(100, 0, 0), Vector3(103.2, 1.4, 0)), "Shared endpoints preserve a connected ramp")
	data.set_overlay(Vector2i(1, 0), TerrainData.OVERLAY_RAMP, false)
	data.set_overlay(Vector2i(1, 0), TerrainData.OVERLAY_WATER, true)
	data.set_level(Vector2i(2, 0), 0)
	await settle()
	path.build(terrain, 0.28, exclude)
	check(path.pursuit_route(Vector3(100, 0, 0), Vector3(103.2, 0, 0)).is_empty(), "Pursuit cannot cross water")
	check(not path.shared_reachable(Vector3(100, 0, 0), Vector3(103.2, 0, 0)), "Shared pursuit cannot cross water")
	check(path.pursuit_route(Vector3(100, 0, 0), Vector3(101.6, 0, 0)).is_empty(), "Water target does not become a building fallback")
	check(not path.shared_reachable(Vector3(100, 0, 0), Vector3(101.6, 0, 0)), "Shared target fallback cannot escape a water cell")
	check(not path.shared_reachable(Vector3(101.59, 0, 0), Vector3(100, 0, 0)), "Shared source fallback cannot escape a water cell")
	check(path.pursuit_route(Vector3(100, 0, 0), Vector3(110, 0, 0)).is_empty(), "Outside-map target stays unreachable")
	check(path.pursuit_route(Vector3.INF, Vector3(100, 0, 0)).is_empty(), "Invalid target/source is rejected")
	terrain.queue_free()
	await settle()

func run() -> void:
	var scene: Node3D = load("res://scenes/world/world.tscn").instantiate()
	scene.get_node("LoadoutUI").save_enabled = false
	scene.get_node("WavePrototype/RunGrowth").enabled = false
	scene.get_node("WavePrototype/FanAutoAttack").enabled = false
	root.add_child(scene)
	current_scene = scene
	await settle(16)
	var wave: WavePrototype = scene.get_node("WavePrototype")
	var player: Player = scene.get_node("Player")
	player.set_physics_process(false)
	wave.set_physics_process(false)
	player.global_position = wave.global_position + Vector3.UP * 0.03
	# Pursuit assertions require a running challenge, not a random fan card draw.
	var skills: RunSkills = wave.get_node("RunSkills")
	skills.initial_cards_per_draw = skills.skill_paths.size()
	var requested := wave.start_run()
	var initial_choice := scene.get_node_or_null("WavePrototype/RunSkills/InitialSkillChoice") as GrowthChoiceUI
	if initial_choice and initial_choice.is_open:
		initial_choice.reveal_now()
		initial_choice.select_option(&"initial:fan_slash")
		initial_choice.confirm_selection()
	check(requested and wave.phase == WavePrototype.Phase.BATTLE, "Challenge starts on current battle map")
	# 学习初始技能会重新开启对应组件；本测试只观察追击和怪物攻击。
	scene.get_node("WavePrototype/FanAutoAttack").enabled = false
	var pierce := scene.get_node_or_null("WavePrototype/LightPierceAutoAttack")
	if pierce: pierce.set("enabled", false)
	wave._spawn_queue.clear()
	check(wave._spawn_enemy(), "Ground target permits initial slime spawn")
	if wave.enemies.is_empty():
		await finish(scene)
		return
	var slime := wave.enemies[0] as SlimeEnemy
	slime.spawn_delay = 0.0
	for prop_path in ["WorldDetails/BattleCourts/TreePlanter", "WorldDetails/BattleCourts/OctagonalPillar20", "WorldDetails/BattleCourts/CrateRow22"]:
		var prop: Node3D = scene.get_node(prop_path)
		var collider := prop.find_children("*", "CollisionShape3D", true, false)[0] as CollisionShape3D
		var center := collider.global_position
		var ray := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 8.0, center - Vector3.UP * 2.0, 1, [player.get_rid()])
		var hit := scene.get_world_3d().direct_space_state.intersect_ray(ray)
		check(not hit.is_empty(), "Real building has a standing surface: " + prop_path)
		if hit.is_empty(): continue
		var roof: Vector3 = hit.position + Vector3.UP * 0.03
		player.global_position = roof
		var start_id := wave._path.graph.get_closest_point(wave._path.ground_position(roof + Vector3(0, 0, -6.0)))
		slime.global_position = wave._path.graph.get_point_position(start_id) + Vector3.UP * 0.03
		slime.velocity = Vector3.ZERO
		slime._route_clock = 0.0
		var before := slime.global_position
		var health := player.current_health
		check(wave._path.route(before, wave._ground_target()).is_empty(), "Exact ground route remains blocked by building: " + prop_path)
		await settle(180)
		check(not slime._route.is_empty() and not wave._path._point_blocked(slime._route[-1]), "Pursuit ends outside real building collision: " + prop_path)
		check(TerrainPath.horizontal_distance(slime.global_position, before) > 1.0, "Slime approaches elevated player: " + prop_path)
		check(TerrainPath.horizontal_distance(slime.global_position, roof) < TerrainPath.horizontal_distance(before, roof) - 1.0, "Pursuit reduces distance without crossing building: " + prop_path)
		if roof.y - slime.global_position.y > slime.contact_height:
			check(player.current_health == health, "High building prevents contact damage")
		check(wave._spawn_enemy(), "Standing on building permits further spawns: " + prop_path)
		for other in wave.enemies.duplicate():
			if other == slime: continue
			other.spawn_delay = 0.0
			other.take_damage(10000.0)
		wave._check_reachability(wave.unreachable_timeout + 0.1)
		check(wave.phase == WavePrototype.Phase.BATTLE, "Roof pursuit does not falsely end challenge: " + prop_path)
		if wave.phase != WavePrototype.Phase.BATTLE:
			await finish(scene)
			return
		var landing_id := wave._path.graph.get_closest_point(wave._path.ground_position(roof + Vector3(-signf(roof.x) * 5.0, 0, 0)))
		player.global_position = wave._path.graph.get_point_position(landing_id) + Vector3.UP * 0.03
		slime._route_clock = 0.0
		before = slime.global_position
		await settle(90)
		check(TerrainPath.horizontal_distance(slime.global_position, before) > 0.5, "Slime resumes direct pursuit after landing: " + prop_path)
		check(not slime._route.is_empty() and slime._route[-1].is_equal_approx(wave._ground_target()), "Landing restores exact destination: " + prop_path)
	# 停留在建筑上时正常等待；真正跌出地面的残怪仍触发原有保护。
	slime.set_physics_process(false)
	slime.global_position.y -= 5.0
	wave._check_reachability(wave.unreachable_timeout + 0.1)
	check(wave.phase == WavePrototype.Phase.RESULT and wave.result_reason.contains("无法到达"), "Fallen enemy still triggers reachability protection")
	await navigation_checks()
	await finish(scene)
