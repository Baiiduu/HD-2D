extends SceneTree

var checks := 0
var failures := 0
var world: Node3D
var wave: WavePrototype
var attack: MirrorMarkAutoAttack
var origin := Vector3.ZERO

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle(frames := 4) -> void:
	for frame in frames: await physics_frame

func mob(offset: Vector3, health := 100.0) -> WaveEnemy:
	var enemy := WaveEnemy.new()
	enemy.wave_mode = true
	enemy.spawn_delay = 0.0
	enemy.health = health
	enemy.collision_layer = 2
	enemy.collision_mask = 0
	var node := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.28
	shape.height = 0.7
	node.shape = shape
	node.position.y = 0.35
	enemy.add_child(node)
	world.add_child(enemy)
	enemy.global_position = origin + offset
	wave.enemies.append(enemy)
	enemy.set_physics_process(false)
	return enemy

func clear_mobs() -> void:
	attack.cancel_current()
	for enemy in wave.enemies:
		if is_instance_valid(enemy): enemy.free()
	wave.enemies.clear()

func wall(offset: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.02, 1, 4)
	node.shape = shape
	body.add_child(node)
	world.add_child(body)
	body.global_position = origin + offset + Vector3.UP * 0.5
	return body

func run() -> void:
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	# 隔离扫掠与反射的夹具；正式地图的地编、相机与存档不改动。
	load("res://scripts/previews/prop_preview_stage.gd").prepare(world)
	root.add_child(world)
	current_scene = world
	await settle(12)
	wave = world.get_node("WavePrototype")
	attack = wave.get_node("MirrorMarkAutoAttack")
	var player: Player = world.get_node("Player")
	var skills: RunSkills = wave.get_node("RunSkills")
	var growth: RunGrowth = wave.get_node("RunGrowth")
	player.set_physics_process(false)
	wave.set_physics_process(false)
	growth.set_physics_process(false)
	attack.audio_enabled = false
	player.global_position = wave._path.ground_position(wave.global_position) + Vector3.UP * 0.03
	check(attack.skill_level == 0 and not attack.is_physics_processing(), "未学习时不消耗战斗更新")
	check(skills.initial_cards_per_draw == 3, "正式开局仍是抽三张，而非新增技能后展示全部")
	skills.initial_cards_per_draw = 4
	check(wave.start_run() and wave.phase == WavePrototype.Phase.READY, "开局等待实际技能选择")
	check(skills._initial_pool.size() == 4 and skills._initial_offered.has(&"initial:mirror_mark"), "镜印进入当前四技能初始池")
	skills.initial_choice.close()
	skills._choose_initial(&"initial:mirror_mark")
	check(wave.phase == WavePrototype.Phase.BATTLE and skills.get_level(&"mirror_mark") == 1, "初始选择实际学习镜印并开始波次")
	attack.set_physics_process(false)
	wave._spawn_queue.clear()
	player.global_position = wave._path.ground_position(Vector3(-5, 0, 40)) + Vector3.UP * 0.03
	origin = wave._path.ground_position(player.global_position)
	var stats := attack.get_attack_stats()
	check(stats.damage == 14.0 and stats.bounces == 2 and stats.mark_duration == 4.0, "一级参数来自独立配置")
	var first := mob(Vector3(1.4, 0, 0), 20)
	var side := mob(Vector3(1.4, 0, -2), 20)
	var straight := mob(Vector3(3.4, 0, 0), 20)
	await settle()
	attack.launch(origin, Vector3.RIGHT, stats)
	var shot: Dictionary = attack._shots[0]
	attack._advance_shot(shot, 0.14)
	check(first.health == 6.0 and attack._marks.has(first.get_instance_id()), "首击立即伤害，史莱姆剩六点血并贴印")
	check(shot.bounces == 1 and shot.direction.z < -0.9, "第一击立即折向侧面，而非只贴印等待下一弹")
	var mark := attack._marks[first.get_instance_id()]
	var initial_normal: Vector3 = mark.normal
	check(shot.direction.is_equal_approx(Vector3.RIGHT.bounce(initial_normal)), "弹道使用镜面法线真实反射")
	attack._advance_shot(shot, 0.2)
	check(side.health == 6.0 and straight.health == 20.0, "沿折射后的新路径扫掠，原直线路径不继续扣血")
	check(shot.hits.size() == 2 and shot.bounces == 2, "反射次数与已命中敌人按每枚弹丸记录")
	var effect: MirrorMarkEffect = mark.effect
	var previous := effect._sprite.global_position
	first.global_position += Vector3(0.4, 0, 0.3)
	effect._process(0.05)
	check(effect._sprite.global_position.is_equal_approx(previous + Vector3(0.4, 0, 0.3)), "镜印跟随移动怪物，不留在旧位置")
	check(mark.normal == initial_normal, "移动怪物不会重新瞄准已有镜面")
	first.take_damage(2.0)
	check(first.health == 4.0 and attack._marks.has(first.get_instance_id()), "镜印不提供无敌或改变通用受伤接口")
	await settle()
	# 改变入射方向，使用同一张镜印；致死命中也完成最后反射。
	attack.launch(first.global_position + Vector3.FORWARD * 1.5, Vector3.BACK, stats)
	var lethal: Dictionary = attack._shots[-1]
	attack._advance_shot(lethal, 0.13)
	check(first.dead and first.health == 0.0, "二次攻击正常击败已经贴印的史莱姆")
	check(lethal.bounces >= 1 and lethal.direction.is_equal_approx(Vector3.BACK.bounce(initial_normal)), "致死命中仍按旧镜面完成反射")
	check(not attack._marks.has(first.get_instance_id()) and effect._breaking, "死亡镜印移出逻辑并播放碎裂")
	clear_mobs()
	await settle()
	# 墙面反射后再经过同一只怪物，验证整枚弹丸去重。
	first = mob(Vector3(1.4, 0, 0))
	await settle()
	attack.launch(origin, Vector3.RIGHT, stats)
	attack._advance_shot(attack._shots[0], 0.14)
	mark = attack._marks[first.get_instance_id()]
	mark.normal = Vector3.LEFT
	mark.effect.normal = Vector3.LEFT
	attack._shots.clear()
	var back_wall := wall(Vector3(-1, 0, 0))
	await settle()
	var before := first.health
	attack.launch(origin, Vector3.RIGHT, stats)
	shot = attack._shots[-1]
	attack._advance_shot(shot, 1.2)
	check(first.health == before - stats.damage and shot.hits.size() == 1, "墙面回程再次穿过同敌人，不重复扣血或刷新镜面")
	check(shot.bounces == 2 and attack._shots.is_empty(), "怪物与墙面共用反射预算，最终按飞行距离消退")
	back_wall.free()
	clear_mobs()
	await settle()
	# 空间阻挡仍真实扫掠，镜印不会隔墙瞬连。
	var front_wall := wall(Vector3(0.7, 0, 0))
	first = mob(Vector3(1.4, 0, 0))
	var raised := mob(Vector3(0.3, 1.2, 0))
	await settle()
	attack.launch(origin, Vector3.RIGHT, stats)
	attack._advance_shot(attack._shots[0], 0.5)
	check(first.health == 100.0 and raised.health == 100.0, "墙后和不同高度的怪物不被镜印穿透结算")
	front_wall.free()
	clear_mobs()
	await settle()
	first = mob(Vector3(1.4, 0, 0))
	await settle()
	attack.launch(origin, Vector3.RIGHT, stats)
	attack._advance_shot(attack._shots[0], 0.14)
	mark = attack._marks[first.get_instance_id()]
	effect = mark.effect
	var clock: float = mark.remaining
	var position_before: Vector3 = attack._shots[0].position
	wave.set_combat_frozen(true)
	attack._physics_process(1.0)
	check(mark.remaining == clock and attack._shots[0].position == position_before and effect.can_process() == false, "升级同时冻结弹丸、镜印时限和全部子特效")
	wave.set_combat_frozen(false)
	attack.set_physics_process(false)
	attack._tick_marks(4.1)
	check(attack._marks.is_empty() and effect._breaking, "镜印时限到达后碎裂，没有无限保留的反射点")
	effect._process(effect.break_time)
	check(effect in attack._idle_marks and not effect.is_processing(), "碎裂结束归还节点池并停止更新")
	var pixel_size: float = player.sprite.pixel_size * player.sprite.global_basis.x.length()
	var projectile: MirrorProjectileEffect = attack._effects[-1]
	check(is_equal_approx(projectile.pixel_size, pixel_size) and is_equal_approx(effect.pixel_size, pixel_size), "弹体与镜印沿用当前人物实际缩放后的像素密度")
	check(projectile.head_texture.get_size() == Vector2(32, 16) and effect.mirror_texture.get_size() == Vector2(24, 32), "Meowa 素材保持原生非正方形像素尺寸")
	projectile.launch(origin, Vector3.RIGHT, 3.0)
	check(is_equal_approx(projectile._head.global_basis.x.length(), 32 * pixel_size), "升级视觉倍率不会放大像素颗粒")
	projectile.stop()
	var effects_count := attack._effects.size()
	var marks_count := attack._mark_effects.size()
	attack.cancel_current()
	first.health = 100.0
	attack.launch(origin, Vector3.RIGHT, stats)
	attack._advance_shot(attack._shots[0], 0.14)
	check(attack._effects.size() == effects_count and attack._mark_effects.size() == marks_count, "再次出手复用弹丸、镜印和材质节点")
	var raw := attack.get_attack_stats()
	wave.combat_modifiers.apply_buff(load("res://data/growth/damage.tres"))
	wave.combat_modifiers.apply_buff(load("res://data/growth/cooldown.tres"))
	wave.combat_modifiers.apply_buff(load("res://data/growth/range.tres"))
	var boosted := attack.get_attack_stats()
	check(is_equal_approx(boosted.damage, raw.damage * 1.2) and is_equal_approx(boosted.interval, raw.interval * 0.9), "共享伤害与冷却增益只叠加一次")
	check(boosted.distance == raw.distance and not attack.get_combat_stats().has("range"), "通用覆盖范围不虚报纯弹丸收益")
	for level in range(2, 5):
		skills.candidates()
		skills._choose(growth.state.level, StringName("skill:mirror_mark:%d" % level))
	check(skills.get_level(&"mirror_mark") == 4 and attack.get_attack_stats().count == 2, "真实升级到四级，齐射两枚各自结算")
	check(not skills.candidates().any(func(option): return String(option.id).begins_with("skill:mirror_mark:")), "满级镜印退出成长候选池")
	check(skills.candidates().any(func(option): return option.id == &"skill:fan_slash:1"), "镜印开局后仍可学习其它武器")
	# 同一局通过真实升级选择学习 A01，验证其命中不受镜印干预。
	skills.candidates()
	skills._choose(growth.state.level, &"skill:fan_slash:1")
	var fan: FanAutoAttack = wave.get_node("FanAutoAttack")
	fan.set_physics_process(false)
	fan.audio_enabled = false
	fan.knockback_distance = 0.0
	var plain_damage := first.health
	check(fan.start_swing(), "学习的 A01 可以向已贴镜印的怪物出手")
	for frame in 50: fan._physics_process(1.0 / 60.0)
	check(is_equal_approx(plain_damage - first.health, fan.get_attack_stats().damage), "其它武器保持自身正常伤害，镜印没有护盾或额外伤害")
	fan.apply_skill_level(0)
	attack.cancel_current()
	attack._cooldown = 0.0
	attack.set_physics_process(false)
	check(attack.fire() and attack._shots.size() == 2, "四级实际发射两枚独立弹体")
	var cooldown_before := attack._cooldown
	position_before = attack._shots[0].position
	player.global_position += Vector3(0, 0, 2)
	player.blink_travelled.emit(player.global_position - Vector3(0, 0, 2), player.global_position)
	check(attack._cooldown == cooldown_before and attack._shots[0].position == position_before, "闪身保持攻击进度与已发射弹丸的世界轨迹")
	attack._phase_changed(WavePrototype.Phase.REST)
	check(attack._marks.is_empty() and attack._shots.is_empty() and attack._mark_effects.all(func(item): return not item.is_processing()), "清波休整取消镜印、弹体与残影")
	clear_mobs()
	attack.apply_skill_level(1)
	attack.set_physics_process(false)
	check(wave._spawn_enemy(), "镜印可攻击当前波次实际登记的敌人")
	var actual := wave.enemies[-1]
	actual.set_physics_process(false)
	actual.spawn_delay = 0.0
	actual.health = 1.0
	actual.experience_reward = 0
	origin = wave._path.ground_position(player.global_position)
	actual.global_position = origin + Vector3.RIGHT * 1.5
	await settle()
	var kills_before := wave.kills
	attack.launch(origin, Vector3.RIGHT, attack.get_attack_stats())
	shot = attack._shots[0]
	attack._advance_shot(shot, 0.15)
	check(wave.kills == kills_before + 1 and wave.enemies.is_empty() and shot.bounces == 1, "真实死亡回调记录一次击杀，移除怪物后仍完成致死反射")
	wave._pending = 0
	wave._clear_wave()
	check(wave.phase == WavePrototype.Phase.REST and attack._shots.is_empty() and attack._marks.is_empty(), "最后一只敌人死后进入现有波间休整并清理特效")
	skills.reset()
	check(attack.skill_level == 0 and not attack.is_physics_processing(), "重开通过现有技能流程清空镜印成长")
	clear_mobs()
	world.free()
	await settle()
	print("Mirror mark: ", checks, " checks, ", failures, " failures")
	quit(1 if failures else 0)
