extends SceneTree

const SESSION := preload("res://tests/fixtures/ricochet_session.gd")
var checks := 0
var failures := 0
var world: Node3D
var terrain: Terrain
var session: WavePrototype
var player: Player
var split_requests: Array[Vector3] = []

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", message)

func settle(count := 3) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func spawn(id := "wave_slime", point := Vector3(1, 0, 0), health := 1.0) -> SlimeEnemy:
	var data := load("res://data/enemies/%s.tres" % id).duplicate() as WaveEnemyDefinition
	data.health = health
	var enemy := data.scene.instantiate() as SlimeEnemy
	enemy.configure_wave({"player": player, "terrain": terrain, "camera": player.movement_camera,
		"navigation": session._path, "attack_root": session._attack_root, "spatial_index": session._spatial_index,
		"damage_player": Callable(), "request_spawn": Callable(), "combat_active": session.combat_active,
		"request_spawn_by_id": func(_id, _count, _delay, position): split_requests.append(position)}, data, 0.0)
	world.add_child(enemy)
	enemy.global_position = point + Vector3.UP * 0.03
	enemy.set_wave_tick_enabled(false)
	enemy.set_process(false)
	session.enemies.append(enemy)
	session._spatial_index.update(enemy)
	enemy.defeated.connect(session._enemy_defeated)
	return enemy

func pool() -> EnemyFeedbackPool:
	return session._attack_root.get_node_or_null("EnemyFeedbackPool") as EnemyFeedbackPool

func active_effects() -> Array[EnemyDeathEffect]:
	var result: Array[EnemyDeathEffect] = []
	if pool():
		for child in pool().get_children():
			if child is EnemyDeathEffect and child.is_processing(): result.append(child)
	return result

func kill(enemy: SlimeEnemy, source: StringName, direction := Vector3.RIGHT, velocity := Vector3.ZERO) -> EnemyDeathEffect:
	enemy.take_damage(999.0, {"source": source, "direction": direction, "motion_velocity": velocity})
	var effects := active_effects().filter(func(item): return item.get("_burst_only") != true)
	return effects[-1] if not effects.is_empty() else null

func clear_effects() -> void:
	for effect in active_effects(): effect._process(10.0)
	if pool() and pool().has_method("_process"): pool()._process(10.0)

func source_checks() -> void:
	for id in ["wave_slime", "leaf_charger", "lantern_spitter", "pot_brood", "bell_frog", "mini_slime"]:
		for source in [&"basic_sword", &"flight_sword", &"ricochet_storm"]:
			var enemy := spawn(id)
			var point := enemy.global_position
			var deaths := session.kills
			var effect := kill(enemy, source)
			check(effect != null and effect.get("_knockout") == true, "%s 的 %s 致死命中生成击飞快照" % [id, source])
			check(enemy.dead and session.kills == deaths + 1 and enemy not in session.enemies, "击飞之前立即结算死亡并撤销存活登记")
			enemy.take_damage(999.0, {"source": source})
			check(session.kills == deaths + 1 and active_effects().size() == 1, "重复伤害不重复死亡或创建尸体")
			if effect:
				check(effect._pieces[0].visible, "近身击飞保留完整死亡帧主体")
				check(effect.get("_stars") != null and effect.get("_stars").multimesh.instance_count == 3, "击飞复用三颗原生眩晕金星")
			if id == "pot_brood":
				check(split_requests.size() == 2 and split_requests[0].distance_to(point) < 0.5, "壶兽在原死亡点立即登记幼体，不随视觉飞走")
				split_requests.clear()
			clear_effects()
			await settle(1)
	for source in [&"A01", &"A02", &"prism_ricochet", &"mirror_mark", &""]:
		var ordinary := kill(spawn(), source)
		check(ordinary == null, "普通史莱姆的远程／无来源死亡保持原规则：" + String(source))
		var creature := kill(spawn("pot_brood"), source)
		check(creature != null and creature.get("_knockout") == false and creature._shards, "壶兽远程击杀保留原有碎片，不附加金星")
		if creature:
			check(creature._materials[0].next_pass == null and creature._pieces[0].get_instance_shader_parameter("death_energy") == 0.0, "池复用回旧死亡效果时撤下补画和额外亮度")
		clear_effects()
		split_requests.clear()
		await settle(1)
	var survivor := spawn("wave_slime", Vector3(1, 0, 0), 100.0)
	survivor.take_damage(1.0, {"source": &"basic_sword", "direction": Vector3.RIGHT})
	check(not survivor.dead and survivor.stun_remaining == 0.0 and active_effects().is_empty(), "非致死近战不击飞、不新增真实眩晕")
	check(survivor.apply_stun(0.5), "原有真实眩晕接口仍可独立生效")
	survivor._stun_effect._process(0.1)
	check(survivor._stun_effect.visible and survivor._stun_effect.multimesh.instance_count == 3, "原有眩晕继续播放同一组三颗金星")
	survivor.stun_remaining = 0.0
	survivor._stun_effect._process(0.0)
	check(not survivor._stun_effect.visible, "真实眩晕到期仍正常撤下金星")
	survivor.health_loss_disabled = true
	survivor.take_damage(999.0, {"source": &"flight_sword", "direction": Vector3.RIGHT})
	check(not survivor.dead and active_effects().is_empty(), "锁血模拟不伪造死亡表现")
	survivor.cancel()
	session.enemies.erase(survivor)
	await settle(1)

