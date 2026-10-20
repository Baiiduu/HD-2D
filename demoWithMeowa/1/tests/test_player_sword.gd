extends SceneTree

const SESSION := preload("res://tests/fixtures/ricochet_session.gd")
var checks := 0
var failures := 0
var world: Node3D
var terrain: Terrain
var session: WavePrototype
var player: Player
var sword: PlayerSword
var strikes: Array[Dictionary] = []
var damage_events: Array[Dictionary] = []
var pushes := 0

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
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

func box(point: Vector3, size: Vector3) -> StaticBody3D:
	var result := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	result.add_child(collision)
	world.add_child(result)
	result.position = point
	return result

func reset() -> void:
	session.set_combat_frozen(false)
	for mob in session.enemies: mob.cancel()
	session.enemies.clear()
	session.combat_modifiers.reset()
	player.body_ricochet.cancel(true)
	sword.cancel()
	sword.set_physics_process(false)
	player.global_position = Vector3(0, 0.03, 0)
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	await settle(10)
	player.set_physics_process(false)
	sword.set_physics_process(false)
	sword._last_position = player.global_position
	sword._motion.clear()
	strikes.clear()
	damage_events.clear()
	pushes = 0

func enemy(point: Vector3, health := 200.0) -> SlimeEnemy:
	var data := load("res://data/enemies/wave_slime.tres").duplicate() as WaveEnemyDefinition
	data.health = health
	var result := data.scene.instantiate() as SlimeEnemy
	result.configure_wave({"player":player, "terrain":terrain, "camera":null, "navigation":session._path,
		"attack_root":session._attack_root, "spatial_index":session._spatial_index,
		"damage_player":func(_value): pass, "request_spawn":Callable(), "combat_active":session.combat_active}, data, 0.0)
	world.add_child(result)
	result.global_position = point + Vector3.UP * 0.03
	result.set_physics_process(false)
	session.enemies.append(result)
	session._spatial_index.update(result)
	session.enemy_spawned.emit(result)
	return result

func manual(heading := Vector3.RIGHT) -> void:
	check(sword.request_manual(heading), "基础攻击独立接受人物请求")
	for frame in 17: sword._physics_process(1.0 / 60.0)

func flight() -> void:
	check(player.body_ricochet.begin_charge(Vector3.RIGHT), "开始弹射蓄力")
	player.body_ricochet.advance(0.8, Vector3.ZERO, false)
	check(player.body_ricochet.release_charge(), "松手开始自动挥剑的飞行")

func advance_flight(seconds: float, step := 1.0 / 60.0) -> void:
	var clock := 0.0
	while clock < seconds - 0.000001:
		var delta := minf(step, seconds - clock)
		player.body_ricochet.advance(delta, Vector3.ZERO, false)
		sword._physics_process(delta)
		clock += delta

