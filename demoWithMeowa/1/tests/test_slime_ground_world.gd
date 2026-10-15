extends "res://tests/test_slime_ground_movement.gd"

## Same live actors, spawn positions, map, camera and tick-based input for A/B.
## Headless times the complete enemy step; --native keeps normal node callbacks
## and records actual rendered frames without the collision diagnostic queries.
var wave: WavePrototype
var starts := PackedVector3Array()
var player_start := Vector3.ZERO
var native := false
var population := 128
var output := ""
var held_key := 0
var damage_hits := 0
var frame_label := ""
var last_draw := 0
var draws: Dictionary = {}
var overlap_details := 0
var max_penetration := 0.0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument == "--native": native = true
		elif argument.begins_with("--count="): population = argument.trim_prefix("--count=").to_int()
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	create_timer(480.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func key(value: int) -> void:
	if value == held_key: return
	for entry in [[held_key,false],[value,true]]:
		if entry[0] == 0: continue
		var event := InputEventKey.new()
		event.physical_keycode = entry[0]
		event.keycode = entry[0]
		event.pressed = entry[1]
		Input.parse_input_event(event)
	held_key = value

func drawn() -> void:
	var now := Time.get_ticks_usec()
	if not frame_label.is_empty() and last_draw > 0:
		if not draws.has(frame_label): draws[frame_label] = []
		draws[frame_label].append((now - last_draw) / 1000.0)
	last_draw = now

func stats(values: Array) -> Dictionary:
	if values.is_empty(): return {}
	values.sort()
	var sum := 0.0
	for value in values: sum += value
	return {"n":values.size(),"mean_ms":sum/values.size(),"p95_ms":values[int(values.size()*0.95)],"p99_ms":values[int(values.size()*0.99)]}

func blocked_count() -> int:
	var query := PhysicsShapeQueryParameters3D.new()
	query.collision_mask = 1
	query.exclude = path._query.exclude
	var result := 0
	for actor in actors:
		var collider: CollisionShape3D = actor.get_node("Collision")
		query.shape = collider.shape
		query.transform = collider.global_transform
		var hits := world.get_world_3d().direct_space_state.intersect_shape(query, 1)
		if not hits.is_empty():
			# Native recovery has a millimetre skin; exact contact also reports an
			# overlap on the monument's convex faces in the original solver.
			var contacts := world.get_world_3d().direct_space_state.collide_shape(query)
			var depth := 0.0
			for pair in range(0, contacts.size(), 2): depth = maxf(depth, contacts[pair].distance_to(contacts[pair+1]))
			max_penetration = maxf(max_penetration, depth)
			if depth <= maxf(0.003, actor.safe_margin * 2.0): continue
			result += 1
			if overlap_details < 4:
				overlap_details += 1
				print("OVERLAP ", actor.position, " -> ", hits[0].collider.get_path(), " margin=",query.margin," contacts=",world.get_world_3d().direct_space_state.collide_shape(query))
	return result

func replay(enabled: bool) -> Dictionary:
	frame_label = ""
	key(0)
	player.body_ricochet.cancel(true)
	player.global_position = player_start
	player.velocity = Vector3.ZERO
	wave.slime_ground_movement_enabled = enabled
	spatial.clear()
	for index in actors.size():
		actors[index].set_physics_process(false)
		reset_actor(actors[index], starts[index], enabled)
		actors[index].spawn_delay = 0.0
	await settle(12)
	(player.movement_camera as FollowCamera).snap_to_target()
	var positions_clear := true
	var steps := 0
	var ground_steps := 0
	var times := {"stand":[],"walk":[],"ricochet":[]}
	draws.clear()
	damage_hits = 0
	max_penetration = 0.0
	var flying_steps := 0
	var deflections := 0
	var visibility := {"stand":[],"walk":[],"ricochet":[]}
	var release := false
	var charge := false
	for actor in actors: actor.set_physics_process(native)
	for tick in 600:
		await physics_frame
		frame_label = "stand" if tick < 240 else ("walk" if tick < 420 else "ricochet")
		if tick % 60 == 0:
			var visible := 0
			for actor in actors:
				if player.movement_camera.is_position_in_frustum(actor.global_position + Vector3.UP*0.5): visible += 1
			visibility[frame_label].append(visible)
		if tick >= 240 and tick < 420: key([KEY_D,KEY_S,KEY_A,KEY_W][((tick-240)/45)%4])
		if tick == 420:
			key(0)
			var nearest := actors[0]
			for actor in actors:
				if actor.global_position.distance_squared_to(player.global_position) < nearest.global_position.distance_squared_to(player.global_position): nearest = actor
			charge = player.body_ricochet.begin_charge((nearest.global_position - player.global_position).normalized())
		if tick == 480: release = player.body_ricochet.release_charge()
		if not native:
			var stamp := Time.get_ticks_usec()
			for actor in actors: actor._physics_process(1.0 / 60.0)
			times[frame_label].append((Time.get_ticks_usec()-stamp)/1000.0)
			for actor in actors:
				if actor._ground_moved: ground_steps += 1
			if tick % 15 == 0:
				var clear := blocked_count() == 0
				positions_clear = positions_clear and clear
		steps += 1
		if player.body_ricochet.flying: flying_steps += 1
		deflections = maxi(deflections, player.body_ricochet.crowd_deflection_count)
	frame_label = ""
	key(0)
	for actor in actors: actor.set_physics_process(false)
	check(charge and release and flying_steps > 0, "正式图真实蓄力和弹射正常，ground=%s" % enabled)
	check(deflections > 0 and damage_hits > 0, "弹射仍沿怪群外沿转向并实际挥剑命中，ground=%s" % enabled)
	if not native: check(positions_clear, "正式图移动中胶囊不侵入建筑（原生接触皮肤 3mm 容差），ground=%s" % enabled)
	check(wave.enemies.size() == population and not wave.player.ricochet_rules.enemy_push_enabled, "保持完整怪群数量与正式弹射规则")
	var spacing: Array[float] = []
	var visible := 0
	for actor in actors:
		var nearest := INF
		for other in actors:
			if actor != other: nearest = minf(nearest, TerrainPath.horizontal_distance(actor.position, other.position))
		spacing.append(nearest)
		if player.movement_camera.is_position_in_frustum(actor.global_position + Vector3.UP*0.5): visible += 1
	spacing.sort()
	var result := {"count":population,"ground":enabled,"native":native,"steps":steps,"ground_steps":ground_steps,"flying_steps":flying_steps,"deflections":deflections,"sword_hits":damage_hits,"visible_end":visible,"median_spacing":spacing[spacing.size()/2],"max_penetration_m":max_penetration if not native else null,"enemy_cpu":{},"rendered_frames":{}}
	for label in times: result.enemy_cpu[label] = stats(times[label])
	result.visibility = visibility
	for label in draws: result.rendered_frames[label] = stats(draws[label])
	print("WORLD ", JSON.stringify(result))
	if native and not output.is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.trim_suffix(".json") + ("-ground.png" if enabled else "-legacy.png"))
	return result