func motion_checks() -> void:
	var enemy := spawn()
	enemy.sprite.flip_h = true
	enemy.sprite.flip_v = true
	enemy.sprite.modulate = Color(0.8, 0.6, 0.5, 0.7)
	var texture := enemy.sprite.texture
	var size := texture.get_size() * enemy.sprite.pixel_size * enemy.sprite.global_basis.x.length()
	var effect := kill(enemy, &"flight_sword", Vector3.FORWARD, Vector3.RIGHT * 12.0)
	if not effect: return
	effect.set_process(false)
	var start := effect._pieces[0].global_position
	effect._process(0.20)
	var position := effect._pieces[0].global_position
	check(Vector2(position.x - start.x, position.z - start.z).length() > 0.3 and position.y > start.y, "弹射击飞沿本次随机方向腾空散开")
	check(effect._size.is_equal_approx(size) and effect._materials[0].get_shader_parameter("effect_texture") == (texture.atlas if texture is AtlasTexture else texture), "尸体使用死亡当前原帧与实际像素尺寸")
	check(is_equal_approx(effect._pieces[0].global_basis.x.length(), size.x), "飞行不随距离或镜头放大怪物贴图")
	var uv: Vector4 = effect._pieces[0].get_instance_shader_parameter("frame_rect")
	check(uv.z < 0.0 and uv.w < 0.0 and effect._pieces[0].get_instance_shader_parameter("tint") == enemy.sprite.modulate, "快照保留当前图集、双向翻转及透明度乘色")
	var fast_distance: float = effect.get("_travel").length()
	var stars: EnemyStunEffect = effect.get("_stars")
	check(stars.global_position.y > position.y and not stars.is_processing(), "金星跟随空中尸体，由同一个时钟推进")
	player.movement_camera.rotation.y += 0.7
	var travel: Vector3 = effect.get("_travel")
	effect._process(0.05)
	var offset := effect._pieces[0].global_position - start
	check(Vector3(offset.x, 0, offset.z).normalized().dot(travel.normalized()) > 0.999, "Q/E 观察方向变化不改变已经选定的随机世界轨迹")
	effect._process(10.0)
	check(not effect.is_processing() and not stars.visible and effect in pool()._idle_deaths, "消散后停止更新，金星隐藏且回到共用池")
	var materials := effect._materials.duplicate()
	var reused := kill(spawn(), &"basic_sword", Vector3.LEFT)
	check(reused == effect and reused._materials == materials and reused._age == 0.0, "下一次击杀复用节点与材质并清除旧轨迹")
	check(reused.get("_travel").length() < fast_distance, "高速弹射击杀比普通近战飞得更有力")
	reused._process(0.15)
	check(reused._pieces[0].global_position.distance_to(reused._position) > 0.1, "普攻同样立即腾空散开")
	clear_effects()
	await settle(1)

func random_spread_checks() -> void:
	var sample := spawn("wave_slime", Vector3(1, 0, 0), 100.0)
	var effect := pool().death(sample.sprite, false, player.action_visuals)
	var random: RandomNumberGenerator = effect.get("_random")
	check(random != null, "死亡表现使用独立随机流")
	if random: random.seed = 314159
	var sectors := PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0])
	for index in 64:
		effect.begin(sample.sprite, false, player.movement_camera, player.action_visuals, {"direction": Vector3.RIGHT})
		var travel: Vector3 = effect.get("_travel")
		var angle := fposmod(atan2(travel.z, travel.x), TAU)
		sectors[mini(7, int(angle / (TAU / 8.0)))] += 1
	for index in 8: check(sectors[index] > 0, "同一来向连续击杀仍覆盖八方随机扇区：%d" % index)
	seed(8181)
	var expected := randi()
	seed(8181)
	effect.begin(sample.sprite, false, player.movement_camera, player.action_visuals)
	check(randi() == expected, "视觉随机不消耗出怪、掉落或抽卡共用的全局随机流")
	var material := effect._materials[0]
	var overlay := material.next_pass as ShaderMaterial
	check(overlay != null and overlay.shader.code.contains("stencil_mode read, compare_equal, 1") and not overlay.shader.code.contains("depth_test_disabled"), "击飞复用怪物轮廓补画，保留建筑遮挡")
	effect._process(effect.get("_duration") * 0.65)
	check(float(effect._pieces[0].get_instance_shader_parameter("opacity")) >= 0.65, "旧死亡主体保留轮廓，同时退亮给当前攻击")
	var energy: Variant = effect._pieces[0].get_instance_shader_parameter("death_energy")
	check(energy != null and float(energy) > 0.0 and float(energy) < 0.3, "旧死亡帧退亮后仍保留少量原色亮度")
	if overlay:
		check(overlay.shader.code.contains("instance uniform float opacity : instance_index(2)") and overlay.shader.code.contains("instance uniform float death_energy : instance_index(5)") and energy == effect._pieces[0].get_instance_shader_parameter("death_energy"), "怪物遮挡补画同步透明度与亮度")
	effect._process(10.0)
	sample.cancel()
	session.enemies.erase(sample)
	await settle(1)

func wall_checks() -> void:
	var effect := kill(spawn(), &"flight_sword", Vector3.RIGHT, Vector3.RIGHT * 12.0)
	if not effect: return
	effect.set_process(false)
	var direction: Vector3 = effect.get("_travel").normalized()
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.02, 4.0, 3.0)
	collision.shape = shape
	wall.add_child(collision)
	world.add_child(wall)
	wall.position = effect._position + direction * 0.7
	wall.position.y = 2.0
	wall.rotation.y = atan2(-direction.z, direction.x)
	await settle()
	effect._process(0.2)
	var stopped := effect._pieces[0].global_position
	var horizontal := Vector2(stopped.x - effect._position.x, stopped.z - effect._position.z)
	check(effect.get("_blocked") == true and horizontal.length() < 0.7, "任意随机方向的击飞仍被真实薄墙截住")
	effect._process(0.15)
	var next := effect._pieces[0].global_position
	check(is_equal_approx(next.x, stopped.x) and is_equal_approx(next.z, stopped.z), "挡墙后保留原地腾空消散，不反弹或额外伤害")
	effect._process(0.25)
	check(effect._pieces[0].global_position.distance_to(Vector3(stopped.x, effect._pieces[0].global_position.y, stopped.z)) < 0.001, "落地弹跳与滑出也不会越过已命中的墙")
	effect._process(10.0)
	wall.queue_free()
	clear_effects()
	await settle()

