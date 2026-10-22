extends "res://tests/test_melee_death_feedback.gd"

func envelope_checks() -> void:
	var script := load("res://scripts/enemies/enemy_hit_reaction.gd") as GDScript
	var coarse = script.new()
	var fine = script.new()
	coarse.strike(Vector3.RIGHT, 12.0, 0.26)
	fine.strike(Vector3.RIGHT, 12.0, 0.26)
	coarse.advance(0.06)
	for index in 6: fine.advance(0.01)
	check(coarse.lean.is_equal_approx(fine.lean), "同一受击姿态不随渲染帧率改变")
	var axis := Vector3.UP.cross(Vector3.RIGHT)
	check(coarse.lean.dot(axis) > 0.0, "受击初段顺来向倾斜")
	coarse.advance(0.065)
	check(coarse.lean.dot(axis) < 0.0, "回正途中有一次轻微反向回弹")
	var bounded := true
	for index in 100:
		fine.strike(Vector3.RIGHT if index % 2 == 0 else Vector3.FORWARD, 12.0, 0.26)
		fine.advance(0.003)
		bounded = bounded and fine.lean.length() <= deg_to_rad(12.0) + 0.000001
	check(bounded, "密集连续命中的身体偏转始终封顶")
	fine.advance(0.3)
	check(not fine.active and fine.lean == Vector3.ZERO, "密集连击结束后完整回正")
	for heading in [Vector3.ZERO, Vector3.UP, Vector3(NAN, 0.0, 1.0)]:
		fine.strike(heading, 12.0, 0.26)
		check(not fine.active, "无效水平来向不启动身体反应")
	fine.strike(Vector3.RIGHT, 0.0, 0.26)
	check(not fine.active, "倾斜幅度为零时不启动反应")
	seed(616)
	var expected := randi()
	seed(616)
	fine.strike(Vector3.RIGHT, 12.0, 0.26)
	fine.advance(0.04)
	check(randi() == expected, "受击反应不消耗战斗与成长的随机流")

func setup() -> void:
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
	player.action_visuals = load("res://data/combat/scenes/world/player/action_visuals.tres").duplicate()
	player.action_visuals.show_aim_guide = false
	player.ricochet_rules = PlayerRicochetRules.new()
	player.ricochet_rules.enemy_push_enabled = false
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = CapsuleShape3D.new()
	player.add_child(collision)
	var camera := Camera3D.new()
	world.add_child(camera)
	player.movement_camera = camera
	session.player = player
	world.add_child(player)
	player.set_physics_process(false)
	await settle()
	session._path.build(terrain, 0.32, [player.get_rid()])

func reaction_checks() -> void:
	for id in ["wave_slime", "leaf_charger", "lantern_spitter", "pot_brood", "bell_frog", "mini_slime"]:
		var enemy := spawn(id, Vector3(2, 0, 0), 100.0)
		var position := enemy.global_transform
		var collision: Transform3D = enemy.get_node("Collision").transform
		var visual := enemy.sprite.transform
		var texture := enemy.sprite.texture
		var clock := enemy._elapsed
		var velocity := Vector3(0.3, 0.0, 0.1)
		enemy.velocity = velocity
		enemy.take_damage(1.0, {"source": &"flight_sword", "direction": Vector3.RIGHT})
		check(enemy.get("_hit_reaction") != null, id + " 的真实非致死命中启动身体反应")
		enemy.call("_advance_hit_reaction", 0.035)
		var lean: Vector3 = enemy.sprite.get_meta("motion_lean", Vector3.ZERO)
		check(lean.dot(Vector3.UP.cross(Vector3.RIGHT)) > deg_to_rad(5.0), id + " 顺真实来袭方向明显倾斜")
		check(enemy.global_transform == position and enemy.get_node("Collision").transform == collision and enemy.velocity == velocity, id + " 不改变根节点、碰撞体或真实速度")
		check(enemy.sprite.transform == visual and enemy.sprite.texture == texture and enemy._elapsed == clock, id + " 保留原生尺寸、选帧与动画时钟")
		check(enemy.stun_remaining == 0.0 and not enemy.is_orbiting(), id + " 不新增硬直、外力或环绕")
		check(enemy._hit_flash > 0.0 and enemy.health == 99.0, id + " 保留实际扣血与原有闪白")
		check(enemy.sprite.get_instance_shader_parameter("motion_lean") == lean, id + " 用实例参数驱动受光与技能轮廓")
		enemy._process(0.005)
		check(enemy.sprite.get_meta("motion_lean") != lean, id + " 正常显示回调实际推进受击姿态")
		var outline := enemy.sprite.get_node_or_null("OcclusionOutline") as MeshInstance3D
		lean = enemy.sprite.get_meta("motion_lean")
		check(outline != null and outline.get_instance_shader_parameter("motion_lean") == lean, id + " 遮挡轮廓同步身体姿态")
		var proxy := MeshInstance3D.new()
		enemy.sprite.apply_motion_to(proxy)
		check(proxy.get_instance_shader_parameter("motion_lean") == lean, id + " 倒影可复用同一姿态")
		proxy.free()
		var before := lean
		player.movement_camera.rotation.y += 0.7
		enemy.call("_advance_hit_reaction", 0.0)
		check(enemy.sprite.get_meta("motion_lean") == before, id + " Q/E 不改变已记录的世界受击方向")
		enemy.take_damage(1.0, {"source": &"basic_sword", "direction": Vector3.FORWARD})
		check(enemy.sprite.get_meta("motion_lean") == before, id + " 连续受击不瞬间重置当前身体姿态")
		enemy.call("_advance_hit_reaction", 0.035)
		check(enemy.sprite.get_meta("motion_lean").length() <= deg_to_rad(player.action_visuals.get("enemy_hit_lean_degrees")) + 0.000001, id + " 连击倾斜有上限")
		enemy.call("_advance_hit_reaction", 1.0)
		check(enemy.sprite.get_meta("motion_lean") == Vector3.ZERO and not enemy.get("_hit_reaction").active, id + " 回正后停止姿态更新")
		enemy.cancel()
		session.enemies.erase(enemy)
	await settle(1)