func run() -> void:
	# A headless world otherwise spins display callbacks freely between fixed
	# physics steps. Limit only that diagnostic to the same 60 Hz callback load.
	if not native: Engine.max_fps = 60
	if native:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		RenderingServer.frame_post_draw.connect(drawn)
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	wave = world.get_node("WavePrototype")
	wave.slime_ground_movement_enabled = false
	wave.enemy_catalog = null
	wave.population_rules = wave.population_rules.duplicate(true)
	wave.population_rules.simulation_mode = true
	wave.population_rules.simulation_enemy_count = population
	wave.population_rules.simulation_skills.clear()
	root.add_child(world)
	current_scene = world
	player = wave.player
	terrain = wave.terrain
	path = wave._path
	spatial = wave._spatial_index
	await settle(20)
	check(wave.start_run(), "正式地图开始史莱姆零伤害模拟")
	var center := wave.battle_area.get_center()
	player.global_position = path.graph.get_point_position(path.closest_point(Vector3(center.x,0,center.y))) + Vector3.UP*0.03
	await settle(12)
	player_start = player.global_position
	while wave.enemies.size() < population: await physics_frame
	await settle(480)
	for actor: SlimeEnemy in wave.enemies:
		actors.append(actor)
		starts.append(actor.global_position)
		actor.set_physics_process(false)
		actor.damaged.connect(func(_event): damage_hits += 1)
	wave.set_physics_process(false)
	var results: Array[Dictionary] = []
	var modes := [false,true,true,false] if "--abba" in OS.get_cmdline_user_args() else [false,true]
	if "--ground-first" in OS.get_cmdline_user_args(): modes = [true,false,false,true] if modes.size() == 4 else [true,false]
	for enabled in modes:
		results.append(await replay(enabled))
	if not output.is_empty():
		FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"engine":Engine.get_version_info().string,"gpu":RenderingServer.get_video_adapter_name(),"viewport":str(root.size),"camera":{"fov":player.movement_camera.fov,"distance":player.movement_camera.get("distance"),"pitch":player.movement_camera.get("pitch_degrees")},"results":results,"failures":failures},"\t"))
	wave.retreat()
	actors.clear()
	world.queue_free()
	await settle()
	print(JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