func sword_checks() -> void:
	var sword := player.sword
	sword.cancel()
	sword.set_physics_process(false)
	var enemy := spawn()
	check(sword.request_manual(Vector3.RIGHT), "实际普通近战可发起攻击")
	for frame in 18: sword._physics_process(1.0 / 60.0)
	check(enemy.dead and active_effects().size() == 1 and active_effects()[0].get("_knockout") == true, "真实普通挥剑命中入口接入击飞死亡")
	clear_effects()
	await settle(1)
	sword.cancel()
	enemy = spawn("wave_slime", Vector3(0.5, 0, -0.5))
	sword._stats = sword.get_stats(true)
	sword._heading = Vector3.FORWARD
	sword._flight_swing = true
	sword._hits.clear()
	sword._collect_hits(Vector3.ZERO, Vector3.RIGHT, 0.0, 1.0, true, 0.0, 0.1)
	check(not sword._pending_hits.is_empty(), "真实移动挥扫记录致死接触")
	player.body_ricochet.direction = Vector3.LEFT
	sword._drain_hits()
	check(enemy.dead and active_effects().size() == 1, "真实飞行剑术接入击飞死亡")
	if enemy.dead:
		var motion: Vector3 = enemy.get("fatal_hit_context").get("motion_velocity", Vector3.ZERO)
		check(motion.x > 9.0 and absf(motion.z) < 0.001, "接触时保存真实路段速度，稍后的反弹或取消不改写击飞来向")
	clear_effects()
	await settle(1)
	sword.cancel()
	enemy = spawn("wave_slime", Vector3(0.5, 0, -0.5))
	sword._stats = sword.get_stats(false)
	sword._heading = Vector3.FORWARD
	sword._flight_swing = false
	sword._collect_hits(Vector3.ZERO, Vector3.RIGHT, 0.0, 1.0, false, 0.0, 0.25)
	player.global_position = Vector3(8, 0.03, 0)
	player.velocity = Vector3.ZERO
	sword._drain_hits()
	check(enemy.dead and enemy.fatal_hit_context.get("motion_velocity", Vector3.ZERO).is_equal_approx(Vector3.RIGHT * 4.0), "走路普攻记录实际移动速度，延后结算不重读已停下的人物")
	check(enemy.fatal_hit_context.get("contact_distance", INF) < 3.0 and active_effects().size() == 1 and active_effects()[0]._knockout, "普通剑术记录接触距离，之后人物移远仍保留近身击杀表现")
	player.global_position = Vector3(0, 0.03, 0)
	clear_effects()
	await settle(1)

func storm_checks() -> void:
	var storm: RicochetStorm = load("res://scenes/combat/ricochet_storm.tscn").instantiate()
	storm.session = session
	storm.audio_enabled = false
	world.add_child(storm)
	check(storm.apply_skill_level(1), "真实奔雷组件学习一级")
	session._path_ready = true
	await settle(1)
	storm.set_physics_process(false)
	var first := spawn("wave_slime", Vector3(1, 0, 0))
	var second := spawn("pot_brood", Vector3(2.25, 0, 0))
	player.velocity = Vector3.RIGHT * 12.0
	check(storm.discharge(Vector3(0, 0.03, 0)), "真实奔雷沿两层向外传导")
	storm.set_physics_process(false)
	check(first.dead and not second.dead and active_effects().size() == 1 and active_effects()[0].get("_knockout") == true, "首片雷伤的真实致死命中生成击飞与金星")
	player.body_ricochet.cancel(true)
	player.global_position = Vector3(5, 0.03, 0)
	player.velocity = Vector3.ZERO
	storm._physics_process(0.1)
	storm.set_physics_process(false)
	check(second.dead and active_effects().size() == 2 and active_effects()[1].get("_knockout") == true, "弹射结束后的在途雷伤仍生成同款击飞")
	if second.dead:
		check(second.fatal_hit_context.source == &"ricochet_storm" and second.fatal_hit_context.direction.x > 1.0, "保留原雷伤来源及实际传播方向")
		check(second.fatal_hit_context.get("motion_velocity", Vector3.ZERO).is_equal_approx(Vector3.RIGHT * 12.0) and second.fatal_hit_context.get("storm_layer", -1) == 1, "在途扩散保留本轮初始速度和实际传播层，不读取落地后的速度")
	var effects := active_effects()
	if not effects.is_empty():
		var effect := effects[-1]
		check(effect.get("_travel").length() > 0.0 and effect.get("_random") != null, "雷伤击飞同样使用独立的随机抛射")
	check(split_requests.size() == 2, "雷伤击杀壶兽仍立即登记幼体")
	split_requests.clear()
	clear_effects()
	storm.cancel_current()
	storm.queue_free()
	player.global_position = Vector3(0, 0.03, 0)
	await settle(1)

func toy_impact_checks() -> void:
	var frames: SpriteFrames = player.action_visuals.get("melee_death_impact_frames")
	check(frames != null and frames.get_frame_count(&"bounce") == 6, "死亡爆点使用独立绑定的原生 Meowa 六帧")
	var pause: Variant = player.action_visuals.get("melee_death_hit_pause")
	check(pause != null and float(pause) > 0.0, "死亡主体具有独立短顿")
	if pause == null: return
	var effect := kill(spawn(), &"flight_sword", Vector3.RIGHT, Vector3.RIGHT * 12.0)
	if not effect: return
	effect.set_process(false)
	var origin := effect._pieces[0].global_position
	effect._process(float(pause) * 0.5)
	check(effect._pieces[0].global_position.is_equal_approx(origin) and effect._pieces[1].visible, "短顿只留住死亡帧，原地爆点已经出现")
	var flash := float(effect._pieces[0].get_instance_shader_parameter("hit_flash"))
	check(flash >= 0.25 and flash <= 0.5, "击杀特写短闪保留实体颜色，不被长定格放大成纯白块")
	check(not session.combat_frozen and player.body_ricochet.state == PlayerRicochet.State.IDLE, "局部短顿不冻结人物和战斗")
	effect._process(0.12)
	check(effect._pieces[0].global_position.distance_to(origin) > 0.6, "短顿后快速弹出，避免缓慢漂浮")
	var impact_duration := float(player.action_visuals.get("melee_death_impact_seconds"))
	effect._process(impact_duration)
	check(not effect._pieces[1].visible and effect._pieces[0].visible, "短爆点先收起，完整死亡帧继续翻飞")
	var land_time := float(pause) + float(player.action_visuals.get("melee_death_air_seconds"))
	effect._process(maxf(0.0, land_time - effect._age))
	check(is_equal_approx(effect._pieces[0].global_position.y, origin.y) and absf(float(effect.get("_spin"))) >= TAU, "快速完成一圈多翻滚和落下，余迹独立收尾")
	effect._process(10.0)
	await settle(1)