func manual_checks() -> void:
	await reset()
	var front := enemy(Vector3(1, 0, 0))
	var side := enemy(Vector3(0, 0, 1))
	var rear := enemy(Vector3(-1, 0, 0))
	var far := enemy(Vector3(1.7, 0, 0))
	var high := enemy(Vector3(1, 1, 0))
	var warning := enemy(Vector3(1, 0, 0.2))
	warning.spawn_delay = 2.0
	await manual()
	check(front.health == 190.0 and damage_events.size() == 1, "一次真实扫击只命中前方目标一次")
	check(side.health == 200.0 and rear.health == 200.0, "普攻 120 度保留侧后方空隙")
	check(far.health == 200.0 and high.health == 200.0 and warning.health == 200.0, "范围、地表高度和出场保护有效")
	check(pushes == 0, "普通攻击不触发飞行拨怪")
	check(not sword.request_manual(Vector3.RIGHT), "完整动作结束后仍受共享出手间隔限制")
	sword._physics_process(0.28)
	await manual()
	check(front.health == 180.0 and strikes.size() == 2 and strikes[0].reverse != strikes[1].reverse, "下一刀可以再次伤害，左右交替挥剑")
	await reset()
	front = enemy(Vector3(1, 0, 0), 20.0)
	await manual()
	check(front.health == 10.0 and not front.dead, "基础史莱姆第一剑剩余一半生命")
	sword._physics_process(0.55)
	await manual()
	check(front.dead, "第二剑击杀基础史莱姆")
	await reset()
	var inside := enemy(Vector3(sword.rules.normal_range - 0.005, 0, 0))
	var outside := enemy(Vector3(sword.rules.normal_range + 0.005, 0, 0))
	await manual()
	check(inside.health == 190.0 and outside.health == 200.0, "刀光半径内外 5 毫米边界与实际命中相符")
	await reset()
	front = enemy(Vector3(1, 0, 0))
	var wall := box(Vector3(0.5, 0.6, 0), Vector3(0.02, 1.2, 4))
	await settle()
	await manual()
	check(front.health == 200.0, "薄墙阻挡基础剑术伤害")
	wall.queue_free()
	await settle()
	await reset()
	front = enemy(Vector3(1.7, 0, 0))
	session.combat_modifiers.apply_buff(load("res://data/growth/damage.tres"))
	session.combat_modifiers.apply_buff(load("res://data/growth/range.tres"))
	session.combat_modifiers.apply_buff(load("res://data/growth/cooldown.tres"))
	await manual()
	check(front.health == 188.0, "伤害与范围增益同时作用，伤害系数只应用一次")
	check(is_equal_approx(sword.get_stats().interval, 0.55 / 1.12) and is_equal_approx(sword.get_stats(true).interval, 0.30 / 1.12), "同一攻速效率分别缩短两种攻击的真实间隔")
	check(session.get_attack_stats().any(func(item): return item.name == "基础剑术"), "基础剑术向现有成长池提供真实收益")
	session.combat_modifiers.apply_buff(load("res://data/growth/cooldown.tres"))
	await flight()
	var buffs := RunBuffs.new()
	buffs.session = session
	check(is_equal_approx(sword.get_stats(true).interval, 0.30 / 1.24) and sword.get_stats(true).interval < sword.rules.duration(), "第二次攻速仍缩短弹射挥剑间隔，完整动作同步加快")
	check(buffs._has_effect(load("res://data/growth/cooldown.tres")), "弹射中仍可获得对普通攻击有效的下一级冷却增益")
	check(session.get_attack_stats().any(func(item): return item.name == "弹射挥剑"), "成长资格同时读取两种攻击模式的真实数值")
	buffs.free()

func attack_speed_checks() -> void:
	for step in [0.5, 1.0 / 30.0, 1.0 / 60.0, 1.0 / 120.0]:
		await reset()
		var mob := enemy(Vector3(1, 0, 0), 10000.0)
		for rank in 30: session.combat_modifiers.apply_buff(load("res://data/growth/cooldown.tres"))
		var stats := sword.get_stats(true)
		check(is_equal_approx(stats.interval, sword.rules.minimum_attack_interval), "高攻速到达明确的最短间隔")
		var elapsed := 0.0
		while elapsed < 1.0 - 0.000001:
			var delta := minf(step, 1.0 - elapsed)
			sword._simulate(player.global_position, player.global_position, delta, true, Vector3.RIGHT)
			sword._drain_hits()
			elapsed += delta
		check(strikes.size() == 9 and damage_events.size() == 9 and is_equal_approx(mob.health, 9910.0), "粗步长与高帧率均为九次独立完整挥剑，不重复伤害也不丢刀")
		check(sword._settings.duration() <= stats.interval and is_equal_approx(sword._settings.windup_seconds / sword._settings.sweep_seconds, 0.5), "加速仍保留起手、扫刃、收尾的时长比例")
		check(is_equal_approx(sword.rules.duration(), 0.25), "攻速不累计改写基础动作资源")
		check(is_equal_approx(player.action_animator._attack_duration, sword._settings.duration()), "攻速成长后的真实动作时长同步人物显示，不受素材原始帧率限制")
	await reset()
	var mob := enemy(Vector3(1, 0, 0))
	sword.request_manual(Vector3.RIGHT)
	sword._physics_process(0.02)
	var original_duration := sword._settings.duration()
	for rank in 5: session.combat_modifiers.apply_buff(load("res://data/growth/cooldown.tres"))
	check(is_equal_approx(sword._settings.duration(), original_duration), "进行中的动作保留起手快照")
	session.set_combat_frozen(true)
	var age := sword._age
	sword._physics_process(0.5)
	check(is_equal_approx(age, sword._age) and mob.health == 200.0, "攻速成长后冻结仍不推进动作或扣血")
	session.set_combat_frozen(false)
	sword._physics_process(0.24)
	check(mob.health == 190.0, "恢复后完成原来的一刀且不重复扣血")

