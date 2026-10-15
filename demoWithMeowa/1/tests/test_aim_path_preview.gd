extends SceneTree

const SESSION := preload("res://tests/fixtures/ricochet_session.gd")
var checks := 0
var failures := 0
var world: Node3D
var terrain: Terrain
var session: WavePrototype
var player: Player
var body: PlayerRicochet
var navigation := TerrainPath.new()
var query := BodyPathPrediction.new()

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle(frames := 3) -> void:
	for frame in frames:
		await physics_frame
		await process_frame

func reset() -> void:
	body.cancel(true)
	player.global_position = Vector3(0, 0.03, 0)
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	await settle(6)
	player.set_physics_process(false)
	player.sword.set_physics_process(false)

func predict(heading := Vector3.RIGHT, bounces := 1, distance := 12.0) -> AimPathData:
	await reset()
	check(body.begin_charge(heading), "从地面开始预览")
	body.advance(0.8, Vector3.ZERO, false)
	var route := AimPathData.new()
	body.predict_path(query, route, distance, bounces)
	return route

func box(position: Vector3, size: Vector3, yaw := 0.0) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	wall.add_child(collision)
	world.add_child(wall)
	wall.position = position
	wall.rotation.y = yaw
	return wall

func enemy(point: Vector3) -> SlimeEnemy:
	var data: WaveEnemyDefinition = load("res://data/enemies/wave_slime.tres").duplicate()
	var actor := data.scene.instantiate() as SlimeEnemy
	actor.configure_wave({"player": player, "terrain": terrain, "camera": null, "navigation": navigation,
		"attack_root": session._attack_root, "spatial_index": session._spatial_index,
		"damage_player": func(_amount): pass, "request_spawn": Callable(), "combat_active": session.combat_active}, data, 0.0)
	world.add_child(actor)
	actor.global_position = point + Vector3.UP * 0.03
	actor.set_physics_process(false)
	session.enemies.append(actor)
	session._spatial_index.update(actor)
	return actor

func clear_enemies() -> void:
	for actor in session.enemies:
		if is_instance_valid(actor): actor.queue_free()
	session.enemies.clear()
	session._spatial_index.clear()

func compare_flight(route: AimPathData, label: String) -> void:
	var expected: Vector3 = route.segments.back().end
	body.release_charge()
	for frame in 600:
		if not body.flying: break
		body.advance(1.0 / 60.0, Vector3.ZERO, false)
	check(TerrainPath.horizontal_distance(player.global_position, expected) < 0.06, "预览与 60Hz 实际胶囊终点一致：" + label)

func path_checks() -> void:
	var route: AimPathData = await predict()
	check(route.segments.size() == 1 and route.contacts.is_empty() and is_equal_approx(route.total_distance, 12.0), "空地路线按实际耗速积分至最低速度")
	var point := player.global_transform
	var velocity := player.velocity
	var clock := player.sword._since_strike
	body.predict_path(query, route, 12.0, 1)
	check(player.global_transform == point and player.velocity == velocity and player.sword._since_strike == clock, "只读预测不移动人物、不重置攻击时钟")
	await compare_flight(route, "空地")
	for yaw in [0.0, PI / 4.0]:
		var wall := box(Vector3(3, 0.6, 0), Vector3(0.02, 1.2, 8), yaw)
		await settle()
		route = await predict()
		check(route.contacts.size() == 1 and route.segments.size() == 2, "薄墙／斜墙显示一次真实反弹")
		check(route.segments[1].heading.dot(Vector3.RIGHT) < 0.01, "反射方向来自实际接触法线")
		await compare_flight(route, "薄墙／斜墙")
		wall.queue_free()
		await settle()
	var wall := box(Vector3(3, 0.6, 0), Vector3(0.02, 1.2, 8))
	await settle()
	route = await predict(Vector3.RIGHT, 0)
	check(route.segments.size() == 1 and route.end_reason == &"preview_limit", "预览预算只限制显示，不限制人物续弹")
	var first := route.contacts[0]
	wall.position.x = 5.0
	await settle()
	body.predict_path(query, route, 12.0, 1)
	check(route.contacts[0].x > first.x + 1.9, "动态墙移动后重新查询，不复用过期碰撞")
	wall.queue_free()
	await settle()
	route = await predict(Vector3.RIGHT, 1, 2.0)
	check(route.total_distance <= 2.00001 and route.end_reason == &"distance", "最长显示距离可截断，不把整张地图铺满")
	player.bounds = Rect2(-2, -2, 4, 4)
	route = await predict()
	check(route.segments.back().end.x <= 2.00001 and route.contacts.is_empty(), "地图边界停止预览，不伪造反弹")
	player.bounds = Rect2(-18, -18, 36, 36)
	for kind in ["water", "cliff"]:
		if kind == "water": terrain.data.set_overlay(Vector2i(1, 0), TerrainData.OVERLAY_WATER, true)
		else: terrain.data.set_level(Vector2i(1, 0), 1)
		await settle()
		route = await predict()
		check(route.segments.back().end.x < 1.0 and route.contacts.is_empty(), "水面／断层与真实弹射共用终止资格：" + kind)
		terrain.data.set_overlay(Vector2i(1, 0), TerrainData.OVERLAY_WATER, false)
		terrain.data.set_level(Vector2i(1, 0), 0)
		await settle()
	player.ricochet_rules.bounce_speed_retention = 0.5
	wall = box(Vector3(3, 0.6, 0), Vector3(0.02, 1.2, 8))
	await settle()
	route = await predict()
	await compare_flight(route, "反弹减速")
	player.ricochet_rules.bounce_speed_retention = 1.0
	wall.queue_free()
	await settle()