func lifecycle_checks() -> void:
	var effect := kill(spawn(), &"basic_sword")
	if not effect: return
	session.set_combat_frozen(true)
	var age := effect._age
	await create_timer(0.05).timeout
	check(not effect.can_process() and effect._age == age, "升级冻结同时暂停尸体和金星")
	session.set_combat_frozen(false)
	await create_timer(0.03).timeout
	check(effect._age > age, "恢复后继续原击飞进度")
	clear_effects()
	player.action_visuals.set("melee_death_enabled", false)
	check(kill(spawn(), &"basic_sword") == null, "地图独立关闭后保持原史莱姆死亡行为")
	check(kill(spawn(), &"ricochet_storm") == null, "奔雷击飞共用地图独立开关")
	var old := kill(spawn("pot_brood"), &"basic_sword")
	check(old != null and not old.get("_knockout") and old._shards, "关闭时恢复原新怪死亡表现")
	clear_effects()
	player.action_visuals.set("melee_death_enabled", true)
	effect = kill(spawn(), &"basic_sword")
	var effect_ref: WeakRef = weakref(effect)
	session._attack_root.queue_free()
	await settle()
	check(effect_ref.get_ref() == null, "清波／退出清理攻击根时，不留尸体与金星")

func readability_checks() -> void:
	check(player.action_visuals.get("combat_readability_enabled") == true, "World 独立开启当前攻击与旧余迹的层次")
	check(pool().has_method("melee_contact"), "非致死飞行剑伤共用反馈池的原生命中短闪")
	if not pool().has_method("melee_contact"): return
	clear_effects()
	var sword := player.sword
	var previous_rules := sword.rules
	sword.rules = load("res://data/combat/scenes/world/player/basic_sword.tres").duplicate()
	sword.cancel()
	sword._begin(Vector3.FORWARD, true)
	check(sword._settings.meowa_body_opacity > sword.rules.meowa_body_opacity, "飞行刀锋适量提亮，不回写基础剑术资源")
	var enemy := spawn("wave_slime", Vector3(0.5, 0, -0.5), 100.0)
	sword._stats = sword.get_stats(true)
	sword._collect_hits(Vector3.ZERO, Vector3.RIGHT, 0.0, 1.0, true, 0.0, 0.1)
	sword._drain_hits()
	var contacts: Array = pool().get_children().filter(func(node): return node.get_script() == load("res://scripts/enemies/enemy_melee_contact.gd"))
	check(enemy.health < 100.0 and not enemy.dead and contacts.size() == 1, "真实非致死接触只加一次短闪，不额外伤害或击飞")
	if not contacts.is_empty():
		var contact: MeshInstance3D = contacts[0]
		var material := contact.material_override as ShaderMaterial
		check(material.next_pass != null and contact.visible and contact.mesh is QuadMesh, "短闪保留怪物补画与建筑遮挡，复用原生网格")
		check(is_equal_approx(contact.get("_point").y, enemy.sprite.global_position.y), "命中短闪锚在当前身体接触处，不使用头顶数字锚点")
		var age: float = contact.get("_age")
		session.set_combat_frozen(true)
		await create_timer(0.03).timeout
		check(is_equal_approx(float(contact.get("_age")), age), "命中短闪随升级冻结")
		session.set_combat_frozen(false)
		contact._process(1.0)
		check(not contact.visible and not contact.is_processing(), "命中帧播完回池并停止处理")
		var reused: Variant = pool().call("melee_contact", enemy.get_damage_feedback_position(), 0.016, Vector3.RIGHT, player.action_visuals)
		check(reused == contact and reused.material_override == material, "再次命中复用网格与材质")
		contact._process(1.0)
	sword._start_tail(Vector3.ZERO, 0.0)
	sword._advance_tails(0.16)
	sword._update_tails()
	var tails: Array = sword._tail_pool.filter(func(tail): return tail.age >= 0.0)
	check(not tails.is_empty() and float(tails[0].effect._material.get_shader_parameter("opacity")) < sword.rules.effect_opacity, "前一刀完整余迹退亮，把视觉重心交给当前刀锋")
	sword.cancel()
	sword.rules = previous_rules
	enemy.cancel()
	session.enemies.erase(enemy)
	await settle(1)