func flight_checks() -> void:
	await reset()
	var mob := enemy(Vector3(1.2, 0, 0.3))
	var side := enemy(Vector3(0.65, 0, -1.0))
	var rear := enemy(Vector3(-1, 0, 0))
	await flight()
	await advance_flight(0.3)
	check(mob.health < 200.0 and side.health < 200.0, "飞行 180 度覆盖前方与两侧")
	check(rear.health == 200.0, "飞行挥剑不自动砍中身后")
	check(pushes > 0, "斩击实际扣血后才触发切线拨怪")
	check(strikes.all(func(item): return item.flying), "飞行只启动独立基础挥剑")
	check(not sword.request_manual(Vector3.LEFT), "飞行中左键不叠加另一把普攻")
	await reset()
	for index in 8: enemy(Vector3(0.8 + index * 0.8, 0, 0.25))
	await flight()
	await advance_flight(0.9)
	check(strikes.size() == 3, "完整 0.9 秒飞行约三刀，结束不补一刀")
	var ids := {}
	for hit in damage_events: ids[hit.enemy.get_instance_id()] = true
	check(pushes == ids.size(), "同一飞行每只受伤怪物最多拨动一次")
	await reset()
	mob = enemy(Vector3(2.0, 0, 0.4))
	await flight()
	await advance_flight(0.3, 0.3)
	check(mob.health < 200.0, "大物理步长依靠连续刀锋扫掠命中，不能穿群漏判")
	await reset()
	await flight()
	await advance_flight(0.3)
	check(strikes.is_empty(), "空地飞行不空挥或产生隐藏伤害")
	await reset()
	player.ricochet_rules.push_radius = 0.5
	mob = enemy(Vector3(1.5, 0, 0.2))
	await flight()
	await advance_flight(0.12)
	check(mob.health < 200.0 and pushes == 0, "小拨怪圈不会在远处剑锋命中时提前推怪")
	await advance_flight(0.15)
	check(pushes == 1 and mob.stun_remaining > 0.0, "先受剑伤的怪物进入较小拨怪圈后，继续接上拨动与眩晕")
	player.ricochet_rules.push_radius = 3.0
	await reset()
	for index in 6: enemy(Vector3(0.8 + index * 0.4, 0, 0.25))
	var wall := box(Vector3(3.1, 0.8, 0), Vector3(0.1, 1.6, 5))
	await settle()
	await flight()
	player.body_ricochet.advance(0.5, Vector3.ZERO, false)
	var seconds := 0.0
	for piece in player.body_ricochet._travel_segments: seconds += piece.seconds
	sword._physics_process(0.5)
	check(player.body_ricochet.bounce_count == 1 and seconds <= 0.500001, "真实撞墙分段不会多算物理帧时长")
	check(strikes.size() == 2, "撞墙反弹不重置攻击时钟或额外补剑")
	wall.queue_free()
	await settle()

func freeze_checks() -> void:
	await reset()
	var mob := enemy(Vector3(1, 0, 0))
	var second := enemy(Vector3(1, 0, 0.05))
	sword.request_manual(Vector3.RIGHT)
	sword._physics_process(0.08)
	var age := sword._age
	var health := mob.health
	session.set_combat_frozen(true)
	sword._physics_process(0.5)
	check(sword._age == age and mob.health == health, "升级冻结保留动作进度与生命")
	session.set_combat_frozen(false)
	# 两个同刀接触中的第一个触发升级，恢复后继续剩余接触，不能重扣首个目标。
	var freeze_once := true
	var freeze_hit := func(_enemy, _damage, _flying):
		if freeze_once:
			freeze_once = false
			session.set_combat_frozen(true)
	sword.hit_landed.connect(freeze_hit)
	sword._physics_process(0.2)
	check(session.combat_frozen, "命中回调可立即触发升级冻结")
	session.set_combat_frozen(false)
	sword._physics_process(0.01)
	check(mob.health == 190.0 and second.health == 190.0, "恢复后同刀剩余命中结算完整且不重复")
	sword.hit_landed.disconnect(freeze_hit)
	await reset()
	mob = enemy(Vector3(1, 0, 0))
	sword.request_manual(Vector3.RIGHT)
	var blocker := Node.new()
	world.add_child(blocker)
	blocker.add_to_group(&"gameplay_input_blockers")
	sword._physics_process(0.4)
	check(strikes.is_empty() and mob.health == 200.0, "管理 UI 拦截新攻击输入")
	blocker.queue_free()
	await settle()

