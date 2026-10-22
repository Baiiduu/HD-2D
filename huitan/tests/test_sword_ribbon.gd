extends "res://tests/test_sword_stretch.gd"

func run() -> void:
	var rules: PlayerSwordRules = load("res://data/combat/scenes/world/player/basic_sword.tres")
	check(rules.effect_mode == 3 and rules.get("ribbon_visual") != null, "World 选择独立原生剑光并绑定样式资源")
	if failures:
		print("Native sword ribbon: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	await super.run()

func input_and_art_checks() -> void:
	await super.input_and_art_checks()
	await reset()
	var original := sword.rules
	var native := load("res://data/combat/scenes/world/player/basic_sword.tres").duplicate() as PlayerSwordRules
	native.ribbon_visual = native.ribbon_visual.duplicate()
	native.ribbon_visual.ribbon_layered_enabled = false
	native.frames = null
	native.audio_enabled = false
	check(native.validation_error().is_empty(), "独立剑光不依赖旧图集")
	var old_width := native.arc_width
	native.arc_width = NAN
	check(native.validation_error().is_empty(), "原生剑光不受未使用的旧窄弧宽度影响")
	native.arc_width = old_width
	var comparison: Array = []
	for mode in [PlayerSwordRules.SlashVisual.MEOWA_ARC, PlayerSwordRules.SlashVisual.NATIVE_RIBBON]:
		await reset()
		sword.rules = native.duplicate()
		sword.rules.effect_mode = mode
		sword.rules.frames = original.frames
		var target := enemy(Vector3(1, 0, 0))
		check(sword.request_manual(Vector3.RIGHT), "新旧剑光共用真实出手入口")
		sword._physics_process(sword.rules.windup_for(false) + sword.rules.sweep_seconds * 0.5)
		comparison.append([target.health, damage_events.size(), sword._age, sword._since_strike])
	check(comparison[0] == comparison[1], "切换原生剑光不改变扣血、同刀去重和真实攻击时钟")
	await reset()
	sword.rules = native
	check(sword.request_manual(Vector3.RIGHT), "无图集原生剑光真实出手")
	sword._physics_process(native.windup_for(false) + native.sweep_seconds * 0.5)
	var effect := sword._effect
	var material := effect._material
	var mesh := effect.mesh
	check(effect.visible and material.shader.resource_path.ends_with("player_sword_ribbon.gdshader"), "正式攻击使用独立原生材质")
	check(material.get_shader_parameter("slash_texture") == null, "原生材质不采样旧月牙图片")
	var phase: float = material.get_shader_parameter("leading_angle")
	session.set_combat_frozen(true)
	sword._physics_process(0.6)
	check(is_equal_approx(material.get_shader_parameter("leading_angle"), phase), "升级冻结同时停止原生笔触")
	session.set_combat_frozen(false)
	var style := native.ribbon_visual
	var started_width := sword._settings.ribbon_visual.ribbon_width
	style.ribbon_width *= 1.5
	sword._physics_process(0.06)
	check(is_equal_approx(sword._settings.ribbon_visual.ribbon_width, started_width), "已挥出的一刀保留独立外观快照")
	var tails := active_tails()
	check(tails.size() == 1 and not effect.visible, "收尾交接给池化世界余迹，原笔触停止跟人")
	if not tails.is_empty():
		var tail: Dictionary = tails[0]
		var origin: Vector3 = tail.origin
		var age: float = tail.age
		player.global_position += Vector3.RIGHT
		sword._physics_process(0.01)
		check(tail.effect.global_position == origin, "人物离开后余迹固定在挥砍位置")
		session.set_combat_frozen(true)
		sword._physics_process(0.5)
		check(tail.age < age + 0.011, "升级冻结也停止已释放余迹的消散")
		session.set_combat_frozen(false)
		sword._physics_process(tail.settings.tail_seconds())
		check(active_tails().is_empty(), "独立视觉到期归还余迹池")
	await reset()
	style.ribbon_width = started_width
	for reverse in [false, true]:
		effect.display(Vector3.ZERO, Vector3.RIGHT, native.normal_range, native.normal_angle, reverse,
			null, 0.065, native, session._path, sword._surface, [player.get_rid()])
		var vertices: PackedVector3Array = effect.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var inside := true
		for point in vertices: inside = inside and point.is_finite() and Vector2(point.x, point.z).length() <= native.normal_range + 0.000001
		check(inside, "正反原生笔触不越过真实半径")
		for property in ["band_width", "blade_color", "middle_color", "tail_color", "release", "blade_presence", "trail_angle", "plane_slope"]:
			check(effect._material.get_shader_parameter(property) == effect._material.next_pass.get_shader_parameter(property), "怪物轮廓补画同步原生笔触：" + property)
	effect.display(Vector3.ZERO, Vector3.RIGHT, native.normal_range, native.normal_angle, false,
		null, 0.065, native, session._path, sword._surface, [player.get_rid()])
	check(effect._material == material and effect.mesh == mesh, "新旧模式切换后继续复用原生材质与平地网格")
	var wall := box(Vector3(0.8, 0.6, 0), Vector3(0.02, 1.2, 5))
	await settle()
	effect.display(Vector3.ZERO, Vector3.RIGHT, native.normal_range, native.normal_angle, false,
		null, 0.065, native, session._path, sword._surface, [player.get_rid()])
	var clipped: PackedVector3Array = effect.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var inside_wall := true
	for point in clipped: inside_wall = inside_wall and (effect.global_transform * point).x <= 0.8001
	check(inside_wall, "原生剑光保留真实薄墙裁切")
	wall.queue_free()
	await settle()
	var bad := style.duplicate() as SwordRibbonVisual
	bad.ribbon_tail_seconds = NAN
	check(not bad.validation_error().is_empty(), "独立消散配置拒绝非有限时长")
	var catalog := preload("res://addons/parameter_hub/catalog.gd").new()
	var exported_rules := player.sword_rules
	player.sword_rules = native
	var entries: Array[Dictionary] = catalog.collect(player)
	player.sword_rules = exported_rules
	for property in ["ribbon_width", "ribbon_tail_seconds", "ribbon_blade_color", "ribbon_blade_enabled", "ribbon_trail_enabled"]:
		check(entries.any(func(entry): return entry.object == style and entry.property == property and entry.common and entry.category == "人物" and entry.label != property), "独立外观参数有中文常用入口：" + property)
	var preview: Node3D = load("res://scenes/previews/sword_slash_workshop.tscn").instantiate()
	world.add_child(preview)
	var component: MeshInstance3D = preview.get_node("SwordSlash")
	check(component.visual == load("res://data/combat/scenes/world/player/basic_sword.tres").ribbon_visual, "工作台与正式 World 使用同一外观资源")
	check(is_equal_approx(preview.get_node("Camera3D").fov, 28.0) and is_equal_approx(preview.get_node("Camera3D").position.distance_to(Vector3.UP * 0.75), 30.0), "工作台采用正式镜头标尺")
	component.get_node("AnimationPlayer").pause()
	component.preview_age = 0.065
	check(component.visible and component.mesh != null, "独立组件可直接按时间定位预览")
	component.preview_age = component.preview_sweep_seconds + component.visual.ribbon_tail_seconds
	check(not component.visible, "预览结束隐藏组件")
	preview.queue_free()
	sword.rules = original
	await reset()
