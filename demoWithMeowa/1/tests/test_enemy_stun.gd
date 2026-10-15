extends SceneTree

var world: Node3D
var wave: WavePrototype
var player: Player
var origin := Vector3(-5,0,42)
var checks := 0
var failures: Array[String] = []
var actors: Array[SlimeEnemy] = []
var hits := 0
var children_requested: Array[StringName] = []

func _initialize() -> void:
	create_timer(75).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL: ",message)

func settle(count := 4) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func spawn(id: String, offset := Vector3.ZERO, health_scale := 1.0) -> SlimeEnemy:
	var data: WaveEnemyDefinition = load("res://data/enemies/%s.tres" % id).duplicate()
	var enemy := data.scene.instantiate() as SlimeEnemy
	enemy.configure_wave({"player":player,"terrain":wave.terrain,"camera":player.movement_camera,
		"navigation":wave._navigation_for(data),"attack_root":wave._attack_root,"spatial_index":wave._spatial_index,
		"damage_player":func(_amount): hits += 1,"request_spawn":Callable(),
		"request_spawn_by_id":func(child_id, count, _delay, _point):
			for number in count: children_requested.append(child_id),
		"combat_active":wave.combat_active,"health_multiplier":health_scale},data,0)
	world.add_child(enemy)
	enemy.global_position = wave._path.ground_position(origin+offset)+Vector3.UP*0.03
	enemy.set_physics_process(false)
	enemy.defeated.connect(func(actor): wave.enemies.erase(actor))
	wave.enemies.append(enemy)
	wave._spatial_index.update(enemy)
	actors.append(enemy)
	return enemy

func cleanup() -> void:
	player.body_ricochet.cancel(true)
	for actor in actors:
		if is_instance_valid(actor):
			wave.enemies.erase(actor)
			actor.cancel()
	actors.clear()
	await settle()

func prepare_push() -> PlayerRicochet:
	var body := player.body_ricochet
	body._settings = player.ricochet_rules.duplicate()
	body._settings.push_stun_seconds = 1.0
	body._settings.push_radius = 0.5
	body._pushed.clear()
	body._sword_contacts.clear()
	body.state = PlayerRicochet.State.FLYING
	body.direction = Vector3.RIGHT
	return body

func choose_origin() -> Vector3:
	var collision := ProjectileCollision.new()
	for z in [42,40,38,44,36]:
		for x in [-5,-7,-3,1,3]:
			var point := wave._path.ground_position(Vector3(x,0,z))
			var clear := true
			for offset: Vector3 in [Vector3.ZERO,Vector3(6,0,0),Vector3(-3,0,0),Vector3(0,0,3),Vector3(0,0,-3)]:
				if wave._path._point_blocked(point+offset) or not collision.wall_contact(world.get_world_3d().direct_space_state,point+Vector3.UP*0.5,point+offset+Vector3.UP*0.5,0.4,[player.get_rid()]).is_empty():
					clear = false
					break
			if clear: return point
	return Vector3.INF

