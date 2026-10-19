extends "res://tests/test_preview_query_view.gd"

const OLD_OUTLINE = preload("res://tests/fixtures/legacy_orbit_outline.gd")
const OLD_EXPANSION = preload("res://tests/fixtures/legacy_orbit_expansion.gd")
const ECCENTRIC = preload("res://scripts/player/player_eccentric_ricochet.gd")
const OBSTACLES = preload("res://scripts/combat/preview_obstacle_batch.gd")

class CountingView extends "res://scripts/combat/preview_spatial_query_view.gd":
	var queries := 0
	func nearby_slots_into(point: Vector3, radius: float, excluded: Dictionary[int, bool], result: Array[int]) -> void:
		queries += 1
		super.nearby_slots_into(point, radius, excluded, result)

func outline_bytes(value: Dictionary) -> PackedByteArray:
	return var_to_bytes([] if value.is_empty() else [value.positions, value.body_radius, value.player_radius, value.members.keys()])

func compare_outline(label: String, allowed: Dictionary[int, WaveEnemy] = {}, expect_reduction := false) -> void:
	var rules: PlayerRicochetRules = player.ricochet_rules.duplicate()
	rules.eccentric_minimum_members = 1
	var old = OLD_OUTLINE.new(rules, session)
	var current := PlayerCrowdDeflection.new(rules, session)
	old.debug_enabled = true
	current.debug_enabled = true
	var old_view := CountingView.new(session._spatial_index, session)
	var new_view := CountingView.new(session._spatial_index, session)
	check(new_view.is_current(session._spatial_index), "使用正式控制器和索引的同步查询视图")
	var seed := session.enemies[0]
	var point := Vector3(-2, 0.03, -2)
	var expected: Dictionary = old._view_eccentric_outline(old_view.slot(seed), point, allowed, old_view, OBSTACLES.new(terrain, [player.get_rid()]))
	var actual := current._view_eccentric_outline(new_view.slot(seed), point, allowed, new_view, OBSTACLES.new(terrain, [player.get_rid()]))
	check(outline_bytes(actual) == outline_bytes(expected), "成员顺序、位置和真实半径逐字节保持：" + label)
	check(current.debug_capture_reason == old.debug_capture_reason, "群体分布与诊断原因保持：" + label)
	check(outline_bytes(current._eccentric_outline(seed, point, allowed)) == outline_bytes(expected), "正式接群入口与旧结果一致：" + label)
	if expect_reduction:
		check(new_view.queries < old_view.queries, "成员已全部收集后不再发起无效邻域查询：" + label)
		print(JSON.stringify({"case":label, "members":session.enemies.size(), "neighbor_queries":{"old":old_view.queries, "new":new_view.queries}}))

func geometry_checks() -> void:
	var rules := PlayerRicochetRules.new()
	var current = ECCENTRIC.new(rules)
	var old = OLD_EXPANSION.new(rules)
	var formations: Array[PackedVector3Array] = [
		PackedVector3Array([Vector3.ZERO]),
		PackedVector3Array([Vector3(-0.4, 0, 0), Vector3(0.4, 0, 0)]),
		PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]),
		PackedVector3Array([Vector3(-0.5, 0.03, -0.5), Vector3(0.5, 0.03, -0.5), Vector3(0.3, 0.03, 0.5), Vector3(-0.2, 0.03, 0.25)]),
		PackedVector3Array([Vector3(-3.1234567, 0.17, 4.765432), Vector3(0.235711, 0.02, -0.6180339), Vector3(0.235712, 0.02, -0.618034)])]
	for points in formations:
		for radius in [0.05, 0.57, 0.57, 0.86, 0.57]:
			check(var_to_bytes(current._expanded_outline(points, radius)) == var_to_bytes(old._expanded_outline(points, radius)), "角度、圆角精度与体型变更后的外包线逐字节一致")
		for clockwise in [true, false]:
			rules.clockwise = clockwise
			current.interrupt()
			old.interrupt()
			var point := Vector3(-5, 0.03, -2)
			var heading := Vector3.RIGHT
			for segment in 3:
				var surface := {"positions":points, "body_radius":0.3 + segment * 0.07, "player_radius":0.24}
				var expected: PackedVector3Array = old.build(point, heading, surface)
				var actual: PackedVector3Array = current.build(point, heading, surface)
				check(var_to_bytes(actual) == var_to_bytes(expected), "首次与连续环绕的全部采样点逐字节一致")
				check(current.turning == old.turning and current.outgoing == old.outgoing and current.presentation_center == old.presentation_center, "运动方向和取景中心保持")
				check(current.departure_heading(point, heading) == old.departure_heading(point, heading), "主动脱离方向保持")
				if not actual.is_empty():
					point = actual[-1]
					heading = current.outgoing

func run() -> void:
	geometry_checks()
	await fixture()
	await populate(8)
	wall.position.x = 20.0
	for i in session.enemies.size():
		var actor := session.enemies[i]
		actor.global_position = Vector3((i % 4) * 0.3, 0.03, (i / 4) * 0.4)
		actor.commit_spatial_state()
	await settle()
	compare_outline("紧凑八怪", {}, true)
	var allowed: Dictionary[int, WaveEnemy] = {}
	for i in 3: allowed[session.enemies[i].get_instance_id()] = session.enemies[i]
	compare_outline("续段仅保留已捕获三怪", allowed, true)
	for i in range(4, 8):
		session.enemies[i].global_position.z += 3.0
		session.enemies[i].commit_spatial_state()
	compare_outline("可见但不相连的第二群")
	session.enemies[2].spawn_delay = 1.0
	session.enemies[2].commit_spatial_state()
	session.enemies[1].global_position.y = 2.0
	session.enemies[1].commit_spatial_state()
	compare_outline("激活状态和异层对象即时更新")
	session.enemies[3].body_radius = 0.53
	session.enemies[3].commit_spatial_state()
	for child in player.get_children():
		if child is CollisionShape3D: child.scale = Vector3.ONE * 1.2
	compare_outline("怪物体型与人物胶囊缩放即时更新")
	wall.position = Vector3(0.45, 0.5, 0)
	wall.get_child(0).shape.size = Vector3(0.025, 1, 6)
	await settle()
	compare_outline("动态薄墙")
	wall.collision_layer = ProjectileCollision.MIRROR_SURFACE.COLLISION_LAYER
	await settle()
	compare_outline("镜面遮挡")
	wall.position.x = 20.0
	await settle()
	session.enemies[3].dead = true
	session._spatial_index.remove(session.enemies[3])
	compare_outline("成员死亡后重新读取")
	clear_enemies()
	await populate(1)
	session.enemies[0].global_position = Vector3.ZERO
	session.enemies[0].commit_spatial_state()
	compare_outline("孤立单怪", {}, true)
	body.cancel(true)
	clear_enemies()
	world.queue_free()
	await settle()
	print("Orbit geometry reuse: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
