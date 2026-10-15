extends SceneTree

var world: Node3D
var wave: WavePrototype
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL: ",message)

func settle(count := 4) -> void:
	for frame in count: await physics_frame

func start(from: Vector3, target: Vector3) -> SlimeEnemy:
	wave._finish("fixture reset")
	wave.return_home()
	wave.player.body_ricochet.cancel(true)
	wave.player.global_position = wave._path.ground_position(wave.global_position) + Vector3.UP*0.03
	check(wave.start_run(), "正式挑战可以开始")
	var skills: RunSkills = wave.get_node("RunSkills")
	if skills.initial_choice.is_open:
		skills.initial_choice.reveal_now()
		skills.initial_choice.select_option(skills.initial_choice._options[0].id)
		skills.initial_choice.confirm_selection()
	for component: Node in skills._components.values(): component.process_mode = Node.PROCESS_MODE_DISABLED
	wave._spawn_queue.clear()
	check(wave._spawn_enemy(), "真实战斗史莱姆可生成")
	var enemy: SlimeEnemy = wave.enemies[-1]
	enemy.set_physics_process(false)
	enemy.spawn_delay = 0
	enemy.global_position = wave._path.ground_position(from) + Vector3.UP*0.03
	enemy.velocity = Vector3.ZERO
	wave.player.global_position = wave._path.ground_position(target) + Vector3.UP*0.03
	wave.player.velocity = Vector3.ZERO
	wave._hurt_clock = 1000
	return enemy

func box(point: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1,2,1)
	collider.shape = shape
	wall.add_child(collider)
	world.add_child(wall)
	wall.global_position = point + Vector3.UP*0.5
	return wall

func run() -> void:
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(world)
	current_scene = world
	await settle(16)
	wave = world.get_node("WavePrototype")
	wave.set_physics_process(false)
	wave.player.set_physics_process(false)
	var goal := Vector3(-5,0,42)
	# 来自当前正式地图的实机几何采样：身体合法，最近点连接却被转角遮挡。
	for point in [Vector3(7.3,0,32.2),Vector3(8.7,0,33.4),Vector3(-3.3,0,42.3),Vector3(9.4,0,46.5),Vector3(-12.7,0,47.0)]:
		var enemy := start(point, goal)
		var route := enemy.navigation.shared_pursuit_route(enemy.global_position,wave._ground_target())
		check(not route.is_empty() and enemy.navigation.shared_reachable(enemy.global_position,wave._ground_target()), "墙角合法起点具有连通追击路线："+str(point))
		check(route.size() > 1 and enemy.navigation._pursuit_start_clear(enemy.global_position,route[1]), "实际追击采用的首段不跳过墙角安全连接："+str(point))
		wave._check_reachability(wave.unreachable_timeout+0.1)
		check(wave.phase == WavePrototype.Phase.BATTLE, "墙角接触超过保护时长也不误中断："+str(point))
		if wave.phase == WavePrototype.Phase.BATTLE:
			var before := enemy.global_position
			enemy._route_clock = 0
			enemy.set_physics_process(true)
			await settle(55)
			enemy.set_physics_process(false)
			check(TerrainPath.horizontal_distance(enemy.global_position,before)>0.35, "实际怪物可离开转角："+str(point))
		await settle()
	# 使用弹射拨怪共用的真实外力接口，把怪物推到先前误报的合法落点。
	var pushed := start(Vector3(6.8,0,30.8),goal)
	var destination := Vector3(7.3,0,32.2)
	var displacement := destination - wave._path.ground_position(pushed.global_position)
	check(pushed.apply_push_impulse(displacement.normalized(),displacement.length()*8.0,0.25), "弹射拨怪的平滑外力被实际怪物接收")
	pushed._advance_push(0.25)
	check(TerrainPath.horizontal_distance(pushed.global_position,destination)<0.08, "真实胶囊外力落在捕获的墙角地面，而不是传送测试位置")
	check(pushed.navigation.shared_reachable(pushed.global_position,wave._ground_target()), "拨怪结束的合法落点仍可重新接入追击")
	wave._check_reachability(wave.unreachable_timeout+0.1)
	check(wave.phase == WavePrototype.Phase.BATTLE, "拨怪落点不触发残怪中断")
	await settle()
	# 玩家实际站点未被挡住，但该半格中心被墙体裁掉。
	for target in [Vector3(7.6,0,32.2),Vector3(8.2,0,32.2),Vector3(8.4,0,32.2)]:
		var enemy := start(goal,target)
		check(not enemy.navigation._point_blocked(wave._ground_target()), "采样目标自身确实没有碰到导航留白")
		check(enemy.navigation.shared_reachable(enemy.global_position,wave._ground_target()), "玩家站在缺失半格内仍可从邻近地面接近")
		var route := enemy.navigation.shared_pursuit_route(enemy.global_position,wave._ground_target())
		check(not route.is_empty() and route[-1].is_equal_approx(wave._ground_target()), "实际追击最终到达合法目标，不停在错误墙侧")
		wave._check_reachability(wave.unreachable_timeout+0.1)
		check(wave.phase == WavePrototype.Phase.BATTLE, "正常玩家位置不使全部怪物超时中断")
		await settle()
	var enemy := start(Vector3(-5,0,42),Vector3(-8,0,44))
	var path := enemy.navigation
	var wall := box(enemy.global_position)
	await settle()
	check(not path.shared_reachable(enemy.global_position,wave._ground_target()), "动态墙真正覆盖怪物时不得伪造穿墙路线")
	check(path.shared_pursuit_route(enemy.global_position,wave._ground_target()).is_empty(), "动态覆盖也不能产生实际追击路线")
	wave._check_reachability(3)
	var blocked_time: float = wave._unreachable.get(enemy.get_instance_id(),0.0)
	wave.set_combat_frozen(true)
	wave._physics_process(20)
	check(wave._unreachable.get(enemy.get_instance_id(),0.0) == blocked_time and wave.phase == WavePrototype.Phase.BATTLE, "升级冻结不推进真实异常计时")
	wave.set_combat_frozen(false)
	wall.queue_free()
	await settle()
	check(path.shared_reachable(enemy.global_position,wave._ground_target()), "动态墙移走后恢复可达")
	wave._check_reachability(1)
	check(wave._unreachable.get(enemy.get_instance_id(),-1.0) == 0, "恢复通路后清零异常计时，不累计正常战斗中的零散接触")
	# 不把真实异常伪装为击杀或清波，也不只通过延长超时掩盖问题。
	enemy.global_position.y -= 5
	wave._check_reachability(wave.unreachable_timeout+0.1)
	check(wave.phase == WavePrototype.Phase.RESULT and wave.result_reason.contains("无法到达") and wave.kills == 0, "真实跌落仍在原超时内中断，不伪造击杀")
	world.queue_free()
	await settle(8)
	await create_timer(0.15).timeout
	print(JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