func lifecycle_checks() -> void:
	var enemy := spawn("wave_slime", Vector3(2, 0, 0), 100.0)
	enemy.take_damage(1.0, {"source": &"basic_sword", "direction": Vector3.ZERO})
	enemy.call("_advance_hit_reaction", 0.035)
	check(enemy.sprite.get_meta("motion_lean").z < 0.0, "无方向的旧攻击回退人物至目标的水平来向")
	var lean: Vector3 = enemy.sprite.get_meta("motion_lean")
	session.register_combat_node(enemy)
	session.set_combat_frozen(true)
	enemy.call("_advance_hit_reaction", 0.1)
	check(enemy.sprite.get_meta("motion_lean") == lean, "升级冻结保持身体姿态")
	session.set_combat_frozen(false)
	enemy.call("_advance_hit_reaction", 0.02)
	check(enemy.sprite.get_meta("motion_lean") != lean, "恢复战斗后继续原反应")
	player.action_visuals.set("enemy_hit_reaction_enabled", false)
	enemy.call("_advance_hit_reaction", 0.0)
	check(enemy.sprite.get_meta("motion_lean") == Vector3.ZERO, "运行时关闭开关立即回正")
	enemy.take_damage(1.0, {"direction": Vector3.RIGHT})
	check(not enemy.get("_hit_reaction").active, "关闭时真实扣血不启动反应")
	player.action_visuals.set("enemy_hit_reaction_enabled", true)
	enemy.health_loss_disabled = true
	enemy.take_damage(1000.0, {"source": &"flight_sword", "direction": Vector3.FORWARD})
	enemy.call("_advance_hit_reaction", 0.035)
	check(enemy.health == 98.0 and not enemy.dead and not enemy.sprite.get_meta("motion_lean").is_zero_approx(), "免死模拟保留真实命中身体反应")
	enemy.cancel()
	check(enemy.sprite.get_meta("motion_lean") == Vector3.ZERO, "取消与重试立即清除姿态")
	session.enemies.erase(enemy)
	await settle(1)
	var lethal := spawn("wave_slime", Vector3(2, 0, 0), 2.0)
	lethal.take_damage(1.0, {"source": &"basic_sword", "direction": Vector3.RIGHT})
	lethal.call("_advance_hit_reaction", 0.035)
	lethal.take_damage(1.0, {"source": &"basic_sword", "direction": Vector3.RIGHT})
	check(lethal.dead and lethal.sprite.get_meta("motion_lean") == Vector3.ZERO, "致死时撤下存活反应并正常交给原有死亡演出")
	check(not active_effects().is_empty(), "原有击杀反馈继续产生")
	clear_effects()
	await settle(1)

func sharing_checks() -> void:
	var first := spawn("wave_slime", Vector3(2, 0, 0), 100.0)
	var second := spawn("wave_slime", Vector3(3, 0, 0), 100.0)
	first.take_damage(1.0, {"direction": Vector3.RIGHT})
	second.take_damage(1.0, {"direction": Vector3.FORWARD})
	first.call("_advance_hit_reaction", 0.035)
	second.call("_advance_hit_reaction", 0.035)
	first.sprite._process(0.0)
	second.sprite._process(0.0)
	check(first.sprite.material_override == second.sprite.material_override, "不同受击方向仍复用同帧受光材质")
	check(first.sprite.get_meta("motion_lean") != second.sprite.get_meta("motion_lean"), "共享材质的两个怪物保留独立姿态")
	check(second.sprite.get_meta("motion_lean") == second.sprite.get_instance_shader_parameter("motion_lean"), "其他怪物的倾斜不会串改实例参数")
	first.sprite.lighting_enabled = false
	first.sprite.apply_lighting()
	first.sprite._process(0.0)
	check(first.sprite.material_override == first.sprite.get("_material"), "关闭自定义受光时仍使用身体反应的几何姿态")
	first.call("_advance_hit_reaction", 1.0)
	check(first.sprite.material_override == first.sprite.get("_original_material"), "回正后恢复原生无受光材质")
	for enemy in [first, second]:
		enemy.cancel()
		session.enemies.erase(enemy)
	await settle(1)

func run() -> void:
	var visuals: PlayerActionVisuals = load("res://data/combat/scenes/world/player/action_visuals.tres")
	check(visuals.get("enemy_hit_reaction_enabled") == true, "World 独立开启怪物受击身体反应")
	if failures:
		print("Enemy hit reaction: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	check(load("res://data/combat/scenes/city/player/action_visuals.tres").get("enemy_hit_reaction_enabled") == false, "City 保持原配置")
	var scene := Player.new()
	scene.action_visuals = visuals
	var entries: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(scene)
	for property in ["enemy_hit_reaction_enabled", "enemy_hit_lean_degrees", "enemy_hit_recovery_seconds"]:
		check(entries.any(func(item): return item.property == property and item.common and item.label != property), "参数总览提供中文常用入口：" + property)
	scene.free()
	envelope_checks()
	await setup()
	await reaction_checks()
	await sharing_checks()
	await lifecycle_checks()
	world.queue_free()
	await settle()
	print("Enemy hit reaction: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