func orbit_camera_checks() -> void:
	var old_camera := player.movement_camera
	var old_rules := player.ricochet_rules
	player.ricochet_rules = old_rules.duplicate()
	player.ricochet_rules.crowd_deflection_enabled = true
	player.ricochet_rules.eccentric_enabled = true
	player.ricochet_rules.minimum_launch_speed = 8.0
	player.ricochet_rules.maximum_launch_speed = 8.0
	player.ricochet_rules.flight_deceleration = 0.1
	var group: Array[SlimeEnemy] = []
	for x in [1.2, 1.8]:
		for z in [-0.35, 0.35]: group.append(spawn("wave_slime", Vector3(x, 0, z), 1000.0))
	var camera := FollowCamera.new()
	camera.target = player
	camera.distance = 25.0
	camera.pitch_degrees = 30.627
	camera.fov = 28.0
	camera.horizontal_rotation_enabled = false
	camera.ricochet_camera_settings = load("res://data/combat/scenes/world/player/ricochet_camera.tres").duplicate()
	world.add_child(camera)
	camera.make_current()
	camera.set_process(false)
	player.movement_camera = camera
	camera._bind_ricochet_camera()
	var body := player.body_ricochet
	body.cancel(true)
	var floor_body := StaticBody3D.new()
	var floor_collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(20, 0.2, 20)
	floor_collision.shape = floor_shape
	floor_body.add_child(floor_collision)
	world.add_child(floor_body)
	floor_body.position.y = -0.1
	player.global_position = Vector3(0, 0.03, 0)
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)
	await settle(8)
	player.set_physics_process(false)
	check(body.begin_charge(Vector3.RIGHT) and body.release_charge(), "持续环绕实机逻辑夹具可以发射")
	var orbit_seen := false
	var weight_seen := false
	var safe := true
	for frame in 100:
		body.advance(1.0 / 60.0, Vector3.ZERO, false)
		player.sword._physics_process(1.0 / 60.0)
		player.reset_physics_interpolation()
		camera._process(1.0 / 60.0)
		orbit_seen = orbit_seen or body.orbiting
		weight_seen = weight_seen or camera._ricochet_camera._combat_focus.orbit_weight > 0.6
		safe = safe and (camera._ricochet_camera.framing + camera._ricochet_camera.shake).length() <= camera.ricochet_camera_settings.max_offset_ratio + 0.00001
	check(orbit_seen and weight_seen, "真实接群和连续续段持续驱动环绕取景")
	check(camera._ricochet_camera._combat_focus.beat_count >= 2, "同次飞行后续多刀真实命中继续产生合并反馈")
	check(safe and camera.distance == 25.0 and camera.fov == 28.0 and Engine.time_scale == 1.0, "新反馈不改基础镜头或时间，重音遵守共用偏移上限")
	var presentation := ChargePresentation.new()
	presentation.player = player
	presentation.orbit_slow_enabled = true
	world.add_child(presentation)
	await settle(1)
	presentation.set_process(false)
	var hits := [0]
	var count_hit := func(_enemy, _damage, flying):
		if flying: hits[0] += 1
	player.sword.hit_landed.connect(count_hit)
	var steady_scale := true
	for frame in 80:
		var step := Engine.time_scale / 60.0
		body.advance(step, Vector3.ZERO, false)
		player.sword._physics_process(step)
		presentation.advance(step, 1.0 / 60.0)
		presentation.set_process(false)
		if frame > 10: steady_scale = steady_scale and is_equal_approx(Engine.time_scale, presentation.orbit_slow_scale)
	check(hits[0] >= 2 and steady_scale, "真实环绕多次剑伤与续段保持同一慢动作，无逐次停顿")
	check(not presentation.enabled and camera.charge_unscaled_time, "环绕慢动作独立于蓄力聚焦开关，镜头使用真实时间")
	camera.horizontal_rotation_enabled = true
	var rotate := InputEventKey.new()
	rotate.keycode = KEY_E
	rotate.physical_keycode = KEY_E
	rotate.pressed = true
	Input.parse_input_event(rotate)
	Input.flush_buffered_events()
	camera._process(Engine.time_scale * 0.02)
	rotate = rotate.duplicate()
	rotate.pressed = false
	Input.parse_input_event(rotate)
	Input.flush_buffered_events()
	check(is_equal_approx(absf(camera._yaw_velocity), camera.yaw_acceleration_degrees * 0.02), "慢动作中 Q/E 仍按真实时间响应")
	camera.horizontal_rotation_enabled = false
	var pose := camera.global_transform
	session.set_combat_frozen(true)
	check(Engine.time_scale == 1.0 and not camera.charge_unscaled_time, "升级冻结同帧恢复时间，不等待渲染更新")
	camera._process(0.2)
	check(camera.global_transform == pose, "升级冻结保持整段环绕取景和冲击进度")
	session.set_combat_frozen(false)
	presentation.advance(0.12, 0.12)
	check(is_equal_approx(Engine.time_scale, presentation.orbit_slow_scale), "解除冻结后仅真实环绕重新渐入")
	check(body.detach_from_crowd() and body.flying and not body.orbiting, "右键沿切线脱离保留真实飞行")
	presentation.advance(0.03 * Engine.time_scale, 0.03)
	check(Engine.time_scale > 0.82 and Engine.time_scale < 1.0, "脱离途中时间平滑恢复")
	presentation.advance(0.03 * Engine.time_scale, 0.03)
	check(Engine.time_scale == 1.0 and not camera.charge_unscaled_time, "脱离后六十毫秒恢复原速和镜头时间")
	start_slow_orbit(presentation)
	body.advance(Engine.time_scale / 60.0, Vector3.RIGHT, false, 1)
	check(not body.flying and Engine.time_scale == 1.0 and not camera.charge_unscaled_time and body._cooldown > 0.0, "新移动接管同帧恢复原速，保留真实剩余冷却")
	start_slow_orbit(presentation)
	session._set_phase(WavePrototype.Phase.REST)
	await settle(1)
	presentation.set_process(false)
	check(Engine.time_scale == 1.0 and not camera.charge_unscaled_time and not body.flying, "清波休整释放慢动作与旧环绕")
	session._set_phase(WavePrototype.Phase.BATTLE)
	await settle(1)
	start_slow_orbit(presentation)
	presentation.free()
	check(Engine.time_scale == 1.0 and not camera.charge_unscaled_time, "场景退出释放正在使用的慢动作与镜头请求")
	player.sword.hit_landed.disconnect(count_hit)
	body.cancel(true)
	for frame in 60: camera._process(1.0 / 60.0)
	check(not camera._ricochet_camera.active and camera._ricochet_camera._combat_focus.pulse == 0.0, "主动取消后清理环绕重音并恢复普通跟随")
	player.sword.cancel()
	player.global_position = Vector3(0, 0.03, 0)
	player.ricochet_rules = old_rules
	player.movement_camera = old_camera
	old_camera.make_current()
	camera.queue_free()
	floor_body.queue_free()
	for enemy in group:
		enemy.cancel()
		session.enemies.erase(enemy)
	clear_effects()
	await settle(1)

