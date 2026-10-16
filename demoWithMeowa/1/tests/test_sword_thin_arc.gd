extends "res://tests/test_player_sword.gd"

func input_and_art_checks() -> void:
	await super.input_and_art_checks()
	await reset()
	var original := sword.rules
	var thin := load("res://data/player/basic_sword.tres").duplicate() as PlayerSwordRules
	var selected_mode := thin.effect_mode
	thin.effect_mode = PlayerSwordRules.SlashVisual.THIN_ARC
	thin.frames = null
	thin.audio_enabled = false
	sword.rules = thin
	check(thin.effect_mode == PlayerSwordRules.SlashVisual.THIN_ARC and thin.frames == null, "程序短弧无需绑定旧圆环图集即可显示")
	var mob := enemy(Vector3(1, 0, 0))
	check(sword.request_manual(Vector3.RIGHT), "窄弧使用真实普攻输入")
	sword._physics_process(0.10)
	var effect := sword._effect
	check(effect.visible and effect._material.shader.resource_path.ends_with("player_sword_arc.gdshader"), "真实攻击路径选择窄弧材质")
	check(mob.health == 190.0 and damage_events.size() == 1, "显示窄弧保留原伤害、真实扫击及同刀去重")
	check(is_zero_approx(float(effect._material.get_shader_parameter("leading_angle"))), "刀尖方向与扫击正中时刻一致")
	var frozen_angle: float = effect._material.get_shader_parameter("leading_angle")
	session.set_combat_frozen(true)
	sword._physics_process(0.5)
	check(effect.visible and is_equal_approx(frozen_angle, effect._material.get_shader_parameter("leading_angle")), "升级冻结保持可见刀痕与扫击进度")
	session.set_combat_frozen(false)
	sword._physics_process(0.15)
	check(not effect.visible and mob.health == 190.0, "完整动作结束隐藏刀痕，不追加伤害")
	sword.cancel()
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.current = true
	var clear_mesh: ArrayMesh
	for index in 8:
		camera.rotation.y = index * TAU / 8.0
		effect.display(Vector3.ZERO, Vector3.RIGHT, thin.normal_range, 120.0, false, null, 0.05, thin, session._path, sword._surface, [player.get_rid()])
		if index == 0: clear_mesh = effect.mesh
		var slope: Vector2 = effect._material.get_shader_parameter("plane_slope")
		var toward := effect.global_basis.inverse() * camera.global_basis.z
		check(slope.dot(Vector2(toward.x, toward.z)) < 0.0 and effect.mesh == clear_mesh, "Q/E 方位 %d 保留世界方向、朝镜头轻斜与平地网格缓存" % index)
		check(thin.effect_height - slope.length() * thin.normal_range >= 0.07999, "Q/E 方位 %d 的刀痕不沉地" % index)
	var forward_uv: PackedVector2Array = effect.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	effect.display(Vector3.ZERO, Vector3.RIGHT, thin.normal_range, 120.0, true, null, 0.05, thin, session._path, sword._surface, [player.get_rid()])
	var reverse_uv: PackedVector2Array = effect.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	check(is_equal_approx(forward_uv[4].x + reverse_uv[4].x, 1.0) and is_equal_approx(forward_uv[4].y, reverse_uv[4].y), "交替挥剑只反转扫动方向，不移动人物枢轴或攻击边界")
	effect.display(Vector3.ZERO, Vector3.RIGHT, thin.normal_range * 10.0, 120.0, false, null, 0.05, thin, session._path, sword._surface, [player.get_rid()])
	check(is_equal_approx(effect._material.get_shader_parameter("band_width"), thin.arc_width * 1.6), "大范围成长仅温和增厚刀痕并保留上限")
	check(is_equal_approx(effect._material.next_pass.get_shader_parameter("band_width"), effect._material.get_shader_parameter("band_width")), "怪物轮廓补画与主材质使用相同窄弧宽度")
	var wall := box(Vector3(0.8, 0.6, 0), Vector3(0.02, 1.2, 5))
	await settle()
	effect.display(Vector3.ZERO, Vector3.RIGHT, thin.normal_range, 120.0, false, null, 0.05, thin, session._path, sword._surface, [player.get_rid()])
	var clipped := true
	var touches := false
	var vertices: PackedVector3Array = effect.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for point in vertices:
		var position := effect.global_transform * point
		if position.x > 0.8001: clipped = false
		if position.x > 0.7: touches = true
	check(clipped and touches and effect.mesh != clear_mesh, "窄弧保留真实薄墙裁切")
	wall.queue_free()
	await settle()
	effect.display(Vector3.ZERO, Vector3.RIGHT, thin.normal_range, 120.0, false, null, 0.05, thin, session._path, sword._surface, [player.get_rid()])
	check(effect.mesh == clear_mesh, "移走建筑后恢复原平地网格")
	sword.cancel()
	check(not effect.visible, "取消攻击立即隐藏窄弧")
	check(load("res://data/player/basic_sword.tres").effect_mode == selected_mode, "旧帧动画与程序短弧验证不污染正式显示方式")
	var catalog := preload("res://addons/parameter_hub/catalog.gd").new()
	var entries: Array[Dictionary] = catalog.collect(player)
	for property in ["effect_mode", "arc_width", "arc_trail_degrees", "effect_height", "effect_tilt_degrees"]:
		check(entries.any(func(entry): return entry.object == player.sword_rules and entry.property == property and entry.common and entry.category == "人物" and entry.label != property), "参数总览以中文常用项暴露刀痕参数：" + property)
	camera.queue_free()
	sword.rules = original
	await reset()
