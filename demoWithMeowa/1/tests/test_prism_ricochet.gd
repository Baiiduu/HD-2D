extends SceneTree

var checks := 0
var failures := 0
var scene: Node3D
var collision := ProjectileCollision.new()

func _initialize() -> void:
	create_timer(70.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle(frames := 4) -> void:
	for frame in frames: await physics_frame

func box(position_on_map: Vector3, size: Vector3, yaw := 0.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	node.shape = shape
	body.add_child(node)
	scene.add_child(body)
	body.position = position_on_map
	body.rotation.y = yaw
	return body

func enemy(position_on_map: Vector3, parent: Node3D) -> WaveEnemy:
	var mob := WaveEnemy.new()
	mob.wave_mode = true
	mob.spawn_delay = 0.0
	mob.health = 10000.0
	mob.collision_layer = 2
	mob.collision_mask = 0
	var node := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 0.7
	node.shape = shape
	node.position.y = 0.35
	mob.add_child(node)
	parent.add_child(mob)
	mob.global_position = position_on_map
	mob.set_physics_process(false)
	return mob

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var wall := box(Vector3(3, 0.5, 0), Vector3(0.02, 1, 4))
	await settle()
	var space := scene.get_world_3d().direct_space_state
	var hit := collision.wall_contact(space, Vector3(0, 0.45, 0), Vector3(8, 0.45, 0), 0.1, [])
	check(not hit.is_empty() and hit.distance < 3.0 and hit.distance > 2.8, "高速扫掠命中两厘米薄墙，不穿透")
	check(hit.normal.dot(Vector3.LEFT) > 0.99, "球形碰撞返回墙面真实法线")
	check(collision.wall_contact(space, Vector3(3, 0.45, 0), Vector3(8, 0.45, 0), 0.1, []).overlap, "起点嵌墙被阻挡")
	wall.rotation.y = PI * 0.25
	await settle()
	hit = collision.wall_contact(space, Vector3(0, 0.45, 0), Vector3(8, 0.45, 0), 0.1, [])
	check(not hit.is_empty() and absf(Vector3.RIGHT.bounce(hit.normal).z) > 0.99, "斜墙法线使弹丸转向九十度")
	wall.position.x = 20
	await settle()
	check(collision.wall_contact(space, Vector3(0, 0.45, 0), Vector3(8, 0.45, 0), 0.1, []).is_empty(), "移动障碍立即改变碰撞结果，没有旧碰撞缓存")
	wall.free()
	var round_prop: RicochetProp = load("res://scenes/buildings/ricochet/variants/round_pillar.tscn").instantiate()
	scene.add_child(round_prop)
	round_prop.position = Vector3(3, 0, 0)
	await settle()
	hit = collision.wall_contact(space, Vector3(0, 0.7, 0.2), Vector3(8, 0.7, 0.2), 0.08, [])
	check(not hit.is_empty() and absf(hit.normal.z) > 0.1, "现有圆柱提供曲面法线")
	round_prop.free()
	var first := enemy(Vector3(1, 0, 0), scene)
	var second := enemy(Vector3(2, 0, 0), scene)
	var off_path := enemy(Vector3(1.5, 0, 1), scene)
	await settle()
	var contacts := collision.enemy_contacts(space, Vector3(0, 0.45, 0), Vector3(4, 0.45, 0), 0.1, func(_mob): return true)
	check(contacts.size() == 2 and contacts[0].enemy == first and contacts[1].enemy == second, "命中按真实碰撞进入顺序排序，路径外敌人不命中")
	contacts = collision.enemy_contacts(space, Vector3(0, 0.45, 0), Vector3(0.8, 0.45, 0), 0.1, func(_mob): return true)
	check(contacts.size() == 1 and contacts[0].enemy == first, "扫掠命中胶囊边缘，不仅检查怪物中心")
	var crowd: Array[WaveEnemy] = [first, second, off_path]
	for index in 45: crowd.append(enemy(Vector3(1.0 + index * 0.02, 0, 0), scene))
	await settle()
	contacts = collision.enemy_contacts(space, Vector3(0, 0.45, 0), Vector3(4, 0.45, 0), 0.1, func(_mob): return true)
	check(contacts.size() == 47, "密集敌群不受固定碰撞返回数量限制")
	var effect: PrismRicochetEffect = load("res://scenes/combat/prism_ricochet_effect.tscn").instantiate()
	scene.add_child(effect)
	effect.launch(Vector3(0, 0.45, 0), Vector3.RIGHT, 1.0)
	effect.move_to(Vector3(2, 0.45, 0), Vector3.RIGHT)
	effect.show_contact(Vector3(2, 0.45, 0), true)
	effect.move_to(Vector3(2, 0.45, -2), Vector3.FORWARD)
	effect._process(0.0)
	check(effect._legs.size() == 2 and effect._legs[0].to == effect._legs[1].from, "折线拖尾保持真实转角，不跨墙连接成直线")
	check(is_equal_approx(effect._legs[0].from.distance_to(effect._legs[0].to) + effect._legs[1].from.distance_to(effect._legs[1].to), effect.trail_length), "短拖尾只保留固定长度，不把整个弹道留成光墙")
	var children := effect.get_child_count()
	effect.stop()
	for index in 30:
		effect.launch(Vector3.ZERO, Vector3.RIGHT, 1.0)
		effect.move_to(Vector3.RIGHT, Vector3.RIGHT)
		effect.show_contact(Vector3.RIGHT, true)
		effect.move_to(Vector3.RIGHT + Vector3.FORWARD, Vector3.FORWARD)
		effect.stop()
	check(effect.get_child_count() == children and not effect.is_processing() and not effect._light.visible, "反复发射复用折线网格与材质，闲置停止光源和更新")
	check(effect._pool[0].mesh.mesh == LightPierceEffect._shared_ribbon_mesh(), "新攻击复用共用光丝网格")
	scene.free()
	await settle()
	await integration()
	print("Prism ricochet: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)

func integration() -> void:
	var world: Node3D = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("MapEffects/BGM").music_enabled = false
	world.get_node("MapEffects/Weather").rain_audio_enabled = false
	world.get_node("MapEffects/Weather").wind_audio_enabled = false
	world.get_node("MapEffects/CoreFeedbackAudio").enabled = false
	# 只隔离当前测试场地的装饰碰撞，不修改正式场景或地形文件。
	var fixture := preload("res://tests/fixtures/combat_scene_fixture.gd")
	fixture.clear_placed_obstacles(world)
	fixture.enable_legacy_skills(world)
	root.add_child(world)
	current_scene = world
	await settle(12)
	var wave: WavePrototype = world.get_node("WavePrototype")
	var player: Player = world.get_node("Player")
	var skills: RunSkillManager = wave.get_node("RunSkillManager")
	var attack: PrismRicochetAutoAttack = wave.get_node("PrismRicochetAutoAttack")
	var growth: RunGrowth = wave.get_node("RunGrowth")
	# 碰撞与成长夹具展示完整技能池；正式开局仍从有效池抽三张。
	wave.skill_draft.initial_cards_per_draw = 100
	player.set_physics_process(false)
	wave.set_physics_process(false)
	growth.set_physics_process(false)
	attack.audio_enabled = false
	player.global_position = wave._path.ground_position(wave.global_position) + Vector3.UP * 0.03
	check(wave.start_run() and wave.phase == WavePrototype.Phase.READY, "开局先显示技能选择，不提前进入战斗")
	check(wave.skill_draft._initial_offered.has(&"initial:prism_ricochet") and wave.skill_draft._initial_offered.size() == skills._components.size(), "初始池保留棱光弹射并兼容新增技能")
	wave.skill_draft.initial_choice.close()
	wave.skill_draft._choose_initial(&"initial:prism_ricochet")
	check(wave.phase == WavePrototype.Phase.BATTLE and skills.get_level(&"prism_ricochet") == 1, "选择棱光弹射后以实际一级开始本局")
	attack.set_physics_process(false)
	wave._spawn_queue.clear()
	player.global_position = wave._path.ground_position(Vector3(-5, 0, 40)) + Vector3.UP * 0.03
	var origin := wave._path.ground_position(player.global_position)
	var outside := wave.terrain.to_global(Vector3(-1000, 0, -1000))
	check(collision.ground_limit(wave._path, outside, Vector3.RIGHT, 2.0, outside.y, 0.55) == 0.0, "地图外的弹丸终止，不在空白地形飞行")
	var before_stats := attack.get_attack_stats()
	wave.combat_modifiers.apply_buff(load("res://data/growth/damage.tres"))
	wave.combat_modifiers.apply_buff(load("res://data/growth/cooldown.tres"))
	wave.combat_modifiers.apply_buff(load("res://data/growth/range.tres"))
	var after_stats := attack.get_attack_stats()
	check(after_stats.damage > before_stats.damage and after_stats.interval < before_stats.interval, "本局伤害与冷却增益同时生效")
	check(after_stats.distance == before_stats.distance and not attack.get_combat_stats().has("range"), "纯弹丸不虚报通用覆盖范围收益")
	var last_damage := 0.0
	var last_distance := 0.0
	for level in range(1, 9):
		var values := attack.get_attack_stats(level)
		check(values.damage > last_damage and values.distance >= last_distance, "等级 %d 的伤害与飞行距离持续成长" % level)
		last_damage = values.damage
		last_distance = values.distance
	scene = world
	var wall := box(origin + Vector3(3, 0.5, 0), Vector3(0.02, 1, 4))
	var mob := enemy(origin + Vector3(1.4, 0, 0), world)
	wave.enemies.append(mob)
	await settle()
	var stats := attack.get_attack_stats()
	attack.launch(origin, Vector3.RIGHT, stats)
	var shot: Dictionary = attack._shots[0]
	attack._advance_shot(shot, 0.15)
	check(is_equal_approx(mob.health, 10000 - stats.damage), "穿过敌人后继续飞行")
	attack._advance_shot(shot, 0.01)
	check(is_equal_approx(mob.health, 10000 - stats.damage), "同一弹道段不会逐帧重复扣血")
	attack._advance_shot(shot, 0.25)
	check(shot.bounces == 1 and shot.direction.x < -0.99 and is_equal_approx(mob.health, 10000 - stats.damage * 2), "同一帧使用反射后的剩余路程，并允许回程命中")
	attack.cancel_current()
	var behind := enemy(origin + Vector3(3.8, 0, 0), world)
	wave.enemies.append(behind)
	attack.launch(origin, Vector3.RIGHT, stats)
	attack._advance_shot(attack._shots[0], 0.5)
	check(behind.health == 10000.0, "墙后敌人不被穿墙结算")
	attack.cancel_current()
	var second_wall := box(origin + Vector3(-1, 0.5, 0), Vector3(0.02, 1, 4))
	await settle()
	var capped := stats.duplicate()
	capped.bounces = 2
	attack.launch(origin, Vector3.RIGHT, capped)
	shot = attack._shots[0]
	attack._advance_shot(shot, 2.0)
	check(attack._shots.is_empty() and shot.bounces == 2, "高帧间隔内连续反射，达到次数上限后消退")
	second_wall.free()
	wall.free()
	await settle()
	for level in range(2, 9):
		skills.candidates()
		wave.skill_draft._choose(growth.state.level, StringName("skill:prism_ricochet:%d" % level))
	check(skills.get_level(&"prism_ricochet") == 8 and not skills.candidates().any(func(option): return String(option.id).begins_with("skill:prism_ricochet:")), "真实成长达到八级后退出升级池")
	attack.set_physics_process(false)
	attack._cooldown = 0.0
	check(attack.fire() and attack._shots.size() == 4, "八级实际齐射四枚独立晶体")
	shot = attack._shots[0]
	var old_position: Vector3 = shot.position
	var old_cooldown := attack._cooldown
	var old_player_position := player.global_position
	player.global_position += Vector3(0, 0, 2)
	player.blink_travelled.emit(old_player_position, player.global_position)
	check(shot.position == old_position and attack._cooldown == old_cooldown, "闪避不重置冷却，也不拖动已发射弹丸")
	wave.set_combat_frozen(true)
	attack._physics_process(1.0)
	check(shot.position == old_position and attack.process_mode == Node.PROCESS_MODE_DISABLED, "升级只冻结战斗计时与弹丸视觉子树")
	wave.set_combat_frozen(false)
	attack.set_physics_process(false)
	attack.cancel_current()
	var effect_count := attack._effects.size()
	attack._cooldown = 0.0
	attack.fire()
	check(attack._effects.size() == effect_count, "下一轮齐射复用已归还的特效节点")
	attack._phase_changed(WavePrototype.Phase.RESULT)
	check(attack._shots.is_empty() and attack._idle_effects.size() == effect_count, "阶段切换清理弹丸、拖尾和命中动画")
	var learned := skills.candidates()
	check(learned.any(func(option): return option.id == &"skill:fan_slash:1") and learned.any(func(option): return option.id == &"skill:light_pierce:1"), "初始弹射技能后仍能学习 A01 和 A02")
	attack.apply_skill_level(0)
	check(not attack.is_physics_processing() and attack._shots.is_empty(), "未学习或重开时停止无效工作")
	# 用正式怪物注册与死亡回调验证清波，不能只验证不死靶的扣血。
	for mob_to_remove in wave.enemies.duplicate(): mob_to_remove.free()
	wave.enemies.clear()
	check(wave._spawn_enemy(), "弹射技能可以命中正式波次注册的怪物")
	var real_enemy := wave.enemies[-1]
	real_enemy.set_physics_process(false)
	real_enemy.spawn_delay = 0.0
	real_enemy.health = 1.0
	real_enemy.experience_reward = 0
	var kill_origin := wave._path.ground_position(player.global_position)
	real_enemy.global_position = kill_origin + Vector3.RIGHT * 1.0
	attack.apply_skill_level(1)
	attack.set_physics_process(false)
	attack._cooldown = 0.0
	await settle()
	var kills_before := wave.kills
	check(attack.fire(), "自动寻敌按正式碰撞发射")
	attack._advance_shot(attack._shots[0], 0.12)
	check(wave.kills == kills_before + 1 and wave.enemies.is_empty(), "实际死亡只记录一次击杀，并移除场上引用")
	wave._pending = 0
	wave._clear_wave()
	check(wave.phase == WavePrototype.Phase.REST and attack._shots.is_empty(), "最后敌人死亡后进入休整，弹丸与特效清理")
	world.free()
	await settle()
