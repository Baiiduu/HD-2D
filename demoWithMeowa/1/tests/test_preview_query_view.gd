extends "res://tests/test_aim_path_preview.gd"

const View = preload("res://scripts/combat/preview_spatial_query_view.gd")
const COUNTS: Array[int] = [128, 160]
class CustomIndex extends WaveEnemySpatialIndex:
	func nearby_into(_point: Vector3, _radius: float, _excluded: Dictionary[int, bool], result: Array[WaveEnemy]) -> void:
		result.clear()
class MutatingSession extends WavePrototype:
	var before_query: Callable
	func _ready() -> void: set_physics_process(false)
	func combat_active() -> bool:
		if before_query.is_valid():
			var callback := before_query
			before_query = Callable()
			callback.call()
		return super.combat_active()

var bench := false
var output := ""
var rows: Array[Dictionary] = []
var wall: StaticBody3D

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--benchmark": bench = true
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	create_timer(180.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func fixture() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	terrain = Terrain.new()
	var data := TerrainData.new()
	data.size = Vector2i.ZERO
	data.resize(Vector2i(-16, -16), Vector2i(32, 32))
	terrain.data = data
	world.add_child(terrain)
	session = WavePrototype.new()
	session.show_ui = false
	session.battle_area = Rect2(-15, -15, 30, 30)
	session.name = "WavePrototype"
	session.terrain = terrain
	session.phase = WavePrototype.Phase.BATTLE
	world.add_child(session)
	session.set_physics_process(false)
	session._attack_root = Node3D.new()
	session.add_child(session._attack_root)
	player = Player.new()
	player.animations = load("res://assets/meowa/player/animations.tres")
	var fresh_rules := ResourceLoader.load("res://data/player/body_ricochet.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as PlayerRicochetRules
	check(fresh_rules.preview_spatial_queries_enabled, "Fresh formal resource load enables preview spatial queries before any manual A/B setting")
	check(fresh_rules.flat_ground_certificate_enabled, "Fresh formal resource load enables the ground certificate before any manual A/B setting")
	player.ricochet_rules = fresh_rules.duplicate()
	player.action_visuals = PlayerActionVisuals.new()
	player.action_visuals.show_charge_effect = false
	player.sword_rules = PlayerSwordRules.new()
	player.sword_rules.audio_enabled = false
	player.bounds = Rect2(-15, -15, 30, 30)
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	sprite.position.y = 0.75
	player.add_child(sprite)
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.24
	shape.height = 1.06592
	collision.shape = shape
	collision.position.y = shape.height * 0.5
	player.add_child(collision)
	session.player = player
	world.add_child(player)
	body = player.body_ricochet
	await settle()
	navigation.prefetch_enabled = false
	navigation.build(terrain, 0.32, [player.get_rid()])
	await reset()
	check(body._path._query.shape == null and body._path.graph.get_point_count() == 0,
		"Actual player TerrainPath remains unbuilt, without a fabricated query shape")
	check(player.ricochet_rules.crowd_deflection_enabled and not player.ricochet_rules.enemy_push_enabled,
		"The real formal ricochet rules enable crowd contours and keep enemy push OFF")
	wall = box(Vector3(0, 0.5, -5.0), Vector3(0.025, 1.0, 3.0))
	await settle()

func populate(count: int) -> void:
	clear_enemies()
	await settle()
	var names := ["wave_slime", "leaf_charger", "lantern_spitter", "pot_brood", "bell_frog"]
	for index in count:
		var definition: WaveEnemyDefinition = load("res://data/enemies/" + names[index % names.size()] + ".tres").duplicate()
		var actor := definition.scene.instantiate() as WaveEnemy
		actor.configure_wave({"player": player, "terrain": terrain, "camera": null, "navigation": navigation,
			"attack_root": session._attack_root, "spatial_index": session._spatial_index,
			"damage_player": func(_amount): pass, "request_spawn": Callable(), "combat_active": session.combat_active}, definition, 0.4 if index % 13 == 0 else 0.0)
		actor.position = Vector3((index % 16 - 7.5) * 0.62, 0.03 + (0.8 if index % 17 == 0 else 0.0), -1.8 - (index / 16) * 0.62)
		world.add_child(actor)
		actor.set_physics_process(false)
		actor.set_process(false)
		session.enemies.append(actor)
		session._spatial_index.update(actor)
	await settle()

func route_bytes(route: AimPathData) -> PackedByteArray:
	return var_to_bytes([route.segments, route.contacts, route.crowd_contacts, route.total_distance, route.total_seconds, route.end_reason])

func state_bytes() -> PackedByteArray:
	var state: Array = [player.global_transform, player.velocity, PhysicsServer3D.body_get_collision_mask(player.get_rid()), player.sword._age, player.sword._since_strike, player.current_health]
	for actor in session.enemies: state.append([actor.get_instance_id(), actor.global_transform, actor.velocity, actor.health, actor.spawn_delay])
	return var_to_bytes(state)

func spatial_checks() -> void:
	var view := View.new(session._spatial_index, session)
	check(view.eligible and view.is_current(session._spatial_index), "Exact production WavePrototype/index activate the fast view")
	var excluded: Dictionary[int, bool] = {}
	var old_nodes: Array[WaveEnemy] = []
	var slots: Array[int] = []
	for index in 32:
		var point := Vector3(-4.5 + index * 0.3, 0.0, -2.0 - (index % 7) * 0.7)
		var radius: float = [0.0, 0.3, 0.8, 1.35, 3.7, 8.0][index % 6]
		if index % 4 == 0: excluded[session.enemies[index].get_instance_id()] = true
		session._spatial_index.nearby_into(point, radius, excluded, old_nodes)
		view.nearby_slots_into(point, radius, excluded, slots)
		var new_nodes: Array[WaveEnemy] = []
		for slot in slots: new_nodes.append(view.owners[slot])
		check(old_nodes == new_nodes, "Typed slots keep exact cell/BFS candidate order, exclusions and distances")
	for seed_index in [1, 15, 33, 67, 90]:
		var seed := session.enemies[seed_index]
		if seed.spawn_delay > 0.0: continue
		var old_regions := EnemyPushWave.new(player.ricochet_rules)
		var new_regions := EnemyPushWave.new(player.ricochet_rules, view)
		var expected := old_regions.region_for(seed, Vector3.FORWARD)
		var actual := new_regions.region_for(seed, Vector3.FORWARD)
		check(var_to_bytes(expected) == var_to_bytes(actual), "Seed height/search-radius BFS and full fitted contour are byte-identical")

func prediction_checks() -> void:
	await reset()
	check(body.begin_charge(Vector3.FORWARD), "Actual player begins grounded preview")
	for fraction in [0.25, 0.6, 1.0]:
		body._charge_age = body._settings.full_charge_seconds * fraction
		for heading in [Vector3.FORWARD, Vector3(-0.35, 0, -1).normalized(), Vector3(0.35, 0, -1).normalized(), Vector3.RIGHT, Vector3.BACK]:
			body.aim(heading)
			body._settings.preview_spatial_queries_enabled = false
			body._settings.flat_ground_certificate_enabled = false
			var expected := AimPathData.new()
			var before := state_bytes()
			body.predict_path(query, expected, 12.0, 1)
			for mode in [[true, false], [false, true], [true, true]]:
				body._settings.preview_spatial_queries_enabled = mode[0]
				body._settings.flat_ground_certificate_enabled = mode[1]
				var actual := AimPathData.new()
				body.predict_path(query, actual, 12.0, 1)
				check(route_bytes(expected) == route_bytes(actual), "Independent/combined candidates preserve every route segment/contact/time/end reason")
			check(state_bytes() == before, "Preview preserves bodies, index actors, masks, attack clocks and HP")
	body.cancel(true)

func measured(view_enabled: bool, ground_enabled: bool, repeats: int) -> Dictionary:
	body._settings.preview_spatial_queries_enabled = view_enabled
	body._settings.flat_ground_certificate_enabled = ground_enabled
	var route := AimPathData.new()
	var started := Time.get_ticks_usec()
	for repeat in repeats: body.predict_path(query, route, 12.0, 1)
	return {"view": view_enabled, "ground": ground_enabled, "calls": repeats,
		"us_per_prediction": float(Time.get_ticks_usec() - started) / repeats,
		"segments": route.segments.size(), "crowd_contacts": route.crowd_contacts.size(), "members": session.enemies.size(),
		"player_path_unbuilt": body._path._query.shape == null and body._path.graph.get_point_count() == 0}

func microbench(count: int) -> void:
	await reset()
	body.begin_charge(Vector3.FORWARD)
	body.advance(0.8, Vector3.ZERO, false)
	var proof := AimPathData.new()
	body.predict_path(query, proof, 12.0, 1)
	check(proof.crowd_contacts.size() > 0 and proof.segments.size() > 10,
		"Timed real prediction actually builds and follows a crowd contour")
	for mode in [[false, false], [true, false], [false, true], [true, true]]: measured(mode[0], mode[1], 8)
	for mode in [[false, false], [true, false], [true, false], [false, false], [false, false], [false, true], [false, true], [false, false], [false, false], [true, true], [true, true], [false, false]]:
		var sample := measured(mode[0], mode[1], 48)
		sample.population = count
		rows.append(sample)
	body.cancel(true)

func boundary_checks() -> void:
	var defaults := PlayerRicochetRules.new()
	check(not defaults.preview_spatial_queries_enabled and not defaults.flat_ground_certificate_enabled, "Generic rule defaults retain legacy paths")
	var standalone := ProjectileCollision.new()
	check(not standalone.center_certificate_enabled, "Unrelated projectile/Creature collision instances retain old sampling")
	var original_index := session._spatial_index
	var original_view := View.new(original_index, session)
	var replacement := WaveEnemySpatialIndex.new()
	replacement.synchronize(session.enemies)
	session._spatial_index = replacement
	check(not original_view.is_current(replacement), "Same-frame index replacement rejects the captured view")
	var old_crowd := PlayerCrowdDeflection.new(player.ricochet_rules, session)
	var new_crowd := PlayerCrowdDeflection.new(player.ricochet_rules, session, null, original_view)
	var start := player.global_position
	var end := start + Vector3.FORWARD * 10.0
	check(old_crowd.contact(start, end, Vector3.FORWARD) == new_crowd.contact(start, end, Vector3.FORWARD), "Replacement uses current legacy contact semantics")
	session._spatial_index = original_index
	var custom_index := CustomIndex.new()
	custom_index.synchronize(session.enemies)
	session._spatial_index = custom_index
	var unknown_view := View.new(custom_index, session)
	check(not unknown_view.eligible, "Unknown index script cannot bypass custom nearby_into")
	new_crowd = PlayerCrowdDeflection.new(player.ricochet_rules, session, null, unknown_view)
	check(new_crowd.contact(start, end, Vector3.FORWARD).is_empty(), "Custom empty candidate filtering survives the enabled candidate")
	session._spatial_index = original_index
	var custom_session := MutatingSession.new()
	custom_session.player = player
	custom_session.terrain = terrain
	custom_session.battle_area = Rect2(-15, -15, 30, 30)
	custom_session.phase = WavePrototype.Phase.BATTLE
	custom_session._spatial_index = original_index
	world.add_child(custom_session)
	var custom_view := View.new(original_index, custom_session)
	check(not custom_view.eligible, "Unknown or mutating combat_active session rejects the fast view before callbacks")
	var subject := session.enemies[1]
	var initial := subject.global_position
	custom_session.before_query = func():
		subject.global_position += Vector3(0.07, 0, 0)
		original_index.update(subject)
	new_crowd = PlayerCrowdDeflection.new(player.ricochet_rules, custom_session, null, custom_view)
	var actual := new_crowd.contact(start, end, Vector3.FORWARD)
	old_crowd = PlayerCrowdDeflection.new(player.ricochet_rules, custom_session)
	check(subject.global_position != initial and actual == old_crowd.contact(start, end, Vector3.FORWARD), "Mutating predicate runs once and legacy sees the updated actual world")
	subject.global_position = initial
	original_index.update(subject)
	custom_session.queue_free()
	# Fresh per-call views reflect committed same-frame movement/activation/size.
	subject = session.enemies[13]
	var old_position := subject.global_position
	var old_delay := subject.spawn_delay
	var old_radius: float = subject.get("body_radius")
	subject.global_position += Vector3(-0.11, 0, 0.04)
	subject.spawn_delay = 0.0
	subject.set("body_radius", old_radius + 0.01)
	original_index.update(subject)
	spatial_checks()
	subject.global_position = old_position
	subject.spawn_delay = old_delay
	subject.set("body_radius", old_radius)
	original_index.update(subject)

func actual_flight_mode(enabled: bool) -> PackedVector3Array:
	await reset()
	player.ricochet_rules.preview_spatial_queries_enabled = enabled
	player.ricochet_rules.flat_ground_certificate_enabled = enabled
	check(body.begin_charge(Vector3.FORWARD), "Actual A/B charge begins")
	body.advance(0.8, Vector3.ZERO, false)
	check(body._collision.center_certificate_enabled == enabled, "Player collision instance is bound to this charge snapshot")
	player.ricochet_rules.flat_ground_certificate_enabled = not enabled
	check(body._settings.flat_ground_certificate_enabled == enabled, "Editing source rules does not alter the current launch snapshot")
	check(body.release_charge(), "Actual A/B release succeeds")
	var points := PackedVector3Array()
	for tick in 600:
		if not body.flying: break
		body.advance(1.0 / 60.0, Vector3.ZERO, false)
		points.append(player.global_position)
	check(not body._collision.center_certificate_enabled, "Flight end clears only this collision instance's certificate flag")
	body.cancel(true)
	return points

func flight_and_lifecycle_checks() -> void:
	var old_points := await actual_flight_mode(false)
	var new_points := await actual_flight_mode(true)
	check(not old_points.is_empty() and old_points.to_byte_array() == new_points.to_byte_array(), "Real 60Hz flight is byte-identical with center certificate OFF/ON")
	for actor in session.enemies:
		if actor is CreatureEnemy:
			check(not actor._surface_collision.center_certificate_enabled, "Creature local movement owns an unaffected disabled instance")
			break
	var dying := session.enemies[5]
	dying.take_damage(dying.health)
	check(dying.dead and not session._spatial_index._entries.has(dying), "Real lethal damage immediately removes the slot")
	spatial_checks()

func run() -> void:
	if DisplayServer.get_name() != "headless": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await fixture()
	for count in COUNTS:
		await populate(count)
		spatial_checks()
		await prediction_checks()
		wall.position.x = 1.0
		await settle()
		spatial_checks()
		await prediction_checks()
		wall.position.x = 0.0
		await settle()
		boundary_checks()
		if bench and failures == 0: await microbench(count)
		await flight_and_lifecycle_checks()
	var report := {"checks": checks, "failures": failures, "same_actors_per_ABBA": true,
		"single_prediction_only": true, "no_cross_frame_cache": true, "samples": rows}
	if not output.is_empty(): FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	body._settings.preview_spatial_queries_enabled = false
	body._settings.flat_ground_certificate_enabled = false
	body.cancel(true)
	clear_enemies()
	world.queue_free()
	await settle()
	quit(1 if failures else 0)
