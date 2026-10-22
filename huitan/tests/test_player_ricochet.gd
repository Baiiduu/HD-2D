extends SceneTree

const SESSION := preload("res://tests/fixtures/ricochet_session.gd")
var checks := 0
var failures := 0
var world: Node3D
var terrain: Terrain
var session: WavePrototype
var player: Player
var body: PlayerRicochet
var path := TerrainPath.new()
var pushed: Array[Dictionary] = []
var bounces := 0
var attacks := 0

func _initialize() -> void:
	create_timer(75.0).timeout.connect(func(): quit(2))
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

func box(point: Vector3, size: Vector3, yaw := 0.0) -> StaticBody3D:
	var node := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	node.add_child(collision)
	world.add_child(node)
	node.position = point
	node.rotation.y = yaw
	return node

func reset(point := Vector3.ZERO) -> void:
	body.cancel(true)
	player.global_position = point + Vector3.UP * 0.03
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	await settle(10)
	player.set_physics_process(false)
	bounces = 0
	pushed.clear()

func launch(heading := Vector3.RIGHT, charge_seconds := 0.0) -> void:
	check(body.begin_charge(heading), "可从地面开始蓄力")
	body.advance(charge_seconds, Vector3.ZERO, false)
	check(body.release_charge(), "松开蓄力进入本体飞行")

func enemy(id: String, point: Vector3) -> SlimeEnemy:
	var data: WaveEnemyDefinition = load("res://data/enemies/%s.tres" % id).duplicate()
	var mob := data.scene.instantiate() as SlimeEnemy
	mob.configure_wave({"player": player, "terrain": terrain, "camera": null, "navigation": path,
		"attack_root": session._attack_root, "spatial_index": session._spatial_index,
		"damage_player": func(_amount): pass, "request_spawn": Callable(),
		"combat_active": session.combat_active}, data, 0.0)
	world.add_child(mob)
	mob.global_position = point + Vector3.UP * 0.03
	mob.set_physics_process(false)
	session.enemies.append(mob)
	session._spatial_index.update(mob)
	return mob

func remove_enemy(mob: WaveEnemy) -> void:
	session.enemies.erase(mob)
	mob.cancel()

func math_checks() -> void:
	for radial in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3(2, 0, 3)]:
		var tangent := PlayerRicochet.tangent_direction(radial, Vector3.RIGHT, true)
		check(absf(tangent.dot(radial)) < 0.00001 and is_equal_approx(tangent.length(), 1.0), "推力是圆的单位切线，径向分量为零")
		check(radial.cross(tangent).dot(Vector3.UP) < 0.0, "圆周各处保持同一世界旋向")
		check(PlayerRicochet.tangent_direction(radial, Vector3.RIGHT, false).is_equal_approx(-tangent), "反向开关翻转完整旋向")
	check(PlayerRicochet.tangent_direction(Vector3.ZERO, Vector3.ZERO, true).is_finite(), "恰好重合也不产生零方向或 NaN")
	var whole := PlayerRicochet.circle_entry(Vector3.ZERO, Vector3(10, 0, 0), Vector3(4, 0, 0.5), 1.0)
	check(whole > 0.3 and whole < 0.4, "连续圆周覆盖返回真实进入点")
	check(PlayerRicochet.circle_entry(Vector3.ZERO, Vector3(10, 0, 0), Vector3(4, 0, 2), 1.0) < 0.0, "圆外怪物不被拨动")
	check(PlayerRicochet.circle_entry(Vector3.ZERO, Vector3(1, 0, 0), Vector3(-4, 0, 0), 1.0) < 0.0, "身后未接触的怪物不被误选")
	for step in [0.1, 0.2, 0.5]:
		var found := -1.0
		for index in ceili(1.0 / step):
			var start := Vector3(10.0 * index * step, 0, 0)
			var end := Vector3(10.0 * (index + 1) * step, 0, 0)
			var entry := PlayerRicochet.circle_entry(start, end, Vector3(4, 0, 0.5), 1.0)
			if entry >= 0.0:
				found = index * step + step * entry
				break
		check(is_equal_approx(whole, found), "切入判定不随物理步长漏过或偏移")