func push_checks() -> void:
	var ordinary := spawn("wave_slime",Vector3(1,0,-0.3))
	var heavy := spawn("pot_brood",Vector3(2,0,0.3))
	var body := prepare_push()
	body._push_segment(origin,origin+Vector3(3,0,0))
	check(ordinary.stun_remaining == 0.0 and heavy.stun_remaining == 0.0,"基础剑术启用时，未实际命中不提前拨怪或控制")
	ordinary.take_damage(1)
	heavy.take_damage(1)
	body.push_after_sword_hit(ordinary,origin+Vector3(1,0,0),Vector3.RIGHT)
	body.push_after_sword_hit(heavy,origin+Vector3(2,0,0),Vector3.RIGHT)
	check(ordinary.stun_remaining == 1.0 and heavy.stun_remaining == 0.5,"正式弹射拨怪接入普通 1 秒、壶兽 0.5 秒")
	check(ordinary._push_remaining > 0.0 and heavy._push_remaining > 0.0,"眩晕不取消已接收的平滑外力")
	var start := ordinary.global_position
	ordinary._physics_process(0.22)
	check(TerrainPath.horizontal_distance(start,ordinary.global_position)>0.1 and is_equal_approx(ordinary.stun_remaining,0.78),"从命中瞬间计时，眩晕期间仍正常滑开")
	var remaining := ordinary.stun_remaining
	body._push_segment(origin,origin+Vector3(3,0,0))
	check(ordinary.stun_remaining == remaining,"同一次弹射再次经过不重复刷新控制")
	ordinary.apply_stun(0.2)
	check(ordinary.stun_remaining == remaining,"较短的重复眩晕不覆盖较长剩余时间")
	ordinary.apply_stun(1.0)
	check(ordinary.stun_remaining == 1.0,"新控制刷新到 1 秒，不累加为 1.78 秒")
	check(ordinary._stun_effect.visible and ordinary._stun_effect.multimesh.instance_count == 3,"真实受控对象显示三颗环绕星")
	var effect := ordinary._stun_effect
	var material := effect.material_override as StandardMaterial3D
	var texture := material.albedo_texture
	check(texture.get_size() == Vector2(10,10) and not texture.get_image().is_invisible() and texture.get_image().get_pixel(0,0).a == 0,"使用非空原生 10×10 透明素材")
	check(material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST and is_equal_approx(effect._pixel,player.sprite.pixel_size*player.sprite.global_basis.x.length()),"最近邻采样匹配人物实际像素密度")
	check(effect.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF,"渲染帧环绕不写物理插值缓存")
	effect._process(0.1)
	var age := effect._age
	var point := ordinary.global_position
	wave.set_combat_frozen(true)
	await settle(12)
	check(ordinary.stun_remaining == 1.0 and effect._age == age and ordinary.global_position == point,"升级冻结同时保留控制时间、星星进度和物理位置")
	wave.set_combat_frozen(false)
	ordinary.global_position += Vector3(0.2,0,0.2)
	ordinary.reset_physics_interpolation()
	await settle(2)
	effect._process(0.1)
	check(TerrainPath.horizontal_distance(effect.global_position,ordinary.global_position)<0.0001,"星星随受拨怪物移动")
	check(effect._age > age,"恢复战斗后特效继续环绕")
	heavy._physics_process(0.51)
	check(heavy.stun_remaining == 0.0 and not heavy._stun_effect.visible and not heavy._stun_effect.is_processing(),"重型怪到时恢复，闲置特效停止处理")
	# 独立用例建立新的发射快照；只清目标表不能绕过同次发射的接力去重。
	body = prepare_push()
	body.state = PlayerRicochet.State.RECOVERY
	body._pushed.clear()
	heavy.global_position = origin+Vector3(0.2,0.03,0.2)
	check(body.push_after_sword_hit(heavy,origin,Vector3.RIGHT) and heavy.stun_remaining == 0.5,"飞行剑术的延后拨怪共用同一眩晕入口")
	await cleanup()

func control_checks() -> void:
	player.global_position = origin+Vector3(0.6,0.03,0)
	var enemy := spawn("wave_slime")
	hits = 0
	enemy.apply_stun(1.0)
	var start := enemy.global_position
	enemy._physics_process(0.8)
	check(hits == 0 and TerrainPath.horizontal_distance(start,enemy.global_position)<0.01,"眩晕禁止追击与接触伤害")
	enemy._physics_process(0.21)
	check(enemy.stun_remaining == 0.0 and hits == 0,"结束控制的帧不会补发积压接触伤害")
	enemy._physics_process(0.02)
	check(hits == 1,"恢复后重新执行正常接触攻击")
	var effect := enemy._stun_effect
	enemy.apply_stun(1.0)
	check(enemy._stun_effect == effect,"再次眩晕复用原节点和材质")
	enemy.stun_remaining = 0.0
	enemy._on_stun_ended()
	enemy.definition.stun_duration_multiplier = 0.0
	check(not enemy.apply_stun(1.0) and not effect.visible,"独立眩晕免疫不残留标记")
	check(enemy.apply_push_impulse(Vector3.FORWARD,1,0.22),"眩晕免疫仍允许物理拨动")
	enemy.definition.stun_duration_multiplier = 1.0
	enemy.knockback_multiplier = 0.0
	check(prepare_push()._apply_push(enemy,Vector3.FORWARD) and enemy.stun_remaining == 1.0,"抗击退与抗眩晕相互独立")
	var grown := spawn("wave_slime",Vector3(-2,0,0),10.0)
	grown.apply_stun(1.0)
	check(grown.max_health == grown.definition.health*10 and grown.stun_remaining == 1.0,"无尽生命成长不暗中缩短控制")
	check(not grown.apply_stun(NAN) and not grown.apply_stun(-1),"拒绝无效控制时间")
	grown.definition.stun_duration_multiplier = NAN
	check(not grown.definition.validation_error().is_empty(),"怪物资源校验拒绝非有限抗性")
	await cleanup()

