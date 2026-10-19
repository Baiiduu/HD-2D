extends "res://tests/test_sword_ribbon.gd"

func run() -> void:
	var rules: PlayerSwordRules = load("res://data/combat/scenes/world/player/basic_sword.tres")
	check(rules.ribbon_visual.get("ribbon_layered_enabled") == true and rules.ribbon_visual.get("ribbon_brush") != null, "World 选择分层流动剑光并绑定真实笔触贴图")
	if failures:
		print("Layered sword flow: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	await super.run()

func input_and_art_checks() -> void:
	await super.input_and_art_checks()
	await reset()
	var original := sword.rules
	var rules := load("res://data/combat/scenes/world/player/basic_sword.tres").duplicate() as PlayerSwordRules
	rules.ribbon_visual = rules.ribbon_visual.duplicate()
	rules.frames = null
	rules.audio_enabled = false
	var results: Array = []
	for enabled in [false, true]:
		await reset()
		rules.ribbon_visual.ribbon_layered_enabled = enabled
		sword.rules = rules
		var mob := enemy(Vector3.RIGHT)
		check(sword.request_manual(Vector3.RIGHT), "新旧笔触真实出手")
		sword._physics_process(0.26)
		results.append([mob.health, damage_events.size(), strikes.size(), sword._age, sword._since_strike])
	check(results[0] == results[1], "分层笔触不改变真实伤害、刀数与动作时钟")
	await reset()
	rules.ribbon_visual.ribbon_layered_enabled = true
	sword.rules = rules
	check(sword.request_manual(Vector3.RIGHT), "分层笔触在无动画图集时正常出手")
	sword._physics_process(0.10)
	var effect := sword._effect
	var material := effect._material
	var mesh := effect.mesh
	check(effect.visible and material.shader.resource_path.ends_with("player_sword_flow_slash.gdshader"), "真实普攻使用独立流动材质")
	check(material.get_shader_parameter("stroke_texture") == rules.ribbon_visual.ribbon_brush and material.get_shader_parameter("flow_noise") == rules.ribbon_visual.ribbon_noise, "直接绑定原生 Meowa 笔触和共用噪声贴图")
	var clock: float = material.get_shader_parameter("visual_age")
	var speed: float = material.get_shader_parameter("flow_speed")
	session.set_combat_frozen(true)
	sword._physics_process(1.0)
	check(is_equal_approx(material.get_shader_parameter("visual_age"), clock), "冻结同时停止流动与解析亮点")
	session.set_combat_frozen(false)
	rules.ribbon_visual.ribbon_flow_speed = speed + 1.0
	sword._physics_process(0.02)
	check(is_equal_approx(material.get_shader_parameter("flow_speed"), speed) and float(material.get_shader_parameter("visual_age")) > clock, "噪声流速保留出刀快照且按战斗时间恢复")
	sword._physics_process(0.04)
	var tails := active_tails()
	check(tails.size() == 1, "流动笔触交接到独立世界余迹")
	if not tails.is_empty():
		var tail: Dictionary = tails[0]
		var after: ShaderMaterial = tail.effect._material
		check(is_equal_approx(after.get_shader_parameter("visual_age"), rules.sweep_seconds + tail.age), "余迹交接沿原噪声时钟继续，不从头闪现")
		var spot: Vector3 = tail.effect.global_position
		var frozen_clock: float = after.get_shader_parameter("visual_age")
		player.global_position += Vector3.RIGHT
		session.set_combat_frozen(true)
		sword._physics_process(0.4)
		check(tail.effect.global_position == spot and is_equal_approx(after.get_shader_parameter("visual_age"), frozen_clock), "世界余迹冻结位置、笔触流动和亮点")
		session.set_combat_frozen(false)
		sword._physics_process(0.01)
		check(tail.effect.global_position == spot, "人物离开时流动余迹留在真实挥砍位置")
	await reset()
	for reverse in [false, true]:
		effect.display(Vector3.ZERO, Vector3.RIGHT, rules.normal_range, rules.normal_angle, reverse,
			null, 0.065, rules, session._path, sword._surface, [player.get_rid()])
		for property in ["stroke_texture", "flow_noise", "visual_age", "attack_angle", "flow_speed", "distortion", "wake_strength", "spark_strength", "plane_slope"]:
			check(material.get_shader_parameter(property) == material.next_pass.get_shader_parameter(property), "怪物轮廓补画同步分层参数：" + property)
		var vertices: PackedVector3Array = effect.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var inside := true
		for vertex in vertices: inside = inside and Vector2(vertex.x, vertex.z).length() <= rules.normal_range + 0.00001
		check(inside, "宽笔触与飞散亮点仍在真实投影边界内")
	var wall := box(Vector3(0.8, 0.6, 0), Vector3(0.02, 1.2, 5))
	await settle()
	effect.display(Vector3.ZERO, Vector3.RIGHT, rules.normal_range, rules.normal_angle, false,
		null, 0.065, rules, session._path, sword._surface, [player.get_rid()])
	var blocked := true
	for point in effect.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]: blocked = blocked and (effect.global_transform * point).x <= 0.8001
	check(blocked and effect.mesh != mesh, "流动材质保留真实薄墙裁切")
	wall.queue_free()
	await settle()
	for enabled in [false, true, false, true]:
		rules.ribbon_visual.ribbon_layered_enabled = enabled
		effect.display(Vector3.ZERO, Vector3.RIGHT, rules.normal_range, rules.normal_angle, false,
			null, 0.065, rules, session._path, sword._surface, [player.get_rid()])
		if enabled: check(effect._material == material and effect.mesh == mesh, "反复切换对照复用流动材质与原有网格")
	rules.ribbon_visual.ribbon_layered_enabled = true
	var exported := player.sword_rules
	player.sword_rules = rules
	var entries: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(player)
	player.sword_rules = exported
	for property in ["ribbon_layered_enabled", "ribbon_brush", "ribbon_flow_speed", "ribbon_distortion", "ribbon_wake_strength", "ribbon_spark_strength", "ribbon_view_tilt"]:
		check(entries.any(func(entry): return entry.object == rules.ribbon_visual and entry.property == property and entry.common and entry.label != property), "参数总览提供分层笔触中文入口：" + property)
	var invalid := rules.ribbon_visual.duplicate() as SwordRibbonVisual
	invalid.ribbon_flow_speed = INF
	check(not invalid.validation_error().is_empty(), "分层参数拒绝无限流速")
	check(not load("res://data/visual/sword_ribbon_world.tres").ribbon_layered_enabled, "原型外观与用户调节值保留独立对照")
	sword.rules = original
	await reset()