func movement_checks() -> void:
	await reset()
	check(player.is_on_floor(), "真实胶囊已落在测试地形")
	await launch(Vector3.RIGHT)
	var minimum := body.flight_speed
	body.advance(0.1, Vector3.ZERO, false)
	check(player.global_position.x > 0.7 and body.flying, "连续飞行前进，不被地面误挡")
	await reset()
	await launch(Vector3.RIGHT, 1.2)
	check(body.flight_speed > minimum and is_equal_approx(body.charge_fraction, 1.0), "蓄力提高速度并在满蓄力封顶")
	var wall := box(Vector3(2, 0.6, 0), Vector3(0.02, 1.2, 4))
	await settle()
	body.advance(0.2, Vector3.ZERO, false)
	check(bounces == 1 and body.direction.x < -0.99 and player.global_position.x < 1.76, "完整胶囊高速扫掠两厘米薄墙并正确反弹")
	wall.position.x = -2.0
	await settle()
	body.advance(0.3, Vector3.ZERO, false)
	check(bounces == 2 and body.direction.x > 0.99 and player.global_position.x > -1.76, "移动后的挡墙立即参与反弹，不使用旧碰撞缓存")
	wall.queue_free()
	await settle()
	await reset()
	wall = box(Vector3(2, 0.6, 0), Vector3(0.02, 1.2, 4))
	player.ricochet_rules.bounce_speed_cost = 100.0
	await settle()
	await launch(Vector3.RIGHT, 1.0)
	body.advance(0.3, Vector3.ZERO, false)
	check(not body.flying and bounces == 0 and player.global_position.x < 1.76, "碰撞后速度不足时停在墙前，仍不穿墙")
	player.ricochet_rules.bounce_speed_cost = 0.5
	wall.queue_free()
	await settle()
	await reset()
	player.bounds = Rect2(-1, -1, 2, 2)
	await launch(Vector3.RIGHT, 1.0)
	body.advance(0.5, Vector3.ZERO, false)
	check(not body.flying and player.global_position.x <= 1.001, "边界终止飞行，保留人物活动范围")
	player.bounds = Rect2(-18, -18, 36, 36)
	await reset()
	await launch(Vector3.RIGHT)
	var point := player.global_position
	var remaining := body._flight_remaining
	session.set_combat_frozen(true)
	body.advance(0.5, Vector3.ZERO, true)
	check(player.global_position == point and body._flight_remaining == remaining, "升级冻结人物飞行位置和剩余计时")
	session.set_combat_frozen(false)
	body.advance(0.1, Vector3.ZERO, false)
	check(player.global_position.x > point.x, "恢复战斗后沿原世界方向继续")
	body.advance(10.0, Vector3.ZERO, false)
	check(not body.flying, "持续耗速会自然收势，反弹不凭空补充速度")
	await reset()
	check(body.begin_charge(Vector3.RIGHT), "开始取消用蓄力")
	var blocker := Node.new()
	world.add_child(blocker)
	blocker.add_to_group(&"gameplay_input_blockers")
	body.advance(0.1, Vector3.ZERO, true)
	check(body.state == PlayerRicochet.State.IDLE and not body.release_charge(), "面板占用输入时取消未释放蓄力，不补发一次发射")
	blocker.queue_free()
	await settle()
	check(body.request_normal_attack() and attacks == 1, "左键普通攻击接口可请求动作")
	check(player.current_health == 100.0, "框架不为人物增加碰撞伤害或扣除资源")
	await reset()
	wall = box(Vector3(2, 0.6, 0), Vector3(0.02, 1.2, 5), PI / 4.0)
	await settle()
	await launch(Vector3.RIGHT, 1.0)
	body.advance(0.2, Vector3.ZERO, false)
	check(bounces == 1 and absf(body.direction.x) < 0.05 and absf(body.direction.z) > 0.99, "斜墙使用实际法线，转向九十度而非只翻转 X")
	wall.queue_free()
	await settle()
	await reset()
	await launch(Vector3.RIGHT)
	var heading := body.direction
	var camera := Camera3D.new()
	world.add_child(camera)
	player.movement_camera = camera
	camera.rotation.y = PI / 2.0
	body.advance(0.05, Vector3.ZERO, false)
	check(body.flying and body.direction == heading, "仅旋转相机仍保留弹射世界方向")
	body.advance(0.05, Vector3.FORWARD, false)
	check(not body.flying and body.state == PlayerRicochet.State.IDLE, "方向移动输入立即停止弹射并恢复行走")
	player.movement_camera = null
	camera.queue_free()
	await reset()
	check(body.begin_charge(Vector3.RIGHT), "开始参数快照测试蓄力")
	player.ricochet_rules.minimum_launch_speed = 12.0
	check(body.release_charge() and body.flight_speed == 8.0, "一次蓄力使用自己的参数快照，下一次才读取修改")
	player.ricochet_rules.minimum_launch_speed = 8.0
	await reset()
	for kind in ["water", "cliff"]:
		if kind == "water": terrain.data.set_overlay(Vector2i(1, 0), TerrainData.OVERLAY_WATER, true)
		else: terrain.data.set_level(Vector2i(1, 0), 1)
		await settle()
		await launch(Vector3.RIGHT, 1.0)
		body.advance(0.3, Vector3.ZERO, false)
		check(not body.flying and player.global_position.x < 0.81 and bounces == 0, "水面或断层终止人物弹射而非反弹：" + kind)
		var mob := enemy("wave_slime", Vector3.ZERO)
		mob.apply_push_impulse(Vector3.RIGHT, 16.0, 0.22)
		mob._advance_push(0.22)
		check(mob.global_position.x < 0.81, "水面或断层也约束切线外力：" + kind)
		remove_enemy(mob)
		terrain.data.set_overlay(Vector2i(1, 0), TerrainData.OVERLAY_WATER, false)
		terrain.data.set_level(Vector2i(1, 0), 0)
		await settle()
		await reset()

