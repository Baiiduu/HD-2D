extends "res://tests/test_sword_thin_arc.gd"

func input_and_art_checks() -> void:
	await super.input_and_art_checks()
	await reset()
	var original := sword.rules
	var meowa := load("res://data/player/basic_sword.tres").duplicate() as PlayerSwordRules
	meowa.audio_enabled = false
	sword.rules = meowa
	check(meowa.effect_mode == PlayerSwordRules.SlashVisual.MEOWA_ARC and meowa.frames != null, "正式剑术绑定已有 Meowa 图集并默认选择动画短弧")
	check(meowa.get_property_list().any(func(info): return info.name == "effect_mode" and "Meowa 动画短弧:2" in str(info.hint_string)), "Godot 显示方式下拉菜单使用明确中文名称")
	var mob := enemy(Vector3(1, 0, 0))
	check(sword.request_manual(Vector3.RIGHT), "Meowa 动画短弧沿用人物真实普攻输入")
	sword._physics_process(0.10)
	var effect := sword._effect
	check(effect.visible and effect._material.shader.resource_path.ends_with("player_sword_meowa_arc.gdshader"), "真实挥剑选择采样 Meowa 图集的独立材质")
	check(mob.health == 190.0 and damage_events.size() == 1, "绑定美术帧不改变伤害、命中时刻或同刀去重")
	var rectangle: Vector4 = effect._material.get_shader_parameter("frame_rect")
	session.set_combat_frozen(true)
	sword._physics_process(0.5)
	check(effect._material.get_shader_parameter("frame_rect") == rectangle, "升级冻结保持当前美术帧")
	session.set_combat_frozen(false)
	sword._physics_process(0.15)
	check(not effect.visible and mob.health == 190.0, "动画收尾结束隐藏短弧，不产生额外伤害")
	var native := meowa.frames.get_frame_texture(&"slash", 0) as AtlasTexture
	var material: ShaderMaterial
	var cached_mesh: ArrayMesh
	for index in 8:
		var frame_age := (index + 0.5) * meowa.sweep_seconds / 4.0 if index < 4 else meowa.sweep_seconds + (index - 4 + 0.5) * meowa.meowa_tail_seconds / 4.0
		effect.display(Vector3.ZERO, Vector3.RIGHT, meowa.normal_range, meowa.normal_angle, false, meowa.frames, frame_age, meowa, session._path, sword._surface, [player.get_rid()])
		if index == 0:
			material = effect._material
			cached_mesh = effect.mesh
		rectangle = effect._material.get_shader_parameter("frame_rect")
		check(is_equal_approx(rectangle.x, (index % 4) * 0.25) and is_equal_approx(rectangle.y, (index / 4) * 0.5), "原始八帧按顺序进入短弧材质：%d" % index)
		check(effect._material.get_shader_parameter("slash_texture") == native.atlas, "直接采样原图集，不生成替代贴图：%d" % index)
		check(effect._material == material and effect.mesh == cached_mesh and material.next_pass.get_shader_parameter("frame_rect") == rectangle, "逐帧复用材质和网格，怪物轮廓补画同步当前帧：%d" % index)
	check(material.get_shader_parameter("fade") == null, "Meowa 原生消散不再次乘程序收尾淡出")
	var program := meowa.duplicate() as PlayerSwordRules
	program.effect_mode = PlayerSwordRules.SlashVisual.THIN_ARC
	effect.display(Vector3.ZERO, Vector3.RIGHT, meowa.normal_range, meowa.normal_angle, false, null, 0.05, program, session._path, sword._surface, [player.get_rid()])
	check(effect._material != material and effect.mesh == cached_mesh, "对照模式仅切换材质，保留相同短弧投影与真实范围")
	effect.display(Vector3.ZERO, Vector3.RIGHT, meowa.normal_range, meowa.normal_angle, false, meowa.frames, 0.05, meowa, session._path, sword._surface, [player.get_rid()])
	check(effect._material == material and effect.mesh == cached_mesh, "切回 Meowa 继续复用原材质及平地网格")
	effect.display(Vector3.ZERO, Vector3.RIGHT, meowa.normal_range, meowa.normal_angle, false, null, 0.05, meowa, session._path, sword._surface, [player.get_rid()])
	check(not effect.visible, "Meowa 素材槽为空时安全隐藏，不访问空图集")
	var wall := box(Vector3(0.8, 0.6, 0), Vector3(0.02, 1.2, 5))
	await settle()
	effect.display(Vector3.ZERO, Vector3.RIGHT, meowa.normal_range, meowa.normal_angle, false, meowa.frames, 0.05, meowa, session._path, sword._surface, [player.get_rid()])
	var clipped := true
	var touches := false
	var vertices: PackedVector3Array = effect.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for point in vertices:
		var position := effect.global_transform * point
		if position.x > 0.8001: clipped = false
		if position.x > 0.7: touches = true
	check(clipped and touches and effect.mesh != cached_mesh, "Meowa 采样保留实时薄墙裁切")
	wall.queue_free()
	await settle()
	effect.display(Vector3.ZERO, Vector3.RIGHT, meowa.normal_range, meowa.normal_angle, false, meowa.frames, 0.05, meowa, session._path, sword._surface, [player.get_rid()])
	check(effect.mesh == cached_mesh, "移走建筑后恢复同一平地网格")
	sword.cancel()
	check(not effect.visible, "取消攻击清理 Meowa 刀痕")
	sword.rules = original
	await reset()