func start_slow_orbit(presentation: ChargePresentation) -> void:
	var body := player.body_ricochet
	body.cancel(true)
	player.global_position = Vector3(0, 0.03, 0)
	check(body.begin_charge(Vector3.RIGHT) and body.release_charge(), "慢动作生命周期使用真实重新发射")
	for frame in 40:
		var step := Engine.time_scale / 60.0
		body.advance(step, Vector3.ZERO, false, 0)
		presentation.advance(step, 1.0 / 60.0)
	presentation.set_process(false)
	check(body.orbiting and is_equal_approx(Engine.time_scale, presentation.orbit_slow_scale), "真实环绕重新取得当前时间基准")

func presentation_cleanup_checks() -> void:
	clear_effects()
	check(pool().has_method("retire_presentations"), "清波允许纯视觉快照短暂收尾")
	if not pool().has_method("retire_presentations"): return
	var effect := kill(spawn(), &"basic_sword")
	var feedback := pool()
	var pool_ref: WeakRef = weakref(feedback)
	var old_root := session._attack_root
	var seed := EnemySeedProjectile.new()
	feedback.add_child(seed)
	seed.active = true
	seed.set_process(true)
	var old_endless := session._run_endless
	session._run_endless = true
	session._clear_wave()
	check(session.phase == WavePrototype.Phase.REST, "正常清波立即进入安全休整，不等待尸体播完")
	check(session._attack_root == null and feedback.get_parent() == old_root and effect.is_processing(), "清波立即撤销攻击根资格，死亡帧留在原父节点自然播放")
	check(not seed.active and not seed.is_processing(), "视觉收尾不保留吐籽伤害或其它危险物")
	session.set_combat_frozen(true)
	var age := effect._age
	await create_timer(0.03).timeout
	check(effect._age == age, "独立收尾仍服从升级冻结")
	session.set_combat_frozen(false)
	for child in feedback.get_children():
		if child.is_processing() and (child is EnemyDeathEffect or child.get_script() == load("res://scripts/enemies/enemy_melee_contact.gd")): child._process(10.0)
	await settle(1)
	check(pool_ref.get_ref() == null, "最后一个视觉结束后整个退役池自行释放")
	session.phase = WavePrototype.Phase.BATTLE
	session._run_endless = old_endless
	session._attack_root = Node3D.new()
	session.add_child(session._attack_root)
	effect = kill(spawn(), &"basic_sword")
	feedback = pool()
	pool_ref = weakref(feedback)
	session.call("_cleanup_attacks", true)
	session._cleanup_attacks()
	await settle(1)
	check(pool_ref.get_ref() == null, "退出或重试立即清理尚未播完的视觉池")
	session._attack_root = Node3D.new()
	session.add_child(session._attack_root)
	player.action_visuals.combat_readability_enabled = false
	kill(spawn(), &"basic_sword")
	pool_ref = weakref(pool())
	session.call("_cleanup_attacks", true)
	await settle(1)
	check(pool_ref.get_ref() == null, "未开启新层次的地图保留原有清波清理行为")
	player.action_visuals.combat_readability_enabled = true
	session._attack_root = Node3D.new()
	session.add_child(session._attack_root)

func extra_feedback_checks() -> void:
	check(player.action_visuals.melee_death_distance >= 3.0, "正式地图扩大四散距离")
	var effect := kill(spawn(), &"basic_sword")
	if not effect: return
	effect.set_process(false)
	var ghosts: Variant = effect.get("_ghosts")
	var accents: Variant = effect.get("_accents")
	check(ghosts != null and ghosts.size() == 2 and accents != null, "飞行复用两层原帧残影与批量碎屑／烟尘")
	if ghosts == null or accents == null:
		clear_effects()
		await settle(1)
		return
	effect._process(0.16)
	check(ghosts[0].visible and ghosts[1].visible and accents.sparks.visible, "起飞后出现短残影与旋转碎屑")
	check(not accents.dust.visible, "空中阶段不提前生成落地烟尘")
	check(is_equal_approx(ghosts[0].global_basis.x.length(), effect._size.x), "残影保持怪物原生像素尺寸")
	var ghost_material := ghosts[0].material_override as ShaderMaterial
	check(ghost_material.get_shader_parameter("effect_texture") == effect._materials[0].get_shader_parameter("effect_texture") and ghosts[0].get_instance_shader_parameter("frame_rect") == effect._pieces[0].get_instance_shader_parameter("frame_rect"), "残影使用同一死亡原帧与翻转")
	check(ghost_material.next_pass != null and not accents.is_processing(), "残影补画保留遮挡，附属粒子由死亡时钟推进")
	var land := float(effect.get("_pause_seconds")) + float(effect.get("_air_seconds"))
	effect._process(land - effect._age)
	var first_contact := effect._pieces[0].global_position
	check(accents.dust.visible, "首次落地扬起克制烟尘")
	effect._process(0.045)
	check(effect._pieces[0].global_position.y > first_contact.y + 0.05 and Vector2(effect._offset.x, effect._offset.z).length() > effect._travel.length(), "落地后小弹跳并沿原方向滑出")
	effect._process(0.16)
	check(is_equal_approx(effect._pieces[0].global_position.y, first_contact.y), "小弹跳快速结束，不再次长时间漂浮")
	effect._process(10.0)
	check(not ghosts[0].visible and not ghosts[1].visible and not accents.visible, "回池时残影、碎屑与烟尘全部隐藏")
	var reused := kill(spawn(), &"basic_sword")
	check(reused == effect and reused.get("_ghosts")[0] == ghosts[0] and reused.get("_accents") == accents, "再次击杀复用附属网格与粒子节点")
	clear_effects()
	await settle(1)

