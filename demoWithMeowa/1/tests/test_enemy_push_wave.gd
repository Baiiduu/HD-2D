extends SceneTree

const SESSION := preload("res://tests/fixtures/ricochet_session.gd")
var world: Node3D
var terrain: Terrain
var session: WavePrototype
var player: Player
var path := TerrainPath.new()
var actors: Array[SlimeEnemy] = []
var checks := 0
var failures := 0

func _initialize() -> void:
	create_timer(60).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle(count := 3) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func spawn(point: Vector3, id := "wave_slime") -> SlimeEnemy:
	var data: WaveEnemyDefinition = load("res://data/enemies/%s.tres" % id).duplicate()
	var actor := data.scene.instantiate() as SlimeEnemy
	actor.configure_wave({"player": player, "terrain": terrain, "camera": null, "navigation": path,
		"attack_root": session._attack_root, "spatial_index": session._spatial_index,
		"damage_player": func(_amount): pass, "request_spawn": Callable(), "combat_active": session.combat_active}, data, 0.0)
	world.add_child(actor)
	actor.global_position = point + Vector3.UP * 0.03
	actor.set_physics_process(false)
	actors.append(actor)
	session.enemies.append(actor)
	session._spatial_index.update(actor)
	return actor

func cleanup() -> void:
	session.set_combat_frozen(false)
	player.body_ricochet.cancel(true)
	for actor in actors: actor.cancel()
	actors.clear()
	session.enemies.clear()
	await settle()

func advance(seconds: float, step := 1.0 / 60.0) -> void:
	var age := 0.0
	while age < seconds - 0.000001:
		var delta := minf(step, seconds - age)
		for actor in actors: actor._advance_push(delta)
		age += delta

func rules() -> PlayerRicochetRules:
	return load("res://data/player/body_ricochet.tres").duplicate()

func begin(actor: WaveEnemy, settings: PlayerRicochetRules = null) -> EnemyPushWave:
	var selected := settings if settings else rules()
	var body := player.body_ricochet
	body._settings = selected
	body._pushed.clear()
	body._push_wave = null
	check(body._apply_push(actor, Vector3.RIGHT), "人物共用入口施加真实推浪")
	return body._push_wave

