extends SceneTree
## Headless, fixed-60-Hz CPU/behaviour comparison on the actual World scene.
## Run each arm in a fresh process with --headless --fixed-fps 60.
## No draw/GPU timing or displayed-FPS claim. Never saves project/user settings.
const WallOracle = preload("res://tests/fixtures/capsule_wall_intrusion_oracle.gd")
const SEED := 617
const PHASES := {"attack": 180, "walk_attack": 120, "charge": 120, "flight": 240}

class EndProbe extends Node:
	signal completed
	signal process_completed
	var audit: SceneTree
	func _physics_process(_delta: float) -> void:
		audit.end_physics()
		completed.emit()
	func _process(delta: float) -> void:
		audit.end_process(delta)
		process_completed.emit()

var population := 128
var certificates := true
var query_backend := Terrain.ObstacleQueryBackend.SCRIPT_CERTIFICATES
var storm_level := 0
var central_updates := false
var preview_dedup := false
var no_aim_guide := false
var native_swarm := false
var with_native_prototype := false
var rendered_fps := false
var frame_stamp := 0
var output := ""
var world: Node3D
var wave: WavePrototype
var player: Player
var terrain: Terrain
var probe: EndProbe
var stage := ""
var recording := false
var physics_stamp := 0
var process_stamp := 0
var span_stamp := 0
var span_stage := ""
var process_stage := ""
var span_valid := false
var measurements := {}
var query_counts := {}
var failures: Array[String] = []
var layout: Array = []
var spawn_instance_ids := PackedInt64Array()
var behaviours: Array = []
var hits := 0
var flight_hits := 0
var storm_hits := 0
var strikes := 0
var deflections := 0
var wall_bounces := 0
var flying_ticks := 0
var preview_frames := 0
var held_key := 0
var last_positions := {}
var travel := {}
var started_charge := false
var released_charge := false
var fixed_clock_valid := true

func _initialize() -> void:
	seed(SEED)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="): population = arg.trim_prefix("--count=").to_int()
		elif arg == "--native": certificates = false
		elif arg == "--native-queries": query_backend = Terrain.ObstacleQueryBackend.NATIVE_QUERIES
		elif arg == "--native-rays": query_backend = Terrain.ObstacleQueryBackend.NATIVE_RAYS
		elif arg == "--central-updates": central_updates = true
		elif arg == "--preview-dedup": preview_dedup = true
		elif arg == "--no-aim-guide": no_aim_guide = true
		elif arg == "--with-native-prototype": with_native_prototype = true
		elif arg == "--rendered-fps": rendered_fps = true
		elif arg == "--native-swarm":
			native_swarm = true
			with_native_prototype = true
			central_updates = true
		elif arg.begins_with("--storm="): storm_level = arg.trim_prefix("--storm=").to_int()
		elif arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	physics_frame.connect(begin_physics)
	process_frame.connect(begin_process)
	create_timer(180.0).timeout.connect(func(): push_error("Native query audit timeout"); quit(2))
	run.call_deferred()

func ensure(value: bool, label: String) -> void:
	if not value: failures.append(label); print("CHECK_FAILED " + label)

func push_sample(phase: String, metric: String, value: float) -> void:
	if not phase.is_empty(): measurements[phase][metric].append(value)

func close_physics_span(now: int) -> void:
	if span_stamp > 0 and span_valid:
		push_sample(span_stage, "physics_span_ms", float(now - span_stamp) / 1000.0)
	span_stamp = 0

func begin_physics() -> void:
	var now := Time.get_ticks_usec()
	close_physics_span(now)
	physics_stamp = now if recording else 0
	span_stamp = physics_stamp
	span_stage = stage
	span_valid = recording

func end_physics() -> void:
	if physics_stamp > 0:
		push_sample(span_stage, "physics_callbacks_ms", float(Time.get_ticks_usec() - physics_stamp) / 1000.0)
		physics_stamp = 0

func begin_process() -> void:
	var now := Time.get_ticks_usec()
	close_physics_span(now)
	process_stamp = now if recording else 0
	process_stage = stage