func push_checks() -> void:
	await reset()
	var mob := enemy("wave_slime", Vector3(2, 0, 0.4))
	var far := enemy("wave_slime", Vector3(2, 0, 3))
	var high := enemy("wave_slime", Vector3(2, 1.0, -0.4))
	var warning := enemy("wave_slime", Vector3(3, 0, -0.4))
	warning.spawn_delay = 1.0
	var health := mob.health
	await launch(Vector3.RIGHT, 1.0)
	body.advance(0.2, Vector3.ZERO, false)
	check(pushed.size() == 1 and pushed[0].enemy == mob, "大步长切入只拨动圆内、同高且完成出场的怪物")
	check(mob.health == health, "切线外力本身不结算伤害")
	var destination := mob._orbit.points[-1]
	var orbit_seconds := mob._orbit.duration
	# 先验证无阻挡落点；人物胶囊本身也在实体碰撞层，不能留在这条圆弧上。
	player.global_position = Vector3(-8, 0.03, -8)
	await settle()
	for frame in 60: mob._advance_push(orbit_seconds / 60.0)
	check(TerrainPath.horizontal_distance(mob.global_position, destination) < 0.001 and mob._push_remaining <= 0.00001, "拨怪沿怪群半圈轨迹到对侧边沿")
	mob.global_position = Vector3(2, 0.03, 0.4)
	session._spatial_index.update(mob)
	body._push_segment(Vector3.ZERO, Vector3(4, 0, 0))
	check(pushed.size() == 1, "同一次弹射不会每帧重复推同一只怪物")
	for actor in [mob, far, high, warning]: remove_enemy(actor)
	await settle()
	await reset()
	mob = enemy("wave_slime", Vector3(2, 0, 0))
	var wall := box(Vector3(1, 0.6, 0), Vector3(0.02, 1.2, 4))
	await settle()
	await launch(Vector3.RIGHT)
	body._push_segment(Vector3.ZERO, Vector3(1.5, 0, 0))
	check(pushed.is_empty(), "墙体阻挡切线拨怪，不隔墙施力")
	wall.queue_free()
	await settle()
	mob.global_position = Vector3.ZERO + Vector3.UP * 0.03
	wall = box(Vector3(0, 0.6, 0.6), Vector3(4, 1.2, 0.02))
	await settle()
	check(mob.apply_push_impulse(Vector3.BACK, 8.0, 0.22), "怪物接受独立平滑外力接口")
	for frame in 12: mob._advance_push(0.02)
	check(mob.global_position.z < 0.34, "被推怪物也用真实胶囊碰撞，不穿薄墙")
	mob.knockback_multiplier = 0.0
	check(not mob.apply_push_impulse(Vector3.BACK, 8.0, 0.22), "保留现有怪物击退抗性")
	wall.queue_free()
	remove_enemy(mob)
	await settle()
	for id in ["leaf_charger", "lantern_spitter", "pot_brood", "bell_frog", "mini_slime"]:
		mob = enemy(id, Vector3(0, 0, 3))
		check(mob.apply_push_impulse(Vector3.RIGHT, 1.0, 0.1), "当前怪物都接入通用外力接口：" + id)
		remove_enemy(mob)
	await settle()
	var distances: Array[float] = []
	for steps in [1, 22]:
		mob = enemy("wave_slime", Vector3(0, 0, 3))
		mob.apply_push_impulse(Vector3.RIGHT, 8.0, 0.22)
		for frame in steps: mob._advance_push(0.22 / steps)
		distances.append(mob.global_position.x)
		remove_enemy(mob)
		await settle()
	check(absf(distances[0] - distances[1]) < 0.001 and absf(distances[0] - 0.88) < 0.001, "切线外力按速度积分，真实距离不随帧率改变")