func target_checks() -> void:
	var near := enemy(Vector3(2, 0, 0.35))
	var far := enemy(Vector3(4, 0, 0))
	var behind := enemy(Vector3(-0.5, 0, 0))
	var high := enemy(Vector3(0.8, 1.3, 0))
	var warning := enemy(Vector3(0.7, 0, 0))
	warning.spawn_delay = 1.0
	var route: AimPathData = await predict()
	var health := near.health
	check(player.sword.preview_target(route) == near, "首目标复用挥剑宽度，排除身后、高处和预告中怪物")
	check(near.health == health and far.health == far.max_health, "选中目标不会造成伤害或拨怪")
	var effect := body._charge_effect
	check(effect._target_enemy == near and effect._aim._target.visible, "仅首个预计可触及目标显示角标")
	var bounds: Rect2i = effect._aim._bounds[near.sprite.texture]
	check(bounds.size.x > 0 and bounds.size.x < near.sprite.texture.get_width(), "压缩图集先解压再读取原生透明边界，角标围住实际身体")
	near.dead = true
	effect._process(0.0)
	check(not effect._aim._target.visible, "目标死亡立即隐藏角标，不保留死亡引用")
	body.advance(0.0, Vector3.ZERO, false)
	check(effect._target_enemy == far, "首目标消失后更新下一有效目标")
	clear_enemies()
	await settle()
	enemy(Vector3(2, 0, 1.3))
	var wall := box(Vector3(2, 0.6, 0.65), Vector3(6, 1.2, 0.02))
	await settle()
	route = await predict()
	check(player.sword.preview_target(route) == null, "虚线附近但隔墙的怪物不能成为提示目标")
	wall.queue_free()
	clear_enemies()
	await settle()
	behind = enemy(Vector3(-1, 0, 0))
	wall = box(Vector3(2, 0.6, 0), Vector3(0.02, 1.2, 8))
	await settle()
	route = await predict()
	check(player.sword.preview_target(route) == behind, "按路线先后顺序查找，支持反弹后首次触及的目标")
	var renderer := effect._aim
	var mesh := renderer._lines.multimesh.mesh
	var material := renderer._line_material
	var previous: Vector3 = effect._route.segments.back().end
	session.set_combat_frozen(true)
	wall.position.x += 1.0
	body.advance(0.3, Vector3.ZERO, false)
	check(effect._route.segments.back().end == previous, "升级冻结保留路线快照")
	session.set_combat_frozen(false)
	body.advance(0.0, Vector3.ZERO, false)
	check(renderer._lines.multimesh.mesh == mesh and renderer._line_material == material, "刷新和恢复复用网格、材质和实例缓冲")
	player.action_visuals.preview_show_target = false
	body.advance(0.0, Vector3.ZERO, false)
	check(renderer.visible and not renderer._target.visible, "角标可以独立关闭，虚线路线保留")
	player.action_visuals.preview_show_target = true
	body.release_charge()
	check(not renderer.visible and not renderer.is_processing() and renderer.route == null, "松开发射清理路线与目标，闲置不处理")
	wall.queue_free()
	clear_enemies()
	await settle()

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
	player.ricochet_rules = PlayerRicochetRules.new()
	player.ricochet_rules.maximum_launch_speed = 8.0
	player.ricochet_rules.bounce_speed_retention = 1.0
	player.action_visuals = PlayerActionVisuals.new()
	player.sword_rules = PlayerSwordRules.new()
	player.sword_rules.audio_enabled = false
	player.bounds = Rect2(-18, -18, 36, 36)
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
	navigation.build(terrain, 0.32, [player.get_rid()])
	await path_checks()
	await target_checks()
	body.cancel()
	world.queue_free()
	await settle()
	print("Aim path preview: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