func end_process(delta: float) -> void:
	if process_stamp > 0:
		if rendered_fps:
			var now := Time.get_ticks_usec()
			if frame_stamp > 0: push_sample(process_stage, "wall_frame_ms", float(now - frame_stamp) / 1000.0)
			frame_stamp = now
		fixed_clock_valid = fixed_clock_valid and is_equal_approx(delta, 1.0 / 60.0)
		push_sample(process_stage, "process_callbacks_ms", float(Time.get_ticks_usec() - process_stamp) / 1000.0)
		if process_stage == "charge" and player.body_ricochet._charge_effect and player.body_ricochet._charge_effect.visible:
			preview_frames += 1
		process_stamp = 0

func settle(count: int) -> void:
	for index in count: await probe.completed

func spawned(enemy: WaveEnemy) -> void:
	# Prevent first-born movement from changing later safe spawn choices.
	enemy.set_wave_tick_enabled(false)
	layout.append([String(enemy.definition.enemy_id), enemy.global_position.x, enemy.global_position.y, enemy.global_position.z])
	spawn_instance_ids.append(enemy.get_instance_id())
	last_positions[enemy.get_instance_id()] = enemy.global_position
	travel[enemy.get_instance_id()] = 0.0

func aim_at_enemy() -> Vector3:
	var best := Vector3.FORWARD
	var distance := INF
	var space := world.get_world_3d().direct_space_state
	for enemy in wave.enemies:
		var offset: Vector3 = enemy.global_position - player.global_position
		if offset.length_squared() >= distance: continue
		var ray := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 0.4, enemy.global_position + Vector3.UP * 0.4, 1, [player.get_rid()])
		if not space.intersect_ray(ray).is_empty(): continue
		distance = offset.length_squared()
		best = offset.normalized()
	return best

func key(value: int) -> void:
	if value == held_key: return
	for entry in [[held_key, false], [value, true]]:
		if entry[0] == 0: continue
		var event := InputEventKey.new()
		event.physical_keycode = entry[0]
		event.keycode = entry[0]
		event.pressed = entry[1]
		Input.parse_input_event(event)
	Input.flush_buffered_events()
	held_key = value

func inspect_behaviour(tick: int) -> void:
	# Oracle/nearest-neighbour O(N^2) diagnostics are outside callback timings;
	# omit this step's wider physics span as well, including coroutine work.
	span_valid = false
	var walls := 0
	var wall_details: Array = []
	var spacing: Array[float] = []
	var controllers := wave.is_physics_processing() and player.is_physics_processing()
	var space := world.get_world_3d().direct_space_state
	var histogram := {}
	for enemy in wave.enemies:
		controllers = controllers and enemy.is_wave_tick_enabled()
		var id := String(enemy.definition.enemy_id)
		histogram[id] = int(histogram.get(id, 0)) + 1
		var wall := WallOracle.inspect(space, enemy.get_node("Collision"), enemy.navigation._query.exclude, 0.003)
		if not wall.supported or wall.intrudes:
			walls += 1
			var objects: Array = []
			for hit in wall.outer_hits:
				objects.append({"path":String(world.get_path_to(hit.collider)), "shape":hit.shape})
			wall_details.append({"type":id, "position":str(enemy.global_position), "velocity":str(enemy.velocity), "floor":enemy.is_on_floor(), "reason":wall.reason, "supported":wall.supported, "intrudes":wall.intrudes, "objects":objects, "raw_pairs":str(wall.raw_pairs)})
		var nearest := INF
		for other in wave.enemies:
			if enemy != other: nearest = minf(nearest, TerrainPath.horizontal_distance(enemy.global_position, other.global_position))
		spacing.append(nearest)
		var instance := enemy.get_instance_id()
		travel[instance] += TerrainPath.horizontal_distance(last_positions[instance], enemy.global_position)
		last_positions[instance] = enemy.global_position
	spacing.sort()
	behaviours.append({"stage":stage, "tick":tick, "alive":wave.enemies.size(), "types":histogram, "wall_intrusions_3mm":walls, "wall_details":wall_details, "spacing_min":spacing[0], "spacing_median":spacing[spacing.size()/2], "player":[player.global_position.x,player.global_position.y,player.global_position.z]})
	if not wall_details.is_empty(): print("WALL_DETAILS " + JSON.stringify(wall_details))
	ensure(controllers and not wave.combat_frozen and wave.phase == WavePrototype.Phase.BATTLE, "Live unfrozen controllers: %s/%d" % [stage,tick])
	ensure(wave.enemies.size() == population and histogram.size() == 5, "Complete five-type horde: %s/%d" % [stage,tick])
	ensure(walls == 0, "No 3mm inner-capsule wall intrusion: %s/%d (%d)" % [stage,tick,walls])
	ensure(is_finite(spacing[spacing.size()/2]) and spacing[spacing.size()/2] > 0.0, "Finite individual spacing")

