extends "res://tests/test_player_sword.gd"

func manual_checks() -> void:
	check("normal_slash_alignment_enabled" in sword.rules, "World 普攻需要独立的动作与刀光对齐配置")
	if not "normal_slash_alignment_enabled" in sword.rules: return
	sword.rules = load("res://data/combat/scenes/world/player/basic_sword.tres").duplicate()
	player.sword_rules = sword.rules
	sword.rules.audio_enabled = false
	player.action_visuals.normal_attack = load("res://data/combat/scenes/world/player/character_attack.tres")
	player.set_process(false)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(8, 8, 8)
	camera.look_at(Vector3.ZERO)
	camera.make_current()
	player.movement_camera = camera
	var heading := camera.global_basis.x
	heading.y = 0.0
	heading = heading.normalized()
	var clip := player.action_visuals.normal_attack
	check(sword.rules.get("normal_slash_alignment_enabled") and not PlayerSwordRules.new().get("normal_slash_alignment_enabled") and not load("res://data/combat/scenes/city/player/basic_sword.tres").get("normal_slash_alignment_enabled"), "World 单独启用，City 与共享默认保留原时序")
	await reset()
	sword._begin(heading, false)
	sword._physics_process(0.05)
	player.action_animator.render(0.2)
	check(player.sprite.texture == clip.get_frame_texture(&"default", 3) and is_equal_approx(player.action_animator._attack_age, sword._age), "前摇中播放起手帧，渲染时间不再另行推进剑术动作")
	check(not sword._effect.visible, "起手阶段仍不提前显示刀光")
	sword._physics_process(0.051)
	player.action_animator.render(0.0)
	check(player.sprite.texture == clip.get_frame_texture(&"default", 6) and sword._effect.visible, "真实扫刃开始时进入第七帧主斩击并显示刀光")
	sword._physics_process(0.049)
	player.action_animator.render(0.13)
	check(player.sprite.texture == clip.get_frame_texture(&"default", 7) and is_equal_approx(player.action_animator._attack_age, 0.15), "扫刃中段对应第八帧，重复渲染不漂移到收刀姿势")
	var style := sword._settings.ribbon_visual
	var effect := sword._effect
	var material := effect._material
	check(style.get("ribbon_hilt_enabled") and float(style.ribbon_width) < 0.64, "复用原笔触，World 收窄贴身光面并固定腰前内端")
	check(material.get_shader_parameter("hilt_enabled") == true and material.get_shader_parameter("hilt_offset") == style.get("ribbon_hilt_offset"), "现有流动着色器收到腰前起点，不平移真实攻击网格")
	check(material.get_shader_parameter("hilt_width_ratio") == style.get("ribbon_hilt_width_ratio"), "内端宽度独立收拢，不扩大刀尖边界")
	for property in ["hilt_enabled", "hilt_offset", "hilt_width_ratio", "blade_presence", "plane_slope"]:
		check(material.get_shader_parameter(property) == material.next_pass.get_shader_parameter(property), "怪物轮廓补画与主刀光一致：" + property)
	var vertices: PackedVector3Array = effect.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var inside := true
	for point in vertices: inside = inside and Vector2(point.x, point.z).length() <= sword.get_stats(false).range + 0.00001
	check(inside, "摆位与收窄保持原真实扇区的 XZ 边界")
	check(is_equal_approx(vertices[0].y, sword.rules.effect_height + float(style.get("ribbon_height_offset"))), "普攻光面下移到腰前，人物与真实判定原点保持")
	check(effect.global_position.is_equal_approx(session._path.ground_position(player.global_position)), "不通过平移整片扇区造成显示与命中错位")
	sword._physics_process(0.051)
	player.action_animator.render(0.0)
	check(player.sprite.texture == clip.get_frame_texture(&"default", 9) and not effect.visible, "扫刃结束时进入第十帧收剑，亮刃不继续跟人")
	var tails := sword._tail_pool.filter(func(item): return item.age >= 0.0)
	check(tails.size() == 1 and is_zero_approx(style.profile(1.0, 0.0).z), "收剑开始仅交接原有消散笔触，亮刃及时退出")
	if not tails.is_empty():
		var tail_material: ShaderMaterial = tails[0].effect._material
		check(is_zero_approx(float(tail_material.get_shader_parameter("blade_presence"))), "独立余迹交接首帧也不会重新闪出亮刃")
	check(is_equal_approx(sword._stats.damage, 10.0) and is_equal_approx(sword._stats.range, 1.52) and is_equal_approx(sword._stats.angle, 120.0) and is_equal_approx(sword._stats.interval, 0.55), "伤害、半径、扇角与出手间隔沿用正式数值")
	check(is_equal_approx(sword._settings.windup_seconds, 0.10) and is_equal_approx(sword._settings.sweep_seconds, 0.10), "动作配准不改写真实前摇和伤害窗口")
	await reset()
	for index in 2:
		sword._begin(heading, false)
		player.action_animator.render(0.0)
		check(not sword._reverse and not player.sprite.flip_h, "相同人物动作的连续普攻保持相同扫向，不机械交替")
	for yaw in [0.0, 0.8, 2.1]:
		camera.rotation.y = yaw
		for left in [false, true]:
			var aim := camera.global_basis.x * (-1.0 if left else 1.0)
			aim.y = 0.0
			sword._begin(aim, false)
			player.action_animator.render(0.0)
			check(sword._reverse == left and player.sprite.flip_h == left, "Q/E 镜头朝向下人物镜像和真实刀锋扫向共用本刀选择")
	for rank in 4: session.combat_modifiers.apply_buff(load("res://data/growth/cooldown.tres"))
	sword._begin(heading, false)
	sword._physics_process(sword._settings.windup_seconds + sword._settings.sweep_seconds * 0.5)
	player.action_animator.render(0.0)
	check(player.sprite.texture == clip.get_frame_texture(&"default", 7), "攻速成长后主斩击帧仍对应真实扫刃中段")
	var age := sword._age
	session.set_combat_frozen(true)
	sword._physics_process(0.4)
	player.action_animator.render(0.0)
	check(is_equal_approx(player.action_animator._attack_age, age), "升级冻结同时保持刀光与人物动作阶段")
	session.set_combat_frozen(false)
	sword.cancel()
	check(player.action_animator._attack.is_empty(), "取消不残留受剑术时钟驱动的普攻动画")
	session.combat_modifiers.reset()
	sword._begin(heading, true)
	check(sword._settings.ribbon_visual.resource_path.is_empty() and not sword._settings.ribbon_visual.get("ribbon_hilt_enabled"), "弹射继续使用独立环绕外观，默认不接腰前调整")
	check(is_equal_approx(sword._settings.effect_height, sword.rules.effect_height) and is_zero_approx(float(sword._settings.ribbon_visual.get("ribbon_height_offset"))), "弹射刀光保持原高度")
	check(is_equal_approx(sword._settings.windup_seconds, 0.05) and is_equal_approx(sword._stats.angle, 360.0), "弹射前摇和全向剑术配置不受普攻对齐影响")
	check(not player.action_animator.get("_attack_synced"), "弹射继续沿原人物动画时钟播放")
	sword.cancel()
	var entries: Array[Dictionary] = load("res://addons/parameter_hub/catalog.gd").new().collect(player)
	for property in ["normal_slash_alignment_enabled", "normal_attack_frame_breaks", "ribbon_hilt_enabled", "ribbon_hilt_offset", "ribbon_hilt_width_ratio", "ribbon_height_offset"]:
		check(entries.any(func(item): return item.property == property and item.common and item.category == "人物" and item.label != property), "参数总览提供中文对齐入口：" + property)

func attack_speed_checks() -> void: pass
func flight_checks() -> void: pass
func freeze_checks() -> void: pass
func input_and_art_checks() -> void: pass
func score_checks() -> void: pass