func box(point: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var geometry := BoxShape3D.new()
	geometry.size = Vector3(0.02, 1.2, 5)
	shape.shape = geometry
	wall.add_child(shape)
	world.add_child(wall)
	wall.position = point
	return wall

func outline() -> Dictionary:
	return {"center": Vector3(0, 0.03, 0), "u": Vector3.RIGHT, "v": Vector3.BACK, "radii": Vector2(2.0, 1.5)}

func launch(actor: SlimeEnemy, settings: PlayerRicochetRules = null, region: Dictionary = {}) -> EnemyPushWave:
	var selected := settings if settings else rules()
	var wave := EnemyPushWave.new(selected)
	check(wave.push(actor, Vector3.FORWARD, selected.push_initial_speed, selected.push_seconds, selected.push_stun_seconds, 0, region if not region.is_empty() else outline()), "真实绕行入口可用")
	return wave

func region_checks() -> void:
	var mob := spawn(Vector3(-2, 0, 0))
	var sum := mob.global_position
	for x in range(1, 7):
		var other := spawn(Vector3(-2 + x * 0.65, 0, (x % 2) * 0.3))
		sum += other.global_position
	var distant := spawn(Vector3(9, 0, 0))
	var warning := spawn(Vector3(-2, 0, 0.1))
	warning.spawn_delay = 1.0
	var high := spawn(Vector3(-2, 1, 0.1))
	var wave := begin(mob)
	var region := mob._orbit.region
	check(TerrainPath.horizontal_distance(region.center, sum / 7.0) < 0.001, "椭圆围绕附近连通怪群，不围绕人物")
	check(not wave._regions.has(distant.get_instance_id()) and not wave._regions.has(warning.get_instance_id()) and not wave._regions.has(high.get_instance_id()), "远处散怪、预告及异层不拉大区域")
	check(region.radii.x > region.radii.y * 1.5, "细长怪群生成有长短轴的椭圆")
	for actor in actors.slice(0, 7):
		var offset: Vector3 = actor.global_position - region.center
		var q := Vector2(offset.dot(region.u) / region.radii.x, offset.dot(region.v) / region.radii.y)
		check(q.length() < 1.0, "不规则怪群被平滑轮廓包住")
	var fixed_center: Vector3 = region.center
	mob._advance_push(0.2)
	check(region.center == fixed_center, "移动后本次圆心保持固定")
	var other := actors[3]
	wave.push(other, Vector3.RIGHT, 24, 0.36, 1)
	check(other._orbit.region == region, "同片怪群共用首次命中的区域")
	await cleanup()
	mob = spawn(Vector3.ZERO)
	begin(mob)
	check(mob._orbit.length > 1.0 and mob._orbit.points[0] == mob.global_position, "单只怪使用连续的小圆弧，不从圆心瞬移")
	await cleanup()
	for number in range(-3, 4): spawn(Vector3(number * 0.65, 0, number * 0.65))
	mob = actors[0]
	wave = begin(mob)
	region = mob._orbit.region
	check(absf(region.u.dot(Vector3(1,0,1).normalized())) > 0.99, "斜向细长怪群的椭圆长轴跟随怪群方向")
	var queries := session._spatial_index.candidate_checks
	var settings := wave.rules
	settings.push_chain_layers = 0
	advance(0.3)
	check(session._spatial_index.candidate_checks == queries, "已建立轮廓不逐帧重新扫描怪群")
	await cleanup()

func orbit_checks() -> void:
	for clockwise in [true, false]:
		var mob := spawn(Vector3(-2, 0, 0))
		var settings := rules()
		settings.clockwise = clockwise
		settings.push_chain_layers = 0
		launch(mob, settings)
		var path := mob._orbit
		var midpoint := path.points[path.points.size() / 2]
		check(midpoint.z < -1.3 if clockwise else midpoint.z > 1.3, "旋向沿怪群外缘，Q/E 不参与世界轨迹")
		check(path.points[0].is_equal_approx(mob.global_position), "起点严格连续")
		for point in path.points:
			check(absf(Vector2(point.x / 2.0, point.z / 1.5).length() - 1.0) < 0.001, "外排沿椭圆而非直穿内部")
		mob._advance_push(path.duration + 0.01)
		check(TerrainPath.horizontal_distance(mob.global_position, Vector3(2, 0, 0)) < 0.001 and not mob.is_orbiting(), "绕行半圈到对侧边沿后停止")
		await cleanup()
	var mob := spawn(Vector3(-0.8, 0, 0))
	launch(mob)
	var path := mob._orbit
	check(path.points[0] == mob.global_position and path.points[1].distance_to(path.points[0]) < 0.13, "内排平滑并入外沿，没有起步瞬移")
	mob._advance_push(path.duration)
	check(TerrainPath.horizontal_distance(mob.global_position, Vector3(2,0,0)) < 0.001, "内排也到达外沿对侧")
	await cleanup()
	var base := EnemyOrbitPath.new(outline(), Vector3(-2,0.03,0), Vector3.FORWARD, true, 24, 0.36, 1)
	var grown := EnemyOrbitPath.new(outline(), Vector3(-2,0.03,0), Vector3.FORWARD, true, 24, 0.72, 1)
	check(grown.duration > base.duration and grown.points[-1] == base.points[-1], "持续成长增加缓冲但不让怪物绕过对侧继续整圈")
	var stronger := EnemyOrbitPath.new(outline(), Vector3(-2,0.03,0), Vector3.FORWARD, true, 36, 0.36, 1)
	check(stronger.duration < base.duration and stronger.initial_speed > base.initial_speed, "推力成长提高绕行速度，终点仍在对侧")
	mob = spawn(Vector3(-2,0,0), "pot_brood")
	mob.knockback_multiplier = 0.5
	launch(mob)
	check(mob._orbit.length < 5.0 and mob.stun_remaining == 0.5, "重型保留较短绕行与独立眩晕抗性")
	await cleanup()

func chain_checks() -> void:
	for layers in [0, 1, 4]:
		var mob := spawn(Vector3(-2,0,0))
		for angle in [0.3, 0.65, 1.0, 1.35]: spawn(Vector3(-2*cos(angle), 0, -1.5*sin(angle)))
		var settings := rules()
		settings.push_chain_layers = layers
		var wave := launch(mob, settings)
		var region := mob._orbit.region
		advance(3.0)
		check(wave.affected_count == 1 if layers == 0 else wave.affected_count >= 2, "接力可关闭，开启后真实碰撞带入同伴")
		check(actors.all(func(actor): return actor._push_layer <= layers), "接力严格遵守层数")
		if layers > 0:
			check(actors[1]._push_layer == 1 and is_equal_approx(actors[1].stun_remaining, 0.85), "同伴眩晕按层衰减")
			check(wave.has_target(actors[1].get_instance_id()), "直接与间接受击共用去重")
		check(actors.all(func(actor): return actor.health == actor.max_health), "绕行与接力没有附加伤害")
		check(not wave.push(mob, Vector3.LEFT, 24, 0.36, 1), "同次发射不能反向反复绕行")
		await cleanup()
	var mob := spawn(Vector3(-2,0,0))
	var other := spawn(Vector3(-1.94,0,-0.45))
	other.knockback_multiplier = 0.0
	launch(mob)
	mob._advance_push(0.05)
	check(other.stun_remaining > 0.0 and not other.is_orbiting(), "抗移动仍可眩晕，不冒充移动传播者")
	await cleanup()
	for property in [&"push_group_link_distance", &"push_group_search_radius", &"push_group_edge_margin", &"push_arrival_arc_degrees", &"push_chain_speed_retention"]:
		var settings := rules()
		settings.set(property, NAN)
		check(not settings.validation_error().is_empty(), "拒绝无效绕行参数：" + String(property))

func wall_checks() -> void:
	var mob := spawn(Vector3(-2,0,0))
	var wall := box(Vector3(0,0.6,-1.5))
	await settle()
	launch(mob)
	mob._advance_push(mob._orbit.duration + 0.01)
	check(mob.global_position.x < -0.27 and mob.global_position.z < -1.0 and not mob.is_orbiting(), "弧线遇真实薄墙停在接触处，不直穿墙体")
	wall.position.x = 7
	await settle()
	mob.global_position = Vector3(-2,0.03,0)
	session._spatial_index.update(mob)
	launch(mob)
	mob._advance_push(mob._orbit.duration + 0.01)
	check(TerrainPath.horizontal_distance(mob.global_position, Vector3(2,0,0)) < 0.001, "动态障碍移开立即恢复绕行")
	wall.queue_free()
	await cleanup()
	mob = spawn(Vector3(-2,0,0))
	var water_cell := terrain.data.world_to_cell(Vector3(0,0,-1.5))
	terrain.data.set_overlay(water_cell, TerrainData.OVERLAY_WATER, true)
	launch(mob)
	mob._advance_push(mob._orbit.duration + 0.01)
	check(mob.global_position.x < 0.01 and not mob.is_orbiting(), "弯曲绕行遇水面终止，不越过水区到对侧")
	terrain.data.set_overlay(water_cell, TerrainData.OVERLAY_WATER, false)
	await cleanup()
	mob = spawn(Vector3(-2,0,0))
	wall = box(Vector3(-1.5,0.6,0))
	var other := spawn(Vector3(-1,0,0))
	await settle()
	var wave := begin(mob)
	check(not wave._regions.has(other.get_instance_id()), "分隔墙两侧不归同一怪群")
	wall.queue_free()
	await cleanup()

func timing_checks() -> void:
	var endpoints: Array[Vector3] = []
	var received: Array[float] = []
	for steps in [1, 120]:
		var mob := spawn(Vector3(-2,0,0))
		var target := spawn(Vector3(-2*cos(0.8),0,-1.5*sin(0.8)))
		launch(mob)
		var duration := mob._orbit.duration
		for frame in steps: mob._advance_push(duration / steps)
		endpoints.append(mob.global_position)
		received.append(target._push_speed)
		check(target.stun_remaining > 0, "低帧率逐段弧线扫掠仍接触同伴")
		await cleanup()
	check(endpoints[0].distance_to(endpoints[1]) < 0.001, "绕行落点不随帧率改变")
	check(absf(received[0] - received[1]) < 0.03, "同伴接收到的速度不随帧率大幅变化")
	var mob := spawn(Vector3(-2,0,0))
	var wave := launch(mob)
	var before := mob.global_position
	session.set_combat_frozen(true)
	mob._physics_process(0.1)
	check(mob.global_position == before and mob.stun_remaining == 1.0, "升级冻结轨迹和控制计时")
	session.set_combat_frozen(false)
	mob._physics_process(0.1)
	check(mob.global_position.distance_to(before) > 0.1, "恢复后从原轨迹继续")
	var next_wave := EnemyPushWave.new(rules())
	check(next_wave.push(mob, Vector3.FORWARD, 24, 0.36, 1), "新发射使用独立记录和新区域")
	await cleanup()
	mob = spawn(Vector3(-2,0,0))
	launch(mob)
	mob._advance_push(0.08)
	mob.apply_knockback(Vector3.BACK, 0.3)
	var displaced := mob.global_position
	mob._advance_push(0.1)
	check(not mob.is_orbiting() and mob.global_position == displaced, "其它攻击的新击退接管后，不被旧轨迹拉回")
	await cleanup()
	mob = spawn(Vector3(-2,0,0))
	launch(mob)
	mob.stun_remaining = 0.0
	var before_orbit := mob.global_position
	mob._physics_process(0.05)
	check(mob.global_position.distance_to(before_orbit) > 0.1 and mob.is_orbiting(), "眩晕提前结束仍保持外力，不叠加普通追击")
	await cleanup()

func arrival_checks() -> void:
	for clockwise in [true, false]:
		var region := outline()
		var landings: Array[Vector3] = []
		for index in 20:
			var angle := PI + (TAU * index / 20.0)
			var start := Vector3(2*cos(angle), 0.03, 1.5*sin(angle))
			var path := EnemyOrbitPath.new(region, start, Vector3.FORWARD, clockwise, 24, 0.36, 1)
			var end := path.points[-1]
			check(end.x > 0.0, "各方位卷入的怪都到最初受击侧的对面，不围成空心圈")
			check(landings.all(func(point): return point.distance_to(end) > 0.05), "后沿落点错开，不叠在同一点")
			landings.append(end)
		check(landings.any(func(point): return point.x < 1.5) and landings.any(func(point): return point.x > 2.3), "落点同时有横向宽度和前后厚度")
	var region := outline()
	region["arrival_angle"] = 0.0
	var already_back := EnemyOrbitPath.new(region, Vector3(2*cos(0.3),0.03,1.5*sin(0.3)), Vector3.FORWARD, true, 24, 0.36, 1)
	var stayed_back := true
	for point in already_back.points:
		if point.x <= 1.0: stayed_back = false
	check(stayed_back, "已经位于后沿的怪就近收势，不额外绕一整圈")

func crowd_checks() -> void:
	for x in 9:
		for z in range(-3, 4): spawn(Vector3(-2.4 + x * 0.55,0,z * 0.5))
	var positions := {}
	for actor in actors: positions[actor] = actor.global_position
	var wave := begin(actors[3])
	var region := actors[3]._orbit.region
	for z in range(0,7):
		var actor := actors[z]
		if not wave.has_target(actor.get_instance_id()): wave.push(actor, Vector3.FORWARD, 24, 0.36, 1)
	advance(5.0)
	var moved := 0
	for actor in actors:
		if TerrainPath.horizontal_distance(actor.global_position, positions[actor]) > 0.5: moved += 1
	check(wave.affected_count > 7 and moved > 7, "密集怪阵前排带动同伴绕行，形成批量翻到对侧的移动")
	check(actors.all(func(actor): return actor.health == actor.max_health), "密集绕行保留真实生命")
	print("Crowd orbit: affected=", wave.affected_count, " moved=", moved, " radii=", region.radii)
	await cleanup()

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	terrain = Terrain.new()
	var data := TerrainData.new()
	data.size = Vector2i.ZERO
	data.resize(Vector2i(-12, -12), Vector2i(24, 24))
	terrain.data = data
	world.add_child(terrain)
	session = SESSION.new()
	session.name = "WavePrototype"
	session.terrain = terrain
	session.phase = WavePrototype.Phase.BATTLE
	world.add_child(session)
	session._attack_root = Node3D.new()
	session.add_child(session._attack_root)
	player = Player.new()
	player.name = "Player"
	player.animations = load("res://assets/meowa/player/animations.tres")
	player.ricochet_rules = rules()
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
	player.position = Vector3(-8, 0.03, 0)
	await settle(8)
	player.set_physics_process(false)
	if player.sword: player.sword.set_physics_process(false)
	path.build(terrain, 0.32, [player.get_rid()])
	await region_checks()
	await orbit_checks()
	await chain_checks()
	await wall_checks()
	await timing_checks()
	await arrival_checks()
	await crowd_checks()
	world.queue_free()
	await settle(4)
	print("Enemy crowd orbit: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