func speed_and_distance_checks() -> void:
	clear_effects()
	var sample := spawn("wave_slime", Vector3(1, 0, 0), 100.0)
	var effect := pool().death(sample.sprite, false, player.action_visuals)
	var previous := Vector4.ZERO
	for speed in [0.0, 4.0, 12.0]:
		effect.get("_random").seed = 87
		effect.begin(sample.sprite, false, player.movement_camera, player.action_visuals, {"source": &"basic_sword", "motion_velocity": Vector3.RIGHT * speed})
		effect.set_process(false)
		var values := Vector4(effect._travel.length(), effect._height, absf(effect._spin), effect.get("_slide_distance"))
		if speed > 0.0:
			check(values.x > previous.x and values.y > previous.y and values.z > previous.z and values.w > previous.w, "真实速度升高时，距离、腾空、翻转和落地滑行一起增强")
		previous = values
	effect.get("_random").seed = 87
	effect.begin(sample.sprite, false, player.movement_camera, player.action_visuals, {"source": &"flight_sword", "motion_velocity": Vector3.RIGHT * 1000.0})
	check(effect._travel.length() <= previous.x + 0.001, "极高速度的死亡抛射仍有上限")
	var first_strength := player.action_visuals.melee_death_strength({"source": &"ricochet_storm", "motion_velocity": Vector3.RIGHT * 1000.0, "storm_layer": 0})
	var next_strength := player.action_visuals.melee_death_strength({"source": &"ricochet_storm", "motion_velocity": Vector3.RIGHT * 1000.0, "storm_layer": 1})
	check(next_strength < first_strength and next_strength > 0.0, "奔雷先封顶力度再逐层减弱，极高速度也不会把外层全部拉满")
	check(is_equal_approx(player.action_visuals.melee_death_strength({"motion_velocity": Vector3.UP * 1000.0}), player.action_visuals.melee_death_min_strength), "垂直跳跃和坠落不伪造水平冲击速度")
	effect._process(10.0)
	sample.cancel()
	session.enemies.erase(sample)
	clear_effects()
	await settle(1)
	var distant := spawn("wave_slime", Vector3(5, 0, 0))
	distant.take_damage(999.0, {"source": &"flight_sword", "motion_velocity": Vector3.RIGHT * 16.0})
	check(distant.dead and active_effects().is_empty(), "离人物较远的普通剑术击杀简化死亡，不因高速额外击飞")
	var near := spawn()
	near.take_damage(999.0, {"source": &"flight_sword", "motion_velocity": Vector3.RIGHT * 12.0, "contact_distance": 5.0})
	check(near.dead and active_effects().is_empty(), "延后结算遵守真实接触距离，不被人物后来走近改变")
	clear_effects()
	var remembered := spawn("wave_slime", Vector3(5, 0, 0))
	remembered.take_damage(999.0, {"source": &"flight_sword", "motion_velocity": Vector3.RIGHT * 12.0, "contact_distance": 1.0})
	check(remembered.dead and active_effects().size() == 1 and active_effects()[0]._knockout, "近身接触后人物离开，仍沿用命中当时的距离与速度")
	clear_effects()
	await settle(1)

func storm_mass_checks() -> void:
	var storm: RicochetStorm = load("res://scenes/combat/ricochet_storm.tscn").instantiate()
	storm.session = session
	storm.audio_enabled = false
	world.add_child(storm)
	storm.apply_skill_level(3)
	await settle(1)
	storm.set_physics_process(false)
	var groups: Array = []
	for x in [1.0, 2.2, 3.4]:
		var group: Array[SlimeEnemy] = []
		for z in [-0.3, 0.0, 0.3]: group.append(spawn("wave_slime", Vector3(x, 0, z)))
		groups.append(group)
	player.velocity = Vector3.RIGHT * 12.0
	var before := session.kills
	check(storm.discharge(player.global_position), "三层怪群可开始成片雷伤")
	storm.set_physics_process(false)
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(-6, 0.03, 0)
	var previous_strength := INF
	for layer in 3:
		if layer > 0: storm._physics_process(storm.layer_interval + 0.001)
		storm.set_physics_process(false)
		check(groups[layer].all(func(enemy): return enemy.dead), "雷潮第 %d 片的三只怪物同层死亡" % layer)
		var strength := 0.0
		for enemy: SlimeEnemy in groups[layer]:
			var hit := enemy.fatal_hit_context
			check(hit.get("motion_velocity", Vector3.ZERO) == Vector3.RIGHT * 12.0 and hit.get("storm_layer", -1) == layer, "同片死亡使用同一触发速度及层号")
			strength = player.action_visuals.melee_death_strength(hit)
		check(strength > 0.0 and strength < previous_strength, "雷潮击飞力度逐层减弱，同时保留整片爆发")
		previous_strength = strength
	check(session.kills == before + 9, "成片死亡表现不新增或漏算真实击杀")
	check(active_effects().filter(func(item): return item._knockout).size() == 9, "远离人物的后续雷潮也保留九只完整死亡击飞")
	clear_effects()
	storm.cancel_current()
	storm.queue_free()
	player.global_position = Vector3(0, 0.03, 0)
	await settle(1)

func storm_route_speed_checks() -> void:
	var storm: RicochetStorm = load("res://scenes/combat/ricochet_storm.tscn").instantiate()
	storm.session = session
	storm.audio_enabled = false
	world.add_child(storm)
	storm.apply_skill_level(1)
	await settle(1)
	storm.set_physics_process(false)
	var enemy := spawn("wave_slime", Vector3(2.0, 0, 0))
	storm._flight_stats = storm.get_attack_stats()
	storm._segments.append({"start": Vector3(0, 0.03, 0), "end": Vector3(4.5, 0.03, 0), "heading": Vector3.RIGHT, "seconds": 0.5, "speed": 10.0, "deceleration": 4.0})
	storm._frame_flight_seconds = 0.5
	player.velocity = Vector3.LEFT * 2.0
	storm._physics_process(0.5)
	storm.set_physics_process(false)
	var motion: Vector3 = enemy.fatal_hit_context.get("motion_velocity", Vector3.ZERO)
	check(enemy.dead and motion.x > 9.6 and motion.x < 9.8 and absf(motion.z) < 0.001, "真实连续路段在触发时保存减速后的瞬时速度，不取路段均速或人物后来速度")
	player.velocity = Vector3.ZERO
	clear_effects()
	storm.cancel_current()
	storm.queue_free()
	await settle(1)