func input_and_art_checks() -> void:
	await reset()
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await settle(1)
	for frame in 60: sword._physics_process(1.0 / 60.0)
	check(strikes.size() == 2, "真实左键按住按 0.55 秒间隔连续普攻")
	event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await settle(1)
	for frame in 60: sword._physics_process(1.0 / 60.0)
	check(strikes.size() == 2, "左键松开后不补发攻击")
	await reset()
	var production := load("res://data/player/basic_sword.tres").duplicate() as PlayerSwordRules
	# 旧素材独立验证；不改写正式资源选中的窄弧模式。
	production.effect_mode = PlayerSwordRules.SlashVisual.FRAME_ANIMATION
	var frames := load("res://assets/meowa/combat/basic_sword/frames.tres") as SpriteFrames
	check(frames.get_frame_count(&"slash") == 8 and frames.get_animation_speed(&"slash") == 40.0, "Meowa 八帧全部保留，横扫与消散原生打包")
	check(is_equal_approx(production.normal_range / production.art_radius_pixels, 0.02 * 0.8), "基础剑光与当前人物同为 0.016 米每原生像素")
	for index in 8:
		var texture := frames.get_frame_texture(&"slash", index) as AtlasTexture
		check(texture.region.size == Vector2(224, 224), "图集保留原生 224 像素画布：%d" % index)
		sword._effect.display(Vector3.ZERO, Vector3.RIGHT, 1.6, 180.0, false, frames, index / 40.0 + 0.00001, production, session._path, sword._surface, [player.get_rid()])
		var rectangle: Vector4 = sword._effect._material.get_shader_parameter("frame_rect")
		check(is_equal_approx(rectangle.x, (index % 4) * 0.25) and is_equal_approx(rectangle.y, (index / 4) * 0.5), "每一帧独立按实际图集区域采样：%d" % index)
	var clear_mesh := sword._effect.mesh
	var edge: PackedVector3Array = clear_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var farthest := 0.0
	for point in edge: farthest = maxf(farthest, Vector2(point.x, point.z).length())
	check(is_equal_approx(farthest, 1.6), "斩光网格的真实外缘使用传入的命中半径")
	check(float(sword._effect._material.get_shader_parameter("leading_angle")) > 1.5, "完整扫击后刀光达到实际扇角终点")
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	for yaw in [0.0, 1.0, 2.0, 3.0]:
		camera.rotation.y = yaw
		sword._effect.display(Vector3.ZERO, Vector3.RIGHT, 1.6, 180.0, false, frames, 0.10, production, session._path, sword._surface, [player.get_rid()])
		var slope: Vector2 = sword._effect._material.get_shader_parameter("plane_slope")
		var view := sword._effect.global_basis.inverse() * camera.global_basis.z
		check(slope.dot(Vector2(view.x, view.z)) < 0.0 and sword._effect.mesh == clear_mesh, "旋转镜头保持斩面朝向镜头并复用原网格")
		check(production.effect_height - slope.length() * 1.6 >= 0.07999, "斜切外缘不会沉入地面")
	camera.queue_free()
	await settle()
	var slower := production.duplicate() as PlayerSwordRules
	slower.sweep_seconds = 0.2
	slower.fade_seconds = 0.4
	sword._effect.display(Vector3.ZERO, Vector3.RIGHT, 1.6, 180.0, false, frames, 0.16, slower, session._path, sword._surface, [player.get_rid()])
	var active_rect: Vector4 = sword._effect._material.get_shader_parameter("frame_rect")
	check(is_equal_approx(active_rect.x, 0.75) and active_rect.y == 0.0, "调慢扫击时先完整播放横扫，不能提前耗尽消散帧")
	sword._effect.display(Vector3.ZERO, Vector3.RIGHT, 1.6, 180.0, false, frames, 0.55, slower, session._path, sword._surface, [player.get_rid()])
	var fade_rect: Vector4 = sword._effect._material.get_shader_parameter("frame_rect")
	check(is_equal_approx(fade_rect.x, 0.75) and fade_rect.y == 0.5, "调慢收尾时保留最后的原生碎屑帧")
	sword._effect.display(Vector3.ZERO, Vector3.RIGHT, 1.6, 180.0, false, frames, 0.05, production, session._path, sword._surface, [player.get_rid()])
	check(sword._effect.mesh == clear_mesh, "无障碍平地复用剑光网格")
	var wall := box(Vector3(0.8, 0.6, 0), Vector3(0.02, 1.2, 5))
	await settle()
	sword._effect.display(Vector3.ZERO, Vector3.RIGHT, 1.6, 180.0, false, frames, 0.05, production, session._path, sword._surface, [player.get_rid()])
	check(sword._effect.mesh != clear_mesh, "动态挡墙出现后立即切换精确裁切网格")
	var vertices: PackedVector3Array = sword._effect.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var reaches_wall := false
	var behind_wall := false
	for point in vertices:
		var global := sword._effect.global_transform * point
		if global.x > 0.7: reaches_wall = true
		if global.x > 0.8001: behind_wall = true
	check(reaches_wall and not behind_wall, "斩光与真实伤害一起被薄墙截断")
	wall.queue_free()
	await settle()
	sword._effect.display(Vector3.ZERO, Vector3.RIGHT, 1.6, 180.0, false, frames, 0.05, production, session._path, sword._surface, [player.get_rid()])
	check(sword._effect.mesh == clear_mesh, "挡墙移除后恢复共享平地网格")
	sword._effect.hide()
	await reset()
	var mob := enemy(Vector3(1.2, 0, 0))
	terrain.data.set_overlay(Vector2i(1, 0), TerrainData.OVERLAY_WATER, true)
	await settle()
	await manual()
	check(mob.health == 200.0, "基础剑术不跨越水面传播伤害")
	terrain.data.set_overlay(Vector2i(1, 0), TerrainData.OVERLAY_WATER, false)
	await settle()