func charge_effect_checks() -> void:
	await reset()
	player.action_visuals.show_aim_guide = true
	var texture := player.sprite.texture
	var scale := player.sprite.scale
	check(body.begin_charge(Vector3.RIGHT), "开始真实蓄力特效")
	var effect := body._charge_effect
	check(is_instance_valid(effect) and effect.visible and effect.is_processing(), "首次蓄力创建并显示圆弧、路线和光点")
	check(is_equal_approx(effect._pixel, player.sprite.pixel_size * player.sprite.global_basis.x.length()), "蓄力特效按人物实际原生像素计量")
	check(player.action_visuals.charge == null and player.sprite.texture == texture and player.sprite.scale == scale, "特效不接入人物动画或缩放角色")
	body.advance(0.4, Vector3.ZERO, false)
	check(is_equal_approx(effect._ring_material.get_shader_parameter("charge"), 0.5), "十二段圆弧直接读取真实半蓄力进度")
	var age := effect._age
	session.set_combat_frozen(true)
	body.advance(0.3, Vector3.ZERO, false)
	effect._process(0.3)
	check(effect._age == age and is_equal_approx(body.charge_fraction, 0.5), "升级冻结同时停止光点和蓄力计时")
	session.set_combat_frozen(false)
	body.advance(0.4, Vector3.ZERO, false)
	check(effect._full_at >= 0.0 and effect._ring_material.get_shader_parameter("full_flash") == 1.0, "真实满蓄力触发一次短闪")
	effect._process(0.3)
	body.advance(0.1, Vector3.ZERO, false)
	check(effect._ring_material.get_shader_parameter("full_flash") == 0.0, "持续按住满蓄力不反复闪烁")
	var point := player.global_position
	body.aim(Vector3.FORWARD)
	body.advance(0.0, Vector3.ZERO, false)
	check(effect._route.segments[0].heading.is_equal_approx(Vector3.FORWARD) and player.global_position == point, "碰撞路线跟随万向瞄准，不移动人物")
	var wall := box(point + Vector3(0, 0.6, -1.4), Vector3(3, 1.2, 0.02))
	await settle()
	body.advance(0.0, Vector3.ZERO, false)
	var tip: Vector3 = effect._route.segments[0].end - point
	check(tip.length() < 1.4, "真实墙体截断首段路线，不显示穿墙提示")
	wall.position.z -= 5.0
	await settle()
	body.advance(0.0, Vector3.ZERO, false)
	tip = effect._route.segments[0].end - point
	check(tip.length() > 2.5, "动态墙移开后路线立即恢复，无过期碰撞缓存")
	wall.queue_free()
	player.action_visuals.show_aim_guide = false
	body.advance(0.0, Vector3.ZERO, false)
	check(effect.visible and not effect._aim.visible, "路线可单独关闭，圆弧和光点仍显示")
	check(body.release_charge() and not effect.visible and not effect.is_processing(), "松开发射立即停止蓄力特效，不沿飞行残留")
	await reset()
	body.begin_charge(Vector3.RIGHT)
	check(body._charge_effect == effect and effect._full_at < 0.0, "再次蓄力复用原节点和网格，满蓄提示重新计时")
	body.advance(0.1, Vector3.ZERO, true)
	check(not effect.visible and not effect.is_processing(), "管理面板取消蓄力时一起隐藏光源和所有特效")
	await reset()
	body.begin_charge(Vector3.RIGHT)
	player.action_visuals.show_charge_effect = false
	body.advance(0.0, Vector3.ZERO, false)
	check(body.charging and not effect.visible, "关闭蓄力特效不改变蓄力机制")
	player.action_visuals.show_charge_effect = true
	body.cancel(true)

