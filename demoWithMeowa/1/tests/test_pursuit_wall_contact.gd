extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL: ",message)

func settle(count := 4) -> void:
	for frame in count: await physics_frame

func run() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	# Keep the captured contact geometry independent of later map-scale edits.
	world.get_node("WorldDetails/BattleCourts/TreePlanter2").scale = Vector3.ONE*0.6
	root.add_child(world)
	current_scene = world
	await settle(16)
	var wave: WavePrototype = world.get_node("WavePrototype")
	var player: Player = world.get_node("Player")
	wave.set_physics_process(false)
	player.set_physics_process(false)
	player.global_position = wave.global_position + Vector3.UP*0.03
	var skills: RunSkillManager = wave.get_node("RunSkillManager")
	# This fixture requires mirror_mark, independent of the random opening draw.
	wave.skill_draft.initial_cards_per_draw = skills.skill_paths.size()
	check(wave.start_run(), "Actual mirror-skill challenge can start")
	wave.skill_draft.initial_choice.close()
	wave.skill_draft._choose_initial(&"initial:mirror_mark")
	wave.get_node("MirrorMarkAutoAttack").enabled = false
	wave._spawn_queue.clear()
	player.global_position = Vector3(2.5,0.03,44.8)
	check(wave._spawn_enemy(), "Actual slime spawns before the wall-contact regression")
	if not wave.enemies.is_empty():
		var slime := wave.enemies[0] as SlimeEnemy
		slime.set_physics_process(false)
		slime.spawn_delay = 0.0
		# Captured from stationary-player reproduction beside TreePlanter2.
		slime.global_position = Vector3(-6.875876,0.000023,53.62153)
		slime.velocity = Vector3.ZERO
		var path := slime.navigation
		var goal := wave._ground_target()
		var start := path.graph.get_point_position(path.graph.get_closest_point(slime.global_position))
		check(path._point_blocked(slime.global_position), "Navigation padding touches the real planter edge")
		check(path._segment_clear(slime.global_position,start), "The first route segment leaves that contact without another obstruction")
		check(not path.pursuit_route(slime.global_position,goal).is_empty(), "The strict original route confirms ground connectivity")
		check(path.shared_reachable(slime.global_position,goal), "A slime touching navigation padding remains reachable")
		check(not path.shared_pursuit_route(slime.global_position,goal).is_empty(), "Shared pursuit retains the escape route at the planter edge")
		var planter: Node3D = world.get_node("WorldDetails/BattleCourts/TreePlanter2")
		var inward := planter.global_position-slime.global_position
		inward.y = 0.0
		check(not path._pursuit_start_clear(slime.global_position,slime.global_position+inward.normalized()*4.0), "Initial padding contact cannot permit movement through the same planter")
		wave._check_reachability(wave.unreachable_timeout+0.1)
		check(wave.phase == WavePrototype.Phase.BATTLE, "Planter contact does not interrupt a valid challenge")
		if wave.phase == WavePrototype.Phase.BATTLE:
			var before := slime.global_position
			slime._route_clock = 0.0
			slime.set_physics_process(true)
			await settle(90)
			slime.set_physics_process(false)
			check(TerrainPath.horizontal_distance(slime.global_position,before)>0.5, "Actual slime leaves the contact instead of remaining stuck")
			check(TerrainPath.horizontal_distance(slime.global_position,goal)<TerrainPath.horizontal_distance(before,goal), "Actual pursuit continues toward the stationary player")
			# A new obstacle covering the starting point still rejects passage.
			var wall := StaticBody3D.new()
			var collision := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(1,2,1)
			collision.shape = box
			wall.add_child(collision)
			world.add_child(wall)
			wall.global_position = slime.global_position+Vector3.UP*0.5
			await settle()
			check(not path.shared_reachable(slime.global_position,goal), "A real dynamic wall covering the slime still rejects reachability")
			check(path.shared_pursuit_route(slime.global_position,goal).is_empty(), "Dynamic obstruction cannot create a route through the new wall")
			wall.free()
			await settle()
			check(path.shared_reachable(slime.global_position,goal), "Removing the dynamic wall restores the valid route")
			slime.global_position.y -= 5.0
			wave._check_reachability(wave.unreachable_timeout+0.1)
			check(wave.phase == WavePrototype.Phase.RESULT and wave.result_reason.contains("无法到达"), "A genuinely fallen enemy still interrupts the challenge")
	if wave.phase == WavePrototype.Phase.BATTLE: wave.retreat()
	await settle()
	world.queue_free()
	await settle()
	print("Pursuit wall contact: ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
