extends SceneTree

## CPU ordinary-chase comparison, not displayed FPS or full-combat acceptance.
## Real formal-map collision, five actor types, navigation, crowd and body moves.
## --headless --fixed-fps 60 --script tools/benchmark_pursuit_batch.gd -- --output=D:/.../result.json
const STEP := 1.0 / 60.0
const KINDS := ["wave_slime", "leaf_charger", "lantern_spitter", "pot_brood", "bell_frog"]
var output := "D:/.codexfile/work/chase-batch-20261018/net-cost.json"
var world: Node3D
var wave: WavePrototype
var actors: Array[SlimeEnemy] = []
var paths: Array[TerrainPath] = []
var starts := PackedVector3Array()
var results: Array[Dictionary] = []
var warm_steps := 60
var sample_steps := 180
var populations := [128,160]
var reverse_order := false

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--samples="): sample_steps = argument.trim_prefix("--samples=").to_int()
		elif argument.begins_with("--warmup="): warm_steps = argument.trim_prefix("--warmup=").to_int()
		elif argument == "--reverse": reverse_order = true
	assert(sample_steps > 0 and warm_steps > 0)
	create_timer(240.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func tick() -> void:
	for actor in actors:
		if actor is CreatureEnemy: (actor as CreatureEnemy)._move_chase(STEP, actor.combat_stop_distance)
		else: actor._combat_tick(STEP)
		actor.commit_spatial_state()

func reset_case(enabled: bool) -> void:
	wave._spatial_index.clear()
	for path in paths:
		path.chase_batch_enabled = enabled
		path.prefetch_enabled = false
		path._chase_frame = -1
		path._chase_surface_ready = false
		path._goal_frame = -1
		path._pursuit_goal_id = -1
	for index in actors.size():
		var actor := actors[index]
		actor.global_position = starts[index]
		actor.force_update_transform()
		actor.velocity = Vector3.ZERO
		actor._ground_moved = false
		actor._route.clear()
		actor._route_clock = float(index % 27) / 60.0
		actor._waypoint = 0
		actor._yield_side = 1.0 if index % 2 == 0 else -1.0
		actor.commit_spatial_state()

func sample(enabled: bool, population: int, number: int) -> Dictionary:
	reset_case(enabled)
	var warm_usec := 0
	var first_step_ms := 0.0
	for step in warm_steps:
		await physics_frame
		var started := Time.get_ticks_usec()
		tick()
		var elapsed := Time.get_ticks_usec() - started
		if step == 0: first_step_ms = float(elapsed) / 1000.0
		warm_usec += elapsed
	var times: Array[float] = []
	var positive := 0
	for step in sample_steps:
		await physics_frame
		var started := Time.get_ticks_usec()
		tick()
		times.append(float(Time.get_ticks_usec() - started) / 1000.0)
		for path in paths:
			if path._chase_batch.valid and path._chase_frame == Engine.get_physics_frames(): positive += 1
	var mean := 0.0
	for value in times: mean += value
	times.sort()
	var positions := PackedVector3Array()
	for actor in actors: positions.append(actor.global_position)
	assert(not enabled or positive > 0,"Enabled comparison must actually execute prepared pursuit queries")
	return {"enabled":enabled,"population":population,"case":number,"mean_ms":mean / times.size(),
		"p95_ms":times[int(times.size() * 0.95)],"warm_mean_ms":float(warm_usec) / warm_steps / 1000.0,"first_step_ms":first_step_ms,
		"prepared_path_steps":positive,"positions":positions,"samples":times.size()}

func populate(population: int) -> void:
	var definitions: Array[WaveMeleeEnemyDefinition] = []
	for kind in KINDS:
		var definition: WaveMeleeEnemyDefinition = load("res://data/enemies/%s.tres" % kind).duplicate()
		definition.attack_damage = 0.0
		definitions.append(definition)
		var path := wave._navigation_for(definition)
		if not paths.has(path): paths.append(path)
	var points := PackedVector3Array()
	var base := paths[0]
	for id in base.graph.get_point_ids():
		var point := base.graph.get_point_position(id)
		var offset := point - wave.player.global_position
		if Vector2(offset.x,offset.z).length() < 3.0: continue
		if not base.can_walk_direct(point,point): continue
		points.append(point)
	assert(points.size() >= population)
	for index in population:
		var definition := definitions[index % definitions.size()]
		var actor := definition.scene.instantiate() as SlimeEnemy
		actor.configure_wave({"player":wave.player,"terrain":wave.terrain,"camera":null,
			"navigation":wave._navigation_for(definition),"attack_root":wave._attack_root,
			"damage_player":func(_amount): return false,"can_damage_player":func(_amount): return false,
			"combat_active":func(): return true,"request_spawn":Callable(),"spatial_index":wave._spatial_index},definition,0)
		var point := points[(index * points.size()) / population] + Vector3.UP * 0.001
		actor.position = point
		actor.ground_movement_enabled = wave.slime_ground_movement_enabled
		world.add_child(actor)
		assert(PhysicsServer3D.body_get_space(actor.get_rid()).is_valid(),"Benchmark requires a live native body")
		actor.set_physics_process(false)
		actor.set_process(false)
		actors.append(actor)
		starts.append(point)

func run() -> void:
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(world)
	current_scene = world
	for frame in 12: await physics_frame
	wave = world.get_node("WavePrototype")
	# Controllers are called synchronously below; rendering/audio are outside this CPU workload.
	# PROCESS_MODE_DISABLED removes bodies from their physics space. Stop only
	# scripted callbacks, retaining the world's real native collision bodies.
	for node in world.find_children("*", "Node", true, false):
		node.set_physics_process(false)
		node.set_process(false)
	world.set_physics_process(false)
	world.set_process(false)
	wave.player.global_position = wave._path.ground_position(wave.player.global_position)
	wave.player.force_update_transform()
	assert(wave._path._prepare_pursuit_goal(wave.player.global_position) >= 0,"Benchmark target must be on the current formal map")
	for population in populations:
		populate(population)
		var reference := PackedVector3Array()
		var max_difference := 0.0
		for number in 4:
			var enabled := (number == 1 or number == 2) != reverse_order
			var result := await sample(enabled,population,number)
			var positions: PackedVector3Array = result.positions
			if number == 0: reference = positions
			for index in positions.size(): max_difference = maxf(max_difference,positions[index].distance_to(reference[index]))
			result.erase("positions")
			result["max_final_position_difference_m"] = max_difference
			results.append(result)
			print("PURSUIT_NET ",JSON.stringify(result))
		for actor in actors: actor.free()
		actors.clear()
		starts.clear()
		wave._spatial_index.clear()
	for path in paths: path.prefetch_enabled = false
	world.queue_free()
	for frame in 4: await physics_frame
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file: file.store_string(JSON.stringify({"purpose":"CPU ordinary chase, includes preparation, steering, real body movement and spatial commits; not FPS", "order":"on/off/off/on" if reverse_order else "off/on/on/off", "warm_steps":warm_steps,"sample_steps":sample_steps,"results":results},"\t"))
	quit(0)