func attack_checks() -> void:
	player.global_position = origin+Vector3(3,0.03,0)
	var leaf := spawn("leaf_charger") as LeafChargerEnemy
	leaf._attack_clock = 0.0
	leaf._claim_warning()
	leaf._begin_windup()
	check(leaf.attack_phase == LeafChargerEnemy.AttackPhase.WINDUP,"真实冲锋预告已开始")
	leaf.apply_stun(1)
	check(leaf.attack_phase == LeafChargerEnemy.AttackPhase.CHASE and not leaf._telegraph.visible and wave._attack_root.get_meta(&"enemy_warnings").is_empty(),"眩晕立即取消冲锋预告并释放预算")
	leaf._physics_process(1.01)
	leaf._physics_process(0.02)
	check(leaf.attack_phase == LeafChargerEnemy.AttackPhase.WINDUP and leaf._phase_clock == leaf.rules.windup_seconds,"恢复后重新完整预告，不从旧预告末尾突然冲出")
	leaf._claim_warning()
	leaf._begin_windup()
	leaf._combat_tick(leaf.rules.windup_seconds)
	check(leaf.attack_phase == LeafChargerEnemy.AttackPhase.CHARGE,"冲锋实际进入高速阶段")
	leaf.apply_stun(1)
	check(leaf.attack_phase == LeafChargerEnemy.AttackPhase.CHASE and leaf.velocity.x == 0 and leaf.velocity.z == 0,"眩晕能打断正在进行的普通怪冲锋")
	await cleanup()
	player.global_position = origin+Vector3(4,0.03,0)
	var flower := spawn("lantern_spitter") as LanternSpitterEnemy
	flower._attack_clock = 0.0
	flower._combat_tick(0.01)
	check(flower.attack_phase == LanternSpitterEnemy.AttackPhase.WINDUP,"真实吐籽预告已开始")
	flower.apply_stun(1)
	flower._physics_process(1.01)
	flower._physics_process(0.02)
	check(flower.attack_phase == LanternSpitterEnemy.AttackPhase.WINDUP and flower._phase_clock == flower.rules.windup_seconds and flower._feedback.get_child_count()==0,"打断吐籽后重新完整预告，不补发旧种子")
	var seed := flower._feedback.shoot_seed(flower,Vector3.RIGHT,flower.rules)
	seed.set_physics_process(false)
	flower.apply_stun(1)
	check(seed.active,"已发出的种子保持世界轨迹")
	await cleanup()
	var frog := spawn("bell_frog") as BellFrogEnemy
	var ally := spawn("wave_slime",Vector3(0,0,1))
	frog._pulse()
	var speed := ally.effective_move_speed()
	frog._attack_clock = 0.0
	frog._combat_tick(0.01)
	check(frog.attack_phase == BellFrogEnemy.AttackPhase.WINDUP,"苔蛙有普通同伴时真实预告鼓舞")
	frog.apply_stun(1)
	check(frog.attack_phase == BellFrogEnemy.AttackPhase.MOVE and not frog._telegraph.visible and ally.effective_move_speed() == speed,"中断新鼓舞，已发出的有限增益继续计时")
	var pot := spawn("pot_brood",Vector3(0,0,-2))
	pot.apply_stun(1)
	children_requested.clear()
	pot.take_damage(10000)
	check(children_requested.size()==2 and children_requested.all(func(id): return id==&"mini_slime"),"眩晕不阻止正常死亡分裂")
	await cleanup()

func run() -> void:
	world = load("res://scenes/world/world.tscn").instantiate()
	world.get_node("LoadoutUI").save_enabled = false
	world.get_node("WavePrototype/RunGrowth").enabled = false
	root.add_child(world)
	current_scene = world
	await settle(16)
	wave = world.get_node("WavePrototype")
	player = wave.player
	wave.set_physics_process(false)
	player.set_physics_process(false)
	player.sword.set_physics_process(false)
	player.global_position = wave.global_position+Vector3.UP*0.03
	check(wave.start_run(),"正式挑战可开始")
	var skills: RunSkills = wave.get_node("RunSkills")
	if skills.initial_choice.is_open:
		skills.initial_choice.reveal_now()
		skills.initial_choice.select_option(skills.initial_choice._options[0].id)
		skills.initial_choice.confirm_selection()
	for component: Node in skills._components.values(): component.process_mode = Node.PROCESS_MODE_DISABLED
	wave._spawn_queue.clear()
	origin = choose_origin()
	check(origin.is_finite(),"在当前正式地图找到真实开阔通路夹具")
	await push_checks()
	await control_checks()
	await attack_checks()
	var entries: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(world)
	for property in ["push_stun_seconds","stun_duration_multiplier","push_group_link_distance","push_group_search_radius","push_group_edge_margin","push_arrival_arc_degrees","push_chain_layers","push_chain_speed_retention","push_chain_stun_retention","push_chain_min_speed"]:
		check(entries.any(func(item): return item.property==property and item.common),"参数总览可调整："+property)
	wave.retreat()
	world.queue_free()
	await settle(8)
	print(JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