func animation_checks() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for name in [&"side", &"front", &"back"]:
		frames.add_animation(name)
		frames.set_animation_speed(name, 10.0)
		for index in 8: frames.add_frame(name, player.animations.get_frame_texture(&"run", index))
	player.action_visuals.charge = frames
	player.action_visuals.flight_attack = frames
	await reset()
	check(body.begin_charge(Vector3.RIGHT), "有动作素材时开始蓄力")
	body.advance(0.4, Vector3.ZERO, false)
	player.action_animator.visuals = player.action_visuals
	check(player.action_animator.render(0.0) and player.sprite.texture == frames.get_frame_texture(&"side", 4), "动作槽按真实蓄力进度选帧")
	var scale := player.sprite.scale
	var pixel := player.sprite.pixel_size
	body.aim(Vector3.FORWARD)
	body.advance(0.0, Vector3.ZERO, false)
	player.action_animator.render(0.0)
	check(player.sprite.texture == frames.get_frame_texture(&"back", 4) and player.sprite.scale == scale and player.sprite.pixel_size == pixel, "换方向保留帧进度和原生像素尺寸")
	body.release_charge()
	check(player.action_animator.request_attack(&"flight_attack", Vector3.RIGHT), "预留飞行攻击动作可由真实出手事件触发")
	player.action_animator.render(0.71)
	check(player.sprite.texture == frames.get_frame_texture(&"side", 7), "完整播放攻击素材所有八帧")
	body.cancel()
	player.action_visuals.charge = null
	check(not player.action_animator.render(0.0), "空动作槽安全回退现有动画")

func mouse_button(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await settle(1)

func input_checks() -> void:
	await reset()
	player._blink._buffer_remaining = 0.1
	check(body.begin_charge(Vector3.RIGHT) and player._blink._buffer_remaining == 0.0, "蓄力接管时丢弃旧闪身缓存，避免飞行中叠加延迟瞬移")
	body.cancel(true)
	await mouse_button(MOUSE_BUTTON_RIGHT, true)
	body.advance(0.1, Vector3.RIGHT, false)
	check(body.charging, "真实右键输入经过 InputMap 和未处理输入开始蓄力")
	await mouse_button(MOUSE_BUTTON_RIGHT, false)
	body.advance(0.01, Vector3.ZERO, false)
	check(body.flying, "真实右键松开只发射一次")
	var count := attacks
	await mouse_button(MOUSE_BUTTON_LEFT, true)
	body.advance(0.01, Vector3.ZERO, false)
	await mouse_button(MOUSE_BUTTON_LEFT, false)
	check(attacks == count + 1, "真实左键输入触发飞行攻击请求")
	session._set_phase(WavePrototype.Phase.REST)
	check(body.state == PlayerRicochet.State.IDLE, "清波或退出战斗立即取消飞行和残留输入")
	session._set_phase(WavePrototype.Phase.BATTLE)
	await reset()
	var mob := enemy("wave_slime", Vector3(0, 0, 3))
	mob.apply_push_impulse(Vector3.RIGHT, 8.0, 0.22)
	mob.set_physics_process(true)
	session.set_combat_frozen(true)
	var point := mob.global_position
	var remaining := mob._push_remaining
	await settle(4)
	check(mob.global_position == point and mob._push_remaining == remaining, "升级冻结保留真实怪物外力的位置和剩余计时")
	session.set_combat_frozen(false)
	await settle(2)
	check(mob._push_remaining < remaining, "升级结束恢复怪物原有外力计时")
	remove_enemy(mob)
	await settle()
	player.owner = world
	var entries: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(world)
	for property in ["push_radius", "minimum_bounce_speed", "flight_deceleration", "bounce_speed_cost", "normal_attack", "flight_attack", "show_charge_effect", "show_aim_guide", "charge_radius_pixels", "charge_effect_opacity", "charge_effect_energy"]:
		check(entries.any(func(item): return item.property == property and item.category == "人物" and item.common), "统一人物参数入口可调整：" + property)
	player.owner = null

func run() -> void:
	math_checks()
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	terrain = Terrain.new()
	terrain.name = "Ground"
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
	# 碰撞夹具使用固定速度与半径；正式试玩资源可独立调节。
	player.ricochet_rules = PlayerRicochetRules.new()
	player.ricochet_rules.bounce_speed_retention = 1.0
	player.action_visuals = PlayerActionVisuals.new()
	player.action_visuals.show_aim_guide = false
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
	body.wall_bounced.connect(func(_point, _normal): bounces += 1)
	body.enemy_pushed.connect(func(mob, tangent): pushed.append({"enemy": mob, "tangent": tangent}))
	player.normal_attack_requested.connect(func(_heading): attacks += 1)
	await settle()
	path.build(terrain, 0.32, [player.get_rid()])
	await movement_checks()
	await push_checks()
	await input_checks()
	await charge_effect_checks()
	await animation_checks()
	session.enemies.clear()
	world.queue_free()
	await settle()
	print("Player body ricochet: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