func statistics(values: Array) -> Dictionary:
	if values.is_empty(): return {"samples":0}
	var ordered := values.duplicate()
	ordered.sort()
	var total := 0.0
	for value in values: total += value
	return {"samples":values.size(), "total_ms":total, "mean_ms":total / values.size(), "p95_ms":ordered[int(ordered.size() * 0.95)], "p99_ms":ordered[int(ordered.size() * 0.99)]}

func run() -> void:
	if rendered_fps:
		if DisplayServer.get_name() == "headless" or "--fixed-fps" in OS.get_cmdline_args() or population != 128:
			push_error("Rendered FPS requires an actual display, real-time clock, and 128 enemies")
			quit(2)
			return
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	elif DisplayServer.get_name() != "headless" or Engine.physics_ticks_per_second != 60:
		push_error("Run this CPU audit with --headless --fixed-fps 60 and 60 physics ticks/sec")
		quit(2)
		return
	if population not in [128, 160] or storm_level < 0 or storm_level > 4:
		push_error("This comparison supports 128/160 enemies and storm levels 0..4")
		quit(2)
		return
	ProjectSettings.set_setting("game_manager/systems/upgrades", false)
	ProjectSettings.set_setting("game_manager/systems/draft", false)
	ProjectSettings.set_setting("game_manager/systems/run_skills", true)
	# Load/construct the same optional native object in BOTH comparison arms.
	# This keeps birth IDs equal: crowd yielding currently depends on those IDs.
	var prototype: RefCounted = WavePrototype.NATIVE_SWARM.create() if with_native_prototype else null
	ensure(not with_native_prototype or prototype != null, "Requested native comparison has a built, loadable kernel")
	if not failures.is_empty(): quit(1); return
	if prototype: prototype.diagnostics_enabled = not rendered_fps
	probe = EndProbe.new()
	probe.audit = self
	probe.process_physics_priority = 1000000
	probe.process_priority = 1000000
	root.add_child(probe)
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("GameSettingsUI").save_graphics_settings = false
	world.get_node("MapEffects/BGM").music_enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	world.get_node("MapEffects/CoreFeedbackAudio").enabled = false
	for audio in world.find_children("UIAudio", "", true, false): audio.enabled = false
	var profile := world.get_node("BattleConfiguration").configuration.duplicate() as SceneCombatConfiguration
	profile.population_rules = profile.population_rules.duplicate(true) as WavePopulationRules
	profile.population_rules.simulation_mode = true
	profile.population_rules.simulation_enemy_count = population
	profile.population_rules.simulation_skills.clear()
	profile.centralized_enemy_updates = central_updates
	profile.native_swarm_enabled = native_swarm
	profile.action_visuals = profile.action_visuals.duplicate() as PlayerActionVisuals
	profile.action_visuals.deduplicate_charge_preview = preview_dedup
	profile.action_visuals.show_aim_guide = not no_aim_guide
	world.get_node("BattleConfiguration").configuration = profile
	terrain = world.get_node("Homestead")
	terrain.obstacle_certificates_enabled = certificates
	terrain.obstacle_query_backend = query_backend
	terrain.query_diagnostics_enabled = not rendered_fps
	wave = world.get_node("WavePrototype")
	wave._native_kernel = prototype
	wave.random_seed = SEED
	wave.enemy_spawned.connect(spawned)
	root.add_child(world)
	current_scene = world
	player = wave.player
	player.sword.hit_landed.connect(func(_enemy, _damage, flying):
		hits += 1
		if flying: flight_hits += 1)
	player.sword.strike_started.connect(func(_heading, _flying, _reverse): strikes += 1)
	player.body_ricochet.crowd_deflected.connect(func(_point, _incoming, _outgoing): deflections += 1)
	player.body_ricochet.wall_bounced.connect(func(_point, _normal): wall_bounces += 1)
	var storm := wave.get_node("RicochetStorm") as RicochetStorm
	storm.hit_landed.connect(func(_enemy, _damage): storm_hits += 1)
	await settle(20)
	player.global_position = wave.global_position + Vector3.UP * 0.03
	player.velocity = Vector3.ZERO
	ensure(wave.start_run(), "Simulation starts without draft gate: " + wave.result_reason)
	var center := wave.battle_area.get_center()
	player.global_position = wave._path.graph.get_point_position(wave._path.closest_point(Vector3(center.x, 0, center.y))) + Vector3.UP * 0.03
	player.velocity = Vector3.ZERO
	(player.movement_camera as FollowCamera).snap_to_target()
	while wave.enemies.size() < population and wave.phase == WavePrototype.Phase.BATTLE: await probe.completed
	ensure(wave.enemies.size() == population and wave._pending == 0, "All seeded enemies born")
	if not failures.is_empty(): quit(1); return
	if storm_level > 0:
		ensure(wave.run_skill_manager.set_skill_level(storm.skill_definition.id, storm_level), "Requested storm level is valid")
	for enemy in wave.enemies:
		enemy.spawn_delay = 0.0
		enemy.set_wave_tick_enabled(true)
		enemy.commit_spatial_state()
	if rendered_fps:
		# Stationary warmup keeps the camera and gathered population comparable.
		# Prewarming a flight leaves each arm at a different place on the map.
		var warmup_origin := player.global_position
		for tick in 1200:
			if tick % 30 == 0: player.sword.request_manual(aim_at_enemy())
			if tick == 240: player.body_ricochet.begin_charge(aim_at_enemy())
			if tick == 360: player.body_ricochet.cancel(true)
			await probe.completed
		player.body_ricochet.cancel(true)
		ensure(TerrainPath.horizontal_distance(warmup_origin, player.global_position) < 0.01, "Stationary warmup retains the same camera target")
	else:
		await settle(120)
	var health := player.current_health
	for phase: String in PHASES:
		stage = phase
		measurements[phase] = {"physics_callbacks_ms":[], "physics_span_ms":[], "process_callbacks_ms":[]}
		if rendered_fps: measurements[phase]["wall_frame_ms"] = []
		frame_stamp = 0
		terrain.reset_query_metrics()
		if phase == "charge":
			key(0)
			started_charge = player.body_ricochet.begin_charge(aim_at_enemy())
		if phase == "flight": released_charge = player.body_ricochet.release_charge()
		recording = true
		for tick in int(PHASES[phase]):
			if tick % 6 == 0: span_valid = false # input/aim preparation belongs to the harness
			if phase == "walk_attack" and tick % 30 == 0: key([KEY_D,KEY_S,KEY_A,KEY_W][tick/30])
			if phase in ["attack", "walk_attack"] and tick % 6 == 0: player.sword.request_manual(aim_at_enemy())
			if phase == "charge" and tick % 6 == 0: player.body_ricochet.aim(aim_at_enemy())
			await probe.completed
			if player.body_ricochet.flying: flying_ticks += 1
			if not rendered_fps and tick % 30 == 0: inspect_behaviour(tick)
		# Flush the final process frame before switching stage labels.
		await probe.process_completed
		recording = false
		# Expensive QA is outside rendered frame sampling. Collision acceptance is
		# separately verified with the fixed-clock and every-step contact tests.
		if rendered_fps: inspect_behaviour(-1)
		process_stamp = 0
		span_stamp = 0
		query_counts[phase] = terrain.get_query_metrics()
	var summary := {}
	for phase in measurements:
		summary[phase] = {}
		for metric in measurements[phase]: summary[phase][metric] = statistics(measurements[phase][metric])
		# Separate rates explicitly; never multiply a headless FPS into a claim.
		summary[phase]["one_physics_plus_one_process_ms"] = summary[phase].physics_span_ms.mean_ms + summary[phase].process_callbacks_ms.mean_ms
		if rendered_fps:
			summary[phase]["average_fps"] = 1000.0 / summary[phase].wall_frame_ms.mean_ms
	var moved := 0
	for distance in travel.values():
		if distance > 0.1: moved += 1
	ensure(started_charge and released_charge and preview_frames > (0 if rendered_fps else 30) and flying_ticks > 0, "Real charge, process preview and release ran")
	ensure(rendered_fps or fixed_clock_valid, "Every sampled process delta uses the required --fixed-fps 60 clock")
	ensure(hits > 0 and flight_hits > 0 and deflections > 0, "Real sword hits and crowd curvature retained")
	ensure(storm_level == 0 or storm_hits > 0, "Equipped storm makes real hits")
	ensure(moved >= population * 0.8, "At least 80% of monsters move over 10cm")
	ensure(wave.kills == 0 and is_equal_approx(player.current_health, health) and not player.ricochet_rules.enemy_push_enabled, "Simulation preserves population, health and no-push rules")
	var effect := player.body_ricochet._charge_effect
	var preview_metrics := {"predictions":effect.prediction_count, "batch_shapes":effect.batch_shape_queries, "empty_proofs":effect.batch_empty_proofs, "proved_rays":effect.batch_proved_rays} if is_instance_valid(effect) else {}
	var native_actor_callbacks := 0
	for enemy in wave.enemies:
		if enemy.is_physics_processing(): native_actor_callbacks += 1
	var centrally_updated: int = wave._enemy_update_batch.last_updated
	ensure(native_actor_callbacks == (0 if central_updates else population), "Selected scheduler owns all actor callbacks")
	ensure(not central_updates or centrally_updated == population, "Central scheduler advances every live actor each physics step")
	var result := {"kind":"headless_fixed60_scene_cpu_not_fps", "engine":Engine.get_version_info().string, "processor":OS.get_processor_name(), "count":population, "certificates":certificates, "query_backend":query_backend, "central_updates":central_updates, "preview_dedup":preview_dedup, "preview_metrics":preview_metrics, "storm_level":storm_level, "seed":SEED, "spawn_layout_sha256":JSON.stringify(layout).sha256_text(), "phases":summary, "behaviour":behaviours, "hits":hits, "flight_hits":flight_hits, "strikes":strikes, "storm_hits":storm_hits, "deflections":deflections, "wall_bounces":wall_bounces, "flying_ticks":flying_ticks, "preview_frames":preview_frames, "moved_over_10cm":moved, "terrain_queries":query_counts, "failures":failures}
	if rendered_fps:
		result.kind = "rendered_realtime_uncapped_fps"
		result["gpu"] = RenderingServer.get_video_adapter_name()
		result["viewport"] = [root.size.x, root.size.y]
		result["frames_drawn"] = Engine.get_frames_drawn()
		ensure(Engine.get_frames_drawn() > 30, "Real frames were drawn")
	result["scheduler"] = {"native_actor_callbacks":native_actor_callbacks, "last_central_updates":centrally_updated}
	result["spawn_instance_ids"] = Array(spawn_instance_ids)
	result["no_aim_guide"] = no_aim_guide
	result["native_swarm"] = native_swarm
	result["native_metrics"] = prototype.get_metrics() if prototype else {}
	ensure(not native_swarm or (wave._spatial_index.native_kernel == prototype and int(result.native_metrics.native_moves) > population), "Native backend actually runs batch forces and ordinary body motion")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE)
		file.store_string(JSON.stringify(result, "\t"))
	print(JSON.stringify({"count":population, "certificates":certificates, "phases":summary, "hits":hits, "flight_hits":flight_hits, "deflections":deflections, "storm_hits":storm_hits, "failures":failures}))
	key(0)
	wave.retreat()
	world.queue_free()
	probe.queue_free()
	await create_timer(0.2).timeout
	quit(0 if failures.is_empty() else 1)
