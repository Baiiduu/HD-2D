extends SceneTree

var checks := 0
var failures := 0
var world: Node3D
var wave: WavePrototype
var player: Player
var origin := Vector3.ZERO
var actors: Array[CreatureEnemy] = []
var index := WaveEnemySpatialIndex.new()
var hits := 0
var allow_hit := true

func _initialize() -> void:
	create_timer(90.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle(count := 4) -> void:
	# 无界 headless 可在同一显示帧追赶多个物理帧；同步删除队列后再查动态墙体。
	for frame in count:
		await physics_frame
		await process_frame

func ground(point: Vector3) -> Vector3:
	return wave._path.ground_position(point) + Vector3.UP * 0.03

func spawn(id: String, offset: Vector3) -> CreatureEnemy:
	var data: WaveEnemyDefinition = load("res://data/enemies/%s.tres" % id)
	var enemy := data.scene.instantiate() as CreatureEnemy
	enemy.configure_wave({"player": player, "terrain": wave.terrain, "camera": player.movement_camera,
		"navigation": wave._navigation_for(data), "attack_root": wave._attack_root, "spatial_index": index,
		"damage_player": func(_damage): hits += 1,
		"can_damage_player": func(_damage): return allow_hit,
		"request_spawn": Callable(), "combat_active": wave.combat_active}, data, 0.0)
	world.add_child(enemy)
	enemy.global_position = ground(origin + offset)
	enemy.set_physics_process(false)
	index.update(enemy)
	actors.append(enemy)
	return enemy

func cleanup_actors() -> void:
	for enemy in actors:
		if is_instance_valid(enemy): enemy.cancel()
	actors.clear()
	await settle()

func box(point: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	node.shape = shape
	body.add_child(node)
	world.add_child(body)
	body.global_position = point
	return body

func choose_origin() -> Vector3:
	var collision := ProjectileCollision.new()
	for z in [42, 40, 38, 44, 36]:
		for x in [-5, -7, -3, 1, 3]:
			var point := wave._path.ground_position(Vector3(x, 0, z))
			var clear := true
			for offset: Vector3 in [Vector3.ZERO, Vector3(6, 0, 0), Vector3(-3, 0, 0), Vector3(0, 0, 3), Vector3(0, 0, -3)]:
				var end := point + offset
				if wave._path._point_blocked(end) or collision.ground_limit(wave._path, point, offset.normalized(), offset.length(), point.y, 0.2) < offset.length() or not collision.wall_contact(world.get_world_3d().direct_space_state, point + Vector3.UP * 0.5, end + Vector3.UP * 0.5, 0.4, [player.get_rid()]).is_empty():
					clear = false
					break
			if clear: return point
	return wave._path.ground_position(wave.global_position)

func charger_checks() -> void:
	player.global_position = ground(origin + Vector3(3, 0, 0))
	var leaf := spawn("leaf_charger", Vector3.ZERO) as LeafChargerEnemy
	await settle()
	check(leaf._claim_warning(), "冲锋取得共用预告名额")
	leaf._begin_windup()
	check(leaf.attack_phase == LeafChargerEnemy.AttackPhase.WINDUP and leaf._telegraph.visible, "锁定方向前有完整蓄力预告")
	var heading := leaf._charge_direction
	leaf._visual_action = &"walk"
	leaf._visual_progress = -1.0
	leaf.velocity.x = 1.0
	var camera := player.movement_camera
	var right := camera.global_basis.x
	var back := camera.global_basis.z
	back.y = 0.0
	leaf._look = (back.normalized() - right).normalized()
	leaf._process(0.15)
	check(leaf.sprite.flip_h, "左向复用原生右向帧，身体像素不缩放")
	var animation_frame := leaf._frame
	var original_basis := camera.global_basis
	camera.global_basis = Basis(Vector3.UP, TAU / 8.0) * original_basis
	leaf._process(0.0)
	check(leaf._frame == animation_frame and leaf._charge_direction == heading and is_equal_approx(leaf.sprite.pixel_size, 0.016), "镜头旋转保留动画进度、实际锁线和人物像素密度")
	camera.global_basis = original_basis
	player.global_position = ground(origin + Vector3(3, 0, 2))
	leaf._combat_tick(leaf.rules.windup_seconds)
	check(leaf._charge_direction.is_equal_approx(heading) and leaf.attack_phase == LeafChargerEnemy.AttackPhase.CHARGE, "玩家横移不改变已锁方向")
	var wall := box(ground(origin + Vector3(1.8, 0, 0)) + Vector3.UP * 0.5, Vector3(0.02, 1, 3))
	await settle()
	for frame in 90:
		if leaf.attack_phase != LeafChargerEnemy.AttackPhase.CHARGE: break
		leaf._combat_tick(1.0 / 60.0)
	check(leaf.attack_phase == LeafChargerEnemy.AttackPhase.RECOVERY and leaf.global_position.x < wall.global_position.x, "高速冲锋碰动态薄墙停止，不穿墙或反弹")
	check(absf(leaf.global_position.z - origin.z) < 0.05 and hits == 0, "错开冲锋线可躲避，冲锋不追踪横移")
	check(not leaf._telegraph.visible and wave._attack_root.get_meta(&"enemy_warnings").is_empty(), "冲锋结束释放预告")
	wall.queue_free()
	await settle()
	leaf.global_position = ground(origin)
	player.global_position = ground(origin + Vector3(2, 0, 0))
	await settle()
	leaf._claim_warning()
	leaf._begin_windup()
	leaf._combat_tick(leaf.rules.windup_seconds)
	for frame in 90:
		if leaf.attack_phase != LeafChargerEnemy.AttackPhase.CHARGE: break
		leaf._combat_tick(1.0 / 60.0)
	check(hits == 1, "冲撞人物一次结算并进入恢复")
	await cleanup_actors()

func spitter_checks() -> void:
	hits = 0
	player.global_position = ground(origin + Vector3(4, 0, 0))
	var flower := spawn("lantern_spitter", Vector3.ZERO) as LanternSpitterEnemy
	await settle()
	flower._attack_clock = 0.0
	flower._combat_tick(0.01)
	check(flower.attack_phase == LanternSpitterEnemy.AttackPhase.WINDUP, "花兽在中距离停步蓄力")
	var heading := flower._shot_direction
	player.global_position = ground(origin + Vector3(4, 0, 1.5))
	flower._combat_tick(flower.rules.windup_seconds)
	var pool := flower._feedback
	var seed := pool.get_children().filter(func(node): return node is EnemySeedProjectile)[0] as EnemySeedProjectile
	seed.set_physics_process(false)
	check(seed.direction.is_equal_approx(heading), "吐籽沿预告方向直飞，不追踪")
	var wall := box(ground(origin + Vector3(2, 0, 0)) + Vector3.UP * 0.5, Vector3(0.02, 1, 2))
	await settle()
	seed._physics_process(1.0)
	check(not seed.active and hits == 0 and not seed.is_processing(), "种子连续扫掠薄墙即销毁，闲置停止工作")
	wall.queue_free()
	await settle()
	player.global_position = ground(origin + Vector3(2, 0, 0))
	var reused := pool.shoot_seed(flower, Vector3.RIGHT, flower.rules)
	reused.set_physics_process(false)
	check(reused == seed, "弹丸复用已完成对象")
	await settle()
	reused._physics_process(0.5)
	check(hits == 1 and not reused.active, "真实种子命中玩家且只结算一次")
	allow_hit = false
	pool.shoot_seed(flower, Vector3.RIGHT, flower.rules).set_physics_process(false)
	seed._physics_process(0.5)
	check(hits == 1 and not seed.active, "共享受击保护阻止重复扣血，仍吞掉种子")
	allow_hit = true
	player.global_position = ground(origin + Vector3(0.4, 0, 0))
	pool.shoot_seed(flower, Vector3.RIGHT, flower.rules).set_physics_process(false)
	await settle()
	seed._physics_process(0.01)
	check(hits == 2 and not seed.active, "种子出生时已接触人物也准确命中，不被当作无伤嵌墙")
	player.global_position = ground(origin + Vector3(4, 0, 2))
	pool.shoot_seed(flower, Vector3.RIGHT, flower.rules).set_physics_process(false)
	var before := seed.global_position
	wave.set_combat_frozen(true)
	seed._physics_process(0.5)
	check(seed.global_position == before and seed.active, "升级冻结保留弹丸原地与轨迹")
	wave.set_combat_frozen(false)
	flower.take_damage(9999.0)
	await settle()
	seed._physics_process(0.2)
	check(seed.active and seed.travel > 0.0, "发射者死亡后种子保留独立生命周期")
	seed._physics_process(2.0)
	check(not seed.active, "超过最大飞行距离停止，不永久残留")
	await cleanup_actors()
	flower = spawn("lantern_spitter", Vector3.ZERO)
	player.global_position = ground(origin + Vector3(1, 0, 0))
	await settle()
	before = flower.global_position
	flower._combat_tick(0.2)
	check(flower.global_position.x < before.x, "人物贴近时花兽小步退让")
	await cleanup_actors()

func frog_checks() -> void:
	player.global_position = ground(origin + Vector3(5, 0, 0))
	var frog := spawn("bell_frog", Vector3.ZERO) as BellFrogEnemy
	frog.rules = frog.rules.duplicate()
	frog.rules.speed_multiplier = 1.35
	var common := spawn("pot_brood", Vector3(1, 0, 0))
	var special := spawn("leaf_charger", Vector3(0, 0, 1))
	var far := spawn("mini_slime", Vector3(5, 0, 2))
	var high := spawn("mini_slime", Vector3(-1, 0, 0))
	high.global_position.y += 1.0
	index.update(high)
	await settle()
	var targets := frog._boost_targets()
	check(common in targets and special not in targets and far not in targets and high not in targets and frog not in targets, "鼓舞只影响同高、半径内普通同伴")
	var wall := box(ground(origin + Vector3(0.5, 0, 0)) + Vector3.UP * 0.5, Vector3(0.02, 1, 1))
	await settle()
	check(common not in frog._boost_targets(), "墙体阻挡鼓舞，不穿建筑")
	wall.queue_free()
	await settle()
	var health := common.health
	frog._pulse()
	check(is_equal_approx(common.effective_move_speed(), common.move_speed * 1.35) and common.health == health, "有限速度脉冲，不回血或改基础移速")
	var second := spawn("bell_frog", Vector3(0.5, 0, 0)) as BellFrogEnemy
	second.rules = second.rules.duplicate()
	second.rules.speed_multiplier = 1.5
	second._pulse()
	check(is_equal_approx(common.effective_move_speed(), common.move_speed * 1.5), "多来源鼓舞取最强，不相乘")
	second.take_damage(9999.0)
	check(is_equal_approx(common.effective_move_speed(), common.move_speed * 1.35), "强来源死亡立即恢复剩余来源")
	frog.cancel()
	check(common.effective_move_speed() == common.move_speed, "取消来源立即清除加速")
	common.add_speed_boost(special, 1.2, 0.5)
	common._tick_speed_boosts(0.51)
	check(common.effective_move_speed() == common.move_speed, "持续时间到期恢复基础移速")
	common.add_speed_boost(special, INF, 1.0)
	common.add_speed_boost(special, 1.2, NAN)
	check(common.effective_move_speed() == common.move_speed, "通用增益拒绝非有限数值")
	await cleanup_actors()
	var first := spawn("bell_frog", Vector3.ZERO)
	second = spawn("bell_frog", Vector3(0, 0, 2))
	var third := spawn("leaf_charger", Vector3(2, 0, 0))
	check(first._claim_warning() and second._claim_warning() and not third._claim_warning(), "同场主预告限制两处")
	first.cancel()
	check(third._claim_warning(), "来源取消后预告名额立即可用")
	await cleanup_actors()

func split_checks() -> void:
	player.global_position = ground(origin)
	wave._spawn_queue.clear()
	var data: PotBroodDefinition = load("res://data/enemies/pot_brood.tres")
	check(wave._spawn_enemy(data, ground(origin + Vector3(1, 0, 0))), "壶兽可通过实际波次生成接口接入")
	if wave.enemies.is_empty(): return
	var pot := wave.enemies[0] as PotBroodEnemy
	pot.set_physics_process(false)
	pot.spawn_delay = 0.0
	var deaths := wave.kills
	var pool := pot._feedback
	var effect := pool.death(pot.sprite, true)
	var size := pot.sprite.texture.get_size() * pot.sprite.pixel_size
	check(is_equal_approx(effect._pieces[0].global_basis.x.length(), size.x * 0.5) and is_equal_approx(effect._pieces[0].global_basis.y.length(), size.y * 0.5), "壶兽碎片首帧保持母体原尺寸")
	check((effect._pieces[0].global_position + effect._pieces[3].global_position).is_equal_approx(pot.sprite.global_position * 2.0), "碎裂首帧中心与母体完全一致")
	pot.take_damage(9999.0)
	pot.take_damage(9999.0)
	check(wave._pending == 2 and wave.kills == deaths + 1 and wave.enemies.is_empty(), "母体只死亡一次，两个幼体先登记后移除")
	wave._physics_process(0.2)
	check(wave.phase == WavePrototype.Phase.BATTLE and wave._pending == 2, "分裂等待阻止提前清波")
	var clock := wave._wave_clock
	wave.set_combat_frozen(true)
	wave._physics_process(1.0)
	check(wave._wave_clock == clock and wave._pending == 2, "冻结暂停分裂生成倒计时")
	wave.set_combat_frozen(false)
	wave._physics_process(0.5)
	check(wave.enemies.size() == 2 and wave._pending == 0, "近身击杀不被普通五米安全距离堵住，幼体实际出场")
	for child in wave.enemies:
		child.set_physics_process(false)
		check(child is MiniSlimeEnemy and TerrainPath.horizontal_distance(child.global_position, player.global_position) < wave.spawn_safe_distance and child.spawn_delay == 0.0, "幼体留在母体附近，出生后立即参与战斗")
	var children := wave.enemies.duplicate()
	for child in children:
		child.spawn_delay = 0.0
		child.take_damage(9999.0)
	check(wave._pending == 0 and wave.enemies.is_empty() and wave.kills == deaths + 3, "一代幼体死亡不递归分裂，真实击杀计数准确")
	wave._physics_process(0.01)
	check(wave.phase == WavePrototype.Phase.REST and wave._attack_root == null, "母体与幼体全部击杀后才进入休整并清掉弹丸")
	check(wave.start_next_wave() and wave.wave == 2, "清波后仍由主动继续进入下一波")
	wave._finish("test reset")

func run() -> void:
	var catalog: WaveEnemyCatalog = load("res://data/enemies/enemy_catalog.tres")
	check(catalog.enemies.size() == 6 and catalog.validation_error().is_empty(), "目录包含原史莱姆、四新怪物与独立幼体")
	var invalid := WaveEnemyCatalog.new()
	var brood: PotBroodDefinition = load("res://data/enemies/pot_brood.tres").duplicate()
	invalid.enemies.assign([brood])
	check(not invalid.validation_error().is_empty(), "幼体未登记在开局前明确拒绝")
	var other := brood.duplicate() as PotBroodDefinition
	other.enemy_id = &"other_pot"
	brood.child_enemy_id = &"other_pot"
	invalid.enemies.assign([brood, other])
	check(not invalid.validation_error().is_empty(), "其它壶兽也不能作为递归分裂幼体")
	for data in catalog.enemies:
		check(data.validation_error().is_empty(), "怪物资源数值合法：" + String(data.enemy_id))
		if data.enemy_id == &"slime": continue
		var actor := data.scene.instantiate() as CreatureEnemy
		check(actor != null and actor.animations.get_frame_count(&"walk_front") == 8, "具体场景接口和完整行走帧接入：" + String(data.enemy_id))
		for direction in [&"front", &"front_right", &"right", &"back_right", &"back"]:
			if data.enemy_id == &"mini_slime": break
			check(actor.animations.has_animation(StringName("walk_%s" % direction)), "行走支持相机八方向：" + String(direction))
			if data.enemy_id != &"pot_brood": check(actor.animations.get_frame_count(StringName("skill_%s" % direction)) == 8, "完整蓄力与恢复动画：" + String(direction))
		if actor.attack_sound: check(actor.attack_sound.get_length() > 0.0 and actor.attack_sound.get_length() < 2.0, "招式 Meowa 音效正常导入且为短音效")
		if actor.death_sound: check(actor.death_sound.get_length() > 0.0 and actor.death_sound.get_length() < 2.0, "壶兽碎裂 Meowa 音效正常导入")
		actor.free()
	world = load("res://scenes/world/world.tscn").instantiate()
	# 无界面怪物逻辑检查不继承编辑器开启的人工入场预览。
	world.get_node("WorldEntry").preview_on_direct_run = false
	# 清波即时规则在此独立验证；最后一击演出由专门用例验收。
	var presentation := world.get_node("WavePresentation") as WavePresentation
	presentation.settings = presentation.settings.duplicate()
	presentation.settings.finish_shot_enabled = false
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(world)
	current_scene = world
	await settle(16)
	wave = world.get_node("WavePrototype")
	# 本夹具验证普通混编波次，不继承编辑器当前选择的巨量怪潮模式。
	wave.population_rules = wave.population_rules.duplicate(true)
	wave.population_rules.simulation_mode = false
	player = wave.player
	player.set_physics_process(false)
	wave.set_physics_process(false)
	player.global_position = wave.global_position + Vector3.UP * 0.03
	check(wave.start_run(), "正式地图使用新目录实际开局")
	var choice: GrowthChoiceUI = wave.get_node("SkillDraft/InitialSkillChoice")
	if choice.is_open:
		choice.reveal_now()
		choice.select_option(choice._options[0].id)
		choice.confirm_selection()
	for component: Node in (wave.get_node("RunSkillManager") as RunSkillManager)._components.values(): component.process_mode = Node.PROCESS_MODE_DISABLED
	check(wave._pending == 18 and wave._wave_total(wave._run_waves[1]) == 28 and wave._wave_total(wave._run_waves[2]) == 40, "前三波初始总数保持 18／28／40")
	for number in [1, 2, 3, 4, 10, 1000000000]:
		var ids := {}
		for entry in wave._definition_for_wave(number).entries:
			if entry.mixed_horde:
				for data in wave._horde_pool: ids[data.enemy_id] = true
			else: ids[entry.enemy.enemy_id] = true
		check(ids.size() == (4 if number == 1 else 5) and not ids.has(&"mini_slime"), "首波混编四种主怪，后续穿插辅助蛙，幼体只从分裂进入")
	var parameters: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(world)
	for property in ["charge_speed", "projectile_speed", "child_enemy_id", "boost_seconds"]:
		check(parameters.any(func(item): return item.property == property and item.category == "战斗与成长"), "新怪物参数可从统一编辑器入口调整：" + property)
	var late := wave._definition_for_wave(1000000000)
	# 从真实晚期混编队列统计母体，不能把混合怪潮中的所有怪物都当成壶兽。
	wave._spawn_queue.clear()
	wave._set_phase(WavePrototype.Phase.REST)
	wave.wave = 1000000000 - 1
	check(wave.start_next_wave(), "极晚期波次可通过真实调度建立完整队列")
	var late_children := 0
	for job in wave._spawn_queue:
		if job.enemy is PotBroodDefinition: late_children += 2
	check(wave._spawn_queue.size() == wave._wave_total(late) and late_children > 0, "晚期真实队列包含全部主怪与可分裂母体")
	check(wave._run_population.max_queued_per_wave >= wave._spawn_queue.size() + late_children, "实际混编数量为所有一代幼体保留登记预算")
	wave.retreat()
	wave.return_home()
	player.global_position = wave.global_position + Vector3.UP * 0.03
	check(wave.start_run(), "预算检查后重新开始正常怪物行为用例")
	choice.reveal_now()
	check(choice.select_option(choice._options[0].id), "重新开局选择有效技能")
	choice.confirm_selection()
	for component: Node in (wave.get_node("RunSkillManager") as RunSkillManager)._components.values(): component.process_mode = Node.PROCESS_MODE_DISABLED
	wave._spawn_queue.clear()
	origin = choose_origin()
	print("Quartet sample: ", origin)
	await charger_checks()
	await spitter_checks()
	await frog_checks()
	await split_checks()
	for audio in world.find_children("*", "AudioStreamPlayer", true, false): audio.stop()
	(world.get_node("MapEffects/GameAudio") as GameAudio).stop_all()
	await create_timer(0.1).timeout
	world.queue_free()
	await settle()
	await create_timer(0.1).timeout
	print("Enemy quartet: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
