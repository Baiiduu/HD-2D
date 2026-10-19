extends "res://tests/test_aim_path_preview.gd"

var mirror: MirrorMarkAutoAttack
var prism: PrismRicochetAutoAttack
var collision_query := ProjectileCollision.new()

func imprint(actor: WaveEnemy) -> Dictionary:
	mirror.launch(actor.global_position + Vector3.LEFT, Vector3.RIGHT, mirror.get_attack_stats())
	var shot: Dictionary = mirror._shots[-1]
	mirror._advance_shot(shot, 0.08)
	check(mirror._marks.has(actor.get_instance_id()), "真实镜梭伤害后建立可用镜面")
	for active in mirror._shots.duplicate(): mirror._finish_shot(active)
	return mirror._marks.get(actor.get_instance_id(), {})

func contact(z := 0.0, mirrors := true) -> Dictionary:
	return collision_query.wall_contact(world.get_world_3d().direct_space_state,
		Vector3(0, 0.48, z), Vector3(6, 0.48, z), 0.1, [player.get_rid()],
		ProjectileCollision.REFLECTION_MASK if mirrors else 1)

func clear_marks() -> void:
	mirror.cancel_current()
	prism.cancel_current()
	clear_enemies()
	await settle()

func path_checks() -> void:
	session._path = navigation
	session._path_ready = true
	player.sprite.pixel_size = 0.02
	player.sprite.scale = Vector3.ONE * 0.8
	for scene_name in ["mirror_mark", "prism_ricochet"]:
		var component: PrismRicochetAutoAttack = load("res://scenes/combat/%s_auto_attack.tscn" % scene_name).instantiate()
		component.session = session
		component.audio_enabled = false
		world.add_child(component)
		component.apply_skill_level(1)
		component.set_physics_process(false)
		if component is MirrorMarkAutoAttack: mirror = component
		else: prism = component
	player.sword.rules.enabled = false

	var actor := enemy(Vector3(3, 0, 0))
	actor.health = 1000
	await settle()
	var mark := await imprint(actor)
	if mark.is_empty(): return
	var expected: Vector3 = Vector3.RIGHT.bounce(mark.normal).normalized()
	check(not contact().is_empty() and contact(0.0, false).is_empty(), "可反弹查询识别镜面，原有墙体查询不受影响")
	var stats := prism.get_attack_stats()
	var before := actor.health
	prism.launch(Vector3.ZERO, Vector3.RIGHT, stats)
	var shot: Dictionary = prism._shots[-1]
	prism._advance_shot(shot, 0.35)
	check(shot.bounces == 1 and shot.direction.x < -0.99, "怪物实体在内部镜片前时，棱光先在真实身体外沿反射")
	check(is_equal_approx(actor.health, before - stats.damage), "镜片接触与紧邻回程不对宿主重复扣血")
	prism.cancel_current()
	# Put the fixture's finite mirror in front of the body to verify true contact ordering.
	var saved_surface_transform: Transform3D = mark.effect._surface.global_transform
	var saved_remote_path: NodePath = mark.effect._surface._follow.remote_path
	mark.effect._surface._follow.remote_path = NodePath()
	mark.effect._surface.global_position += Vector3.LEFT
	mark.effect._surface.force_update_transform()
	await settle()
	before = actor.health
	mark.effect._glint_age = 0.5
	prism.launch(Vector3.ZERO, Vector3.RIGHT, stats)
	shot = prism._shots[-1]
	prism._advance_shot(shot, 0.35)
	check(shot.bounces == 1 and shot.direction.dot(expected) > 0.999 and actor.health == before, "实际位于怪物之前的镜面按固定法线反射，不穿镜伤害宿主")
	check(mark.effect._glint_age == 0.0, "反射触发原有镜片闪光，复用反馈")
	prism.cancel_current()
	var capped := stats.duplicate()
	capped.bounces = 0
	prism.launch(Vector3.ZERO, Vector3.RIGHT, capped)
	shot = prism._shots[-1]
	prism._advance_shot(shot, 0.35)
	check(shot.bounces == 0 and prism._shots.is_empty(), "棱光无反弹预算时在镜片结束，不能免费反射")
	mark.effect._surface.global_transform = saved_surface_transform
	mark.effect._surface._follow.remote_path = saved_remote_path
	mark.effect._surface._follow.force_update_cache()
	mark.effect._surface.force_update_transform()
	await settle()
	before = actor.health
	mirror.launch(Vector3.ZERO, Vector3.RIGHT, mirror.get_attack_stats())
	shot = mirror._shots[-1]
	mirror._advance_shot(shot, 0.35)
	check(shot.bounces == 1 and shot.direction.dot(expected) > 0.999 and is_equal_approx(actor.health, before - mirror.get_attack_stats().damage), "镜梭仍先伤害宿主再按旧镜面反射，不被新增碰撞提前截住")
	for active in mirror._shots.duplicate(): mirror._finish_shot(active)

	var route := await predict()
	check(route.contacts.size() == 1 and route.segments.size() == 2 and route.segments[1].heading.dot(expected) > 0.999, "蓄力预览使用同一有限镜片和保存法线")
	check(player.collision_mask == 1 and PhysicsServer3D.body_get_collision_mask(player.get_rid()) == 1, "只读预览还原物理查询层")
	var invalid := AimPathData.new()
	query.trace(player, Vector3(NAN, 0, 0), 8.0, 0.9, 1, 1.0, navigation, player.bounds, 0.2, invalid)
	check(invalid.segments.is_empty() and PhysicsServer3D.body_get_collision_mask(player.get_rid()) == 1, "预测无效输入早退也还原普通碰撞层")
	before = actor.health
	await compare_flight(route, "移动怪物上的反射镜印")
	check(body.bounce_count == 1 and body.direction.dot(expected) > 0.999, "真实人物胶囊与预览一致地撞镜反弹")
	check(actor.health == before and PhysicsServer3D.body_get_collision_mask(player.get_rid()) == 1, "人物反弹保留原伤害规则，飞行后恢复普通碰撞层")

	player.ricochet_rules.bounce_speed_cost = 100.0
	route = await predict()
	check(route.end_reason == &"speed_depleted" and route.segments.size() == 1, "人物余速不足时在镜面停止")
	await compare_flight(route, "镜面续弹速度不足")
	check(body.bounce_count == 0 and not body.flying, "镜面不能绕过人物统一耗速规则")
	player.ricochet_rules.bounce_speed_cost = 0.5
	await reset()
	player.move_and_collide(Vector3.RIGHT * 6.0)
	check(player.position.x > 5.9, "普通走路仍可穿过镜印，不被反射层挡住")

	await reset()
	var wall := box(Vector3(1.4, 0.6, 0), Vector3(0.02, 1.2, 4))
	await settle()
	route = await predict()
	check(route.contacts.size() == 1 and route.segments[1].heading.x < -0.99, "真实墙体在镜面前时优先反弹，不隔墙借镜")
	before = actor.health
	prism.launch(Vector3.ZERO, Vector3.RIGHT, stats)
	shot = prism._shots[-1]
	prism._advance_shot(shot, 0.35)
	check(shot.bounces == 1 and shot.direction.x < -0.99 and actor.health == before, "棱光同样按墙体与镜片实际先后顺序碰撞")
	wall.queue_free()
	await clear_marks()

