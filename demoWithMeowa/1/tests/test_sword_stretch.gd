extends "res://tests/test_sword_residue.gd"

func run() -> void:
	var rules: PlayerSwordRules = load("res://data/combat/scenes/world/player/basic_sword.tres")
	check(rules.get("meowa_stretch_enabled") == true, "World 独立启用剑光拉伸")
	check(rules.get("meowa_visibility_strength") != null and float(rules.get("meowa_visibility_strength")) > 0.0, "World 独立增强剑光可见度")
	if failures:
		print("Sword stretch: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	check(load("res://data/combat/scenes/city/player/basic_sword.tres").get("meowa_stretch_enabled") == false, "City 保留原剑光形态")
	await super.run()

func present(rules: PlayerSwordRules, age: float, reverse := false) -> void:
	sword._effect.display(Vector3.ZERO, Vector3.RIGHT, rules.normal_range, rules.normal_angle, reverse,
		rules.frames, age, rules, session._path, sword._surface, [player.get_rid()])

func input_and_art_checks() -> void:
	await super.input_and_art_checks()
	await reset()
	var original := sword.rules
	var rules := load("res://data/combat/scenes/world/player/basic_sword.tres").duplicate() as PlayerSwordRules
	rules.effect_mode = PlayerSwordRules.SlashVisual.MEOWA_ARC
	rules.audio_enabled = false
	sword.rules = rules
	present(rules, rules.sweep_seconds * 0.1)
	var material := sword._effect._material
	var mesh := sword._effect.mesh
	var short_angle: float = material.get_shader_parameter("trail_angle")
	check(short_angle < deg_to_rad(rules.arc_trail_degrees) * 0.6, "起刀时拖尾明显收短")
	present(rules, rules.sweep_seconds * 0.75)
	var long_angle: float = material.get_shader_parameter("trail_angle")
	var clear_width: float = material.get_shader_parameter("band_width")
	check(float(material.get_shader_parameter("visibility_strength")) > 0.0, "清晰度增强传入原生剑光材质")
	var visible_profile: Vector3 = rules.call("meowa_stretch_profile", 1.0, 0.28)
	check(visible_profile.z > 0.0, "收尾前段保留一小段可辨认的主刃")
	rules.set("meowa_visibility_strength", 0.0)
	present(rules, rules.sweep_seconds * 0.75)
	check(is_equal_approx(material.get_shader_parameter("band_width"), rules.arc_width) and float(material.get_shader_parameter("visibility_strength")) == 0.0, "清晰度归零完整恢复原宽度和原材质强度")
	check(clear_width > float(material.get_shader_parameter("band_width")), "增强只适量加宽笔触，不扩大攻击半径")
	rules.set("meowa_visibility_strength", 1.0)
	present(rules, rules.sweep_seconds * 0.75)
	check(long_angle > deg_to_rad(rules.arc_trail_degrees) * 1.4, "挥扫中拖尾沿弧线明显拉长")
	check(sword._effect.mesh == mesh and sword._effect._material == material, "拉伸只更新实例材质参数，不重建平地网格或材质")
	var atlas := (rules.frames.get_frame_texture(&"slash", 0) as AtlasTexture).atlas
	check(material.get_shader_parameter("slash_texture") == atlas, "拉伸继续直接采样原图集")
	var leading: float = material.get_shader_parameter("leading_angle")
	var rectangle: Vector4 = material.get_shader_parameter("frame_rect")
	var opacity: float = material.get_shader_parameter("body_opacity")
	rules.set("meowa_stretch_enabled", false)
	present(rules, rules.sweep_seconds * 0.75)
	check(material.get_shader_parameter("leading_angle") == leading and material.get_shader_parameter("frame_rect") == rectangle, "开关拉伸不改变真实刀锋方向或原帧顺序")
	check(is_equal_approx(material.get_shader_parameter("trail_angle"), deg_to_rad(rules.arc_trail_degrees)) and is_equal_approx(material.get_shader_parameter("tail_width_scale"), 1.0), "关闭开关完整恢复原角度和厚度")
	rules.set("meowa_stretch_enabled", true)
	rules.set("meowa_stretch_strength", 0.0)
	present(rules, rules.sweep_seconds * 0.75)
	check(is_equal_approx(material.get_shader_parameter("trail_angle"), deg_to_rad(rules.arc_trail_degrees)), "拉伸强度为零恢复原表现")
	rules.set("meowa_stretch_strength", 1.0)
	present(rules, rules.sweep_seconds - 0.000001)
	var before: Vector3 = Vector3(material.get_shader_parameter("trail_angle"), material.get_shader_parameter("tail_width_scale"), material.get_shader_parameter("body_opacity"))
	present(rules, rules.sweep_seconds)
	var after: Vector3 = Vector3(material.get_shader_parameter("trail_angle"), material.get_shader_parameter("tail_width_scale"), material.get_shader_parameter("body_opacity"))
	check(before.distance_to(after) < 0.0001, "扫刃到世界余迹交接时拉伸连续")
	present(rules, rules.sweep_seconds + rules.meowa_tail_seconds * 0.6)
	check(float(material.get_shader_parameter("body_opacity")) < opacity * 0.05, "收尾白刃先收住")
	check(float(material.get_shader_parameter("tail_width_scale")) < after.y and float(material.get_shader_parameter("tail_width_scale")) > 0.0, "有色尾迹逐渐收细并继续播放")
	for property in ["trail_angle", "tail_width_scale", "body_opacity", "visibility_strength", "band_width"]:
		check(material.next_pass.get_shader_parameter(property) == material.get_shader_parameter(property), "怪物轮廓补画同步拉伸：" + property)
	for reverse in [false, true]:
		present(rules, rules.sweep_seconds * 0.75, reverse)
		var vertices: PackedVector3Array = sword._effect.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var inside := true
		for point in vertices:
			inside = inside and Vector2(point.x, point.z).length() <= rules.normal_range + 0.000001
		check(inside and is_equal_approx(material.get_shader_parameter("attack_radius"), rules.normal_range), "正反挥扫的拉伸始终留在真实攻击范围内")
	var fast := rules.duplicate() as PlayerSwordRules
	fast.sweep_seconds *= 0.4
	present(fast, fast.sweep_seconds * 0.75)
	check(is_equal_approx(material.get_shader_parameter("trail_angle"), long_angle), "攻速改变后同一挥扫比例保持相同拉伸形态")
	present(fast, fast.sweep_seconds + fast.meowa_tail_seconds * 0.6)
	var fast_width: float = material.get_shader_parameter("tail_width_scale")
	present(rules, rules.sweep_seconds + rules.meowa_tail_seconds * 0.6)
	check(is_equal_approx(material.get_shader_parameter("tail_width_scale"), fast_width), "攻速不压缩余迹收细的独立消散时长")
	var wall := box(Vector3(0.8, 0.6, 0), Vector3(0.02, 1.2, 5))
	await settle()
	present(rules, rules.sweep_seconds * 0.75)
	var clipped := true
	var wall_vertices: PackedVector3Array = sword._effect.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for point in wall_vertices:
		clipped = clipped and (sword._effect.global_transform * point).x <= 0.8001
	check(clipped and sword._effect.mesh != mesh, "拉伸开启后仍按真实薄墙裁切")
	wall.queue_free()
	await settle()
	present(rules, rules.sweep_seconds * 0.75)
	check(sword._effect.mesh == mesh, "墙体移除后复用原有网格")
	await damage_and_freeze_checks(rules)
	var catalog := preload("res://addons/parameter_hub/catalog.gd").new()
	var entries: Array[Dictionary] = catalog.collect(player)
	for property in ["meowa_stretch_enabled", "meowa_stretch_strength", "meowa_visibility_strength"]:
		check(entries.any(func(entry): return entry.object == player.sword_rules and entry.property == property and entry.common and entry.label != property), "参数总览提供中文拉伸入口：" + property)
	sword.rules = original
	await reset()

func damage_and_freeze_checks(rules: PlayerSwordRules) -> void:
	for flying in [false, true]:
		var results: Array = []
		for enabled in [false, true]:
			await reset()
			sword.rules = rules.duplicate()
			sword.rules.set("meowa_stretch_enabled", enabled)
			var mob := enemy(Vector3(1, 0, 0), 1000.0)
			if flying: await flight()
			else: check(sword.request_manual(Vector3.RIGHT), "剑光对照使用真实普攻")
			for index in 36: sword._physics_process(0.01)
			results.append([mob.health, damage_events.size(), strikes.size(), sword._age, sword._since_strike])
		check(results[0] == results[1], "拉伸开关不改变%s的伤害、刀数与攻击时钟" % ("飞行挥剑" if flying else "普攻"))
	await reset()
	sword.rules = rules
	check(sword.request_manual(Vector3.RIGHT), "真实挥剑冻结检查")
	sword._physics_process(rules.windup_for(false) + rules.sweep_seconds * 0.3)
	var material := sword._effect._material
	var angle: float = material.get_shader_parameter("trail_angle")
	session.set_combat_frozen(true)
	sword._physics_process(0.5)
	check(material.get_shader_parameter("trail_angle") == angle, "升级冻结同时暂停剑光形变")
	session.set_combat_frozen(false)
	sword._physics_process(0.08)
	var tails := active_tails()
	check(tails.size() == 1, "拉伸剑光仍交接到独立世界余迹")
	if not tails.is_empty():
		var tail: Dictionary = tails[0]
		var origin: Vector3 = tail.origin
		var tail_angle: float = tail.effect._material.get_shader_parameter("trail_angle")
		rules.set("meowa_stretch_enabled", false)
		player.global_position += Vector3.RIGHT
		sword._physics_process(0.02)
		check(tail.effect.global_position == origin and tail.settings.get("meowa_stretch_enabled") == true, "人物离开或修改开关不改写已释放余迹的落点与快照")
		check(float(tail.effect._material.get_shader_parameter("trail_angle")) <= tail_angle, "余迹沿本次收势继续变化")
		rules.set("meowa_stretch_enabled", true)
	sword.cancel()
	check(active_tails().is_empty() and not sword._effect.visible, "取消清理拉伸与全部余迹")