func score_checks() -> void:
	await reset()
	var score: RunScore = session.get_node("RunScore")
	score.state.begin(77, score.rules)
	var batches: Array = []
	for index in 6:
		var mob := enemy(Vector3(1.0, 0, -0.25 + index * 0.1), 1.0)
		mob.damaged.connect(func(event: CombatDamageEvent): batches.append(event.score_batch))
	await manual()
	check(score.state.kill_score == 60 and score.state.burst_score == 25 and score.state.combo_score == 0, "真实普攻一刀六杀共享倍率并即时支付成片奖励")
	check(batches.size() == 6 and batches[0] != null and batches.all(func(batch): return batch == batches[0]), "刀锋接触到真实伤害事件保留同一计分批次")
	sword._physics_process(0.55)
	enemy(Vector3(1.0, 0, 0), 1.0)
	await manual()
	check(score.state.combo_score == 2 and score.state.total == 97, "下一刀接上连杀倍率，普通攻击同样受益")
	await reset()
	score.state.begin(78, score.rules)
	batches.clear()
	for index in 6:
		var mob := enemy(Vector3(1.0, 0, -0.25 + index * 0.1), 1.0)
		mob.damaged.connect(func(event: CombatDamageEvent): batches.append(event.score_batch))
		if index == 0: mob.damaged.connect(func(_event): session.set_combat_frozen(true), CONNECT_ONE_SHOT)
	await manual()
	check(session.combat_frozen and score.state.kills == 1, "升级式冻结在当前真实命中后暂停余下扣血与计分")
	session.set_combat_frozen(false)
	for frame in 17: sword._physics_process(1.0 / 60.0)
	check(score.state.kills == 6, "恢复后完成当前刀的全部击杀，实际 %d；待结算 %d，动作 %.3f，短顿 %s" % [score.state.kills, sword._pending_hits.size(), sword._age, player.hit_stop_active])
	check(score.state.total == 85, "恢复后不复制奖励，实际分数 %d" % score.state.total)
	check(batches.all(func(batch): return batch == batches[0]), "恢复后保留原刀计分批次")

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
	var score := RunScore.new()
	score.name = "RunScore"
	score.session = session
	score.rules = RunScoreRules.new()
	session.add_child(score)
	player = Player.new()
	player.animations = load("res://assets/meowa/player/animations.tres")
	player.action_visuals = PlayerActionVisuals.new()
	player.action_visuals.show_aim_guide = false
	player.ricochet_rules = PlayerRicochetRules.new()
	player.ricochet_rules.minimum_launch_speed = 8.0
	player.ricochet_rules.maximum_launch_speed = 8.0
	player.ricochet_rules.push_radius = 3.0
	player.sword_rules = PlayerSwordRules.new()
	player.sword_rules.audio_enabled = false
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.24
	shape.height = 1.06592
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = shape.height * 0.5
	player.add_child(collision)
	session.player = player
	world.add_child(player)
	sword = player.sword
	sword.strike_started.connect(func(direction, flying, reverse): strikes.append({"direction":direction, "flying":flying, "reverse":reverse}))
	sword.hit_landed.connect(func(enemy, damage, flying): damage_events.append({"enemy":enemy, "damage":damage, "flying":flying}))
	player.body_ricochet.enemy_pushed.connect(func(mob, _heading):
		check(mob.health < mob.max_health, "拨怪发生在真实伤害之后")
		pushes += 1)
	await settle()
	session._path.build(terrain, 0.32, [player.get_rid()])
	await manual_checks()
	await attack_speed_checks()
	await flight_checks()
	await freeze_checks()
	await input_and_art_checks()
	await score_checks()
	for mob in session.enemies: mob.cancel()
	session.enemies.clear()
	world.queue_free()
	await settle()
	print("Player basic sword: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