func target_checks() -> void:
	await reset()
	var actor := enemy(Vector3(3, 0, 0))
	actor.health = 1000
	await settle()
	var mark := await imprint(actor)
	if mark.is_empty(): return
	var surface: StaticBody3D = mark.effect._surface
	var normal: Vector3 = mark.normal
	actor.position.z = 2.0
	actor.rotation.y = PI / 3.0
	await settle()
	check(contact().is_empty() and not contact(2.0).is_empty(), "怪物移动后旧位置失效、新位置立即参与镜面扫掠")
	check(surface.global_basis.z.dot(normal) > 0.999, "宿主转向不改变镜面的固定世界朝向")
	var back := collision_query.wall_contact(world.get_world_3d().direct_space_state,
		Vector3(6, 0.48, 2), Vector3(0, 0.48, 2), 0.1, [player.get_rid()], ProjectileCollision.REFLECTION_MASK)
	check(not back.is_empty() and ProjectileCollision.reflection_normal(back.collider, back.normal, Vector3.LEFT).dot(Vector3.LEFT) < 0.0, "镜片背面也能反射，脱离法线朝向入射侧")
	check(contact(3.0).is_empty(), "镜片边缘有界，不形成横穿怪群的无限平面")
	actor.position.y = 2.0
	await settle()
	check(contact(2.0).is_empty(), "高处镜片不会隔层反射地面弹丸")
	actor.position = Vector3(3, 0.03, 0)
	await settle()
	mark.remaining = 0.0
	mirror._tick_marks(0.01)
	check(surface.collision_layer == 0 and contact().is_empty(), "镜印到期立即撤除碰撞，碎裂动画不继续挡路")
	mark.effect._process(mark.effect.break_time)
	var next := await imprint(actor)
	check(next.effect._surface == surface, "下一次贴印复用原镜面碰撞体与形状")
	actor.take_damage(10000)
	check(surface.collision_layer == 0 and contact().is_empty(), "宿主死亡当帧撤除反射，无残留物理镜面")
	await clear_marks()

	actor = enemy(Vector3(3, 0, 0))
	actor.health = 1000
	await settle()
	mark = await imprint(actor)
	mirror.cancel_current()
	check(mark.effect._surface.collision_layer == 0 and contact().is_empty(), "清波、卸下技能和重试统一移除镜面碰撞")
	await clear_marks()
	print("Mirror collision integration checks completed")