func cluster_checks() -> void:
	clear_effects()
	var feedback := pool()
	check(feedback.has_method("_register_burst"), "反馈池支持附近密集击杀合并爆点")
	if not feedback.has_method("_register_burst"): return
	for index in 2: kill(spawn("wave_slime", Vector3(index * 0.2, 0, 0)), &"basic_sword")
	check(active_effects().filter(func(item): return item.get("_burst_only") == true).is_empty(), "零星两次击杀不触发集中爆点")
	var deaths := session.kills
	kill(spawn("wave_slime", Vector3(0.3, 0, 0.2)), &"ricochet_storm")
	var bursts := active_effects().filter(func(item): return item.get("_burst_only") == true)
	check(bursts.size() == 1 and session.kills == deaths + 1, "附近三次击杀只添加一次视觉爆点，不添加击杀或伤害")
	if not bursts.is_empty():
		var burst: EnemyDeathEffect = bursts[0]
		check(not burst._pieces[0].visible and burst._pieces[1].visible, "集中爆点不复制尸体")
	for index in 5: kill(spawn(), &"basic_sword")
	check(active_effects().filter(func(item): return item.get("_burst_only") == true).size() == 1, "密集连续击杀服从集中爆点间隔")
	var remaining: float = feedback.get("_burst_cooldown")
	session.set_combat_frozen(true)
	await create_timer(0.03).timeout
	check(is_equal_approx(float(feedback.get("_burst_cooldown")), remaining), "集中爆点的合并计时服从战斗冻结")
	session.set_combat_frozen(false)
	clear_effects()
	await settle(1)
	for index in 3: kill(spawn("wave_slime", Vector3(index * 4.0, 0, 0)), &"basic_sword")
	check(active_effects().filter(func(item): return item.get("_burst_only") == true).is_empty(), "相距很远的击杀不合成跨场爆点")
	clear_effects()
	await settle(1)
	for index in 3:
		kill(spawn(), &"basic_sword")
		feedback._process(0.13)
	check(active_effects().filter(func(item): return item.get("_burst_only") == true).is_empty(), "分散在合并窗口之外的击杀不触发集中爆点")
	clear_effects()
	player.action_visuals.melee_death_cluster_enabled = false
	for index in 3: kill(spawn(), &"basic_sword")
	check(active_effects().filter(func(item): return item.get("_burst_only") == true).is_empty(), "集中爆点可由当前地图独立关闭")
	player.action_visuals.melee_death_cluster_enabled = true
	clear_effects()
	await settle(1)

func run() -> void:
	var visuals: PlayerActionVisuals = load("res://data/combat/scenes/world/player/action_visuals.tres")
	check(visuals.get("melee_death_enabled") == true, "World 独立开启近身击杀击飞")
	check(load("res://data/combat/scenes/city/player/action_visuals.tres").get("melee_death_enabled") == false, "City 默认保留当前死亡表现")
	if failures:
		print("Melee death feedback: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	check(visuals.melee_death_height >= 1.5 and visuals.melee_death_seconds >= 0.8 and visuals.melee_death_spin_degrees >= 180.0, "World 提高腾空、翻转与清晰停留时间，突出怪堆中的击杀")
	var scene := Player.new()
	scene.action_visuals = visuals
	var entries: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(scene)
	for property in ["melee_death_enabled", "melee_death_seconds", "melee_death_distance", "melee_death_height", "melee_death_spin_degrees", "melee_death_hit_pause", "melee_death_air_seconds", "melee_death_impact_frames", "melee_death_impact_seconds", "melee_death_trail_enabled", "melee_death_landing_enabled", "melee_death_bounce_height", "melee_death_slide_distance", "melee_death_cluster_enabled", "melee_death_near_distance", "melee_death_reference_speed", "melee_death_min_strength", "melee_death_storm_retention"]:
		check(entries.any(func(item): return item.property == property and item.common and item.label != property), "参数总览提供常用中文入口：" + property)
	scene.free()
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	terrain = Terrain.new()
	var data := TerrainData.new()
	data.size = Vector2i.ZERO
	data.resize(Vector2i(-8, -8), Vector2i(16, 16))
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
	player.animations = load("res://assets/meowa/player/animations.tres")
	player.action_visuals = visuals.duplicate()
	player.action_visuals.show_aim_guide = false
	player.ricochet_rules = PlayerRicochetRules.new()
	player.ricochet_rules.enemy_push_enabled = false
	player.sword_rules = PlayerSwordRules.new()
	player.sword_rules.audio_enabled = false
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	var collision := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.24
	shape.height = 1.06592
	collision.name = "Collision"
	collision.shape = shape
	collision.position.y = shape.height * 0.5
	player.add_child(collision)
	var camera := Camera3D.new()
	world.add_child(camera)
	player.movement_camera = camera
	session.player = player
	world.add_child(player)
	player.set_physics_process(false)
	player.sword.set_physics_process(false)
	await settle()
	session._path.build(terrain, 0.32, [player.get_rid()])
	await source_checks()
	await motion_checks()
	await random_spread_checks()
	await wall_checks()
	await sword_checks()
	await storm_checks()
	await toy_impact_checks()
	await extra_feedback_checks()
	await speed_and_distance_checks()
	await storm_mass_checks()
	await storm_route_speed_checks()
	await cluster_checks()
	await readability_checks()
	await orbit_camera_checks()
	await presentation_cleanup_checks()
	await lifecycle_checks()
	world.queue_free()
	await settle()
	print("Melee death feedback: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
