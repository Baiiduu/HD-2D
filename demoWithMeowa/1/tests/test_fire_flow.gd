extends "res://tests/test_player_fire_trail.gd"

func spark_samples(sparks: Node3D) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for index in sparks.count:
		var slot: int = (sparks._head + index) % sparks._births.size()
		var point: Vector3 = sparks._transforms[slot].origin
		result.append(Vector3(point.x, point.z, sparks._births[slot]))
	return result

func path_checks() -> void:
	await super.path_checks()
	await reset()
	var settings := player.action_visuals
	var formal: PlayerActionVisuals = load("res://data/combat/scenes/world/player/action_visuals.tres")
	check(formal.get("fire_trail_flow_enabled") == true, "World 启用贴地火焰笔触与小火星")
	check(settings.get("fire_trail_flow_enabled") == false, "共享默认不自动改变其它地图")
	check(formal.get("fire_trail_brush") != null, "正式火焰笔触绑定独立 Meowa 素材")
	if failures: return
	settings.show_fire_trail = true
	settings.fire_trail_flow_enabled = true
	settings.fire_trail_brush = formal.fire_trail_brush
	var effect := player.fire_trail
	effect.clear()
	seed(93)
	var expected := randf()
	seed(93)
	for index in 10:
		effect._travelled(Vector3(index * 0.1, 0, 0), Vector3((index + 1) * 0.1, 0, 0), Vector3.RIGHT, 0.01)
		effect._process(0.01)
	var sparks: Node3D = effect._sparks
	check(sparks != null and sparks.count > 0, "真实经过路段产生小火星")
	check(randf() == expected, "火焰变化不消耗出怪和成长的随机流")
	var split_count: int = sparks.count
	var split_points := spark_samples(sparks)
	var node: MultiMeshInstance3D = sparks.batch
	var material: ShaderMaterial = sparks.material
	check(node.multimesh.mesh is QuadMesh, "离地层只有火星小卡片，不包含立起的火舌曲面")
	check(effect.get_child_count() == 2 and sparks.get_child_count() == 1, "全部离地火星共用一个额外批量绘制节点")
	check(effect._material.get_shader_parameter("fire_brush") == formal.fire_trail_brush, "正式地火材质直接读取 Meowa 笔触")
	check(material.get_shader_parameter("fire_brush") == formal.fire_trail_brush and is_equal_approx(material.get_shader_parameter("flow_speed"), settings.fire_trail_flow_speed), "火星与地火读取同一笔触和节奏，只从火纹爆发或破碎处甩出")
	check(material.get_shader_parameter("body_mask_margin_pixels") == settings.fire_trail_body_clearance_pixels, "人物轮廓使用独立可调的原生像素间隙")
	check(is_equal_approx(effect._material.get_shader_parameter("flow_strength"), settings.fire_trail_flow_strength), "分叉火纹读取正式独立参数")
	effect.clear()
	effect._travelled(Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT, 0.10)
	var combined := spark_samples(sparks)
	var same: bool = sparks.count == split_count
	if same:
		for index in combined.size(): same = same and combined[index].is_equal_approx(split_points[index])
	check(same, "同一路线分帧或合并不会改变火星数量、落点和出生时刻")
	var points := spark_samples(sparks)
	player.global_position += Vector3(3, 0, 2)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(5, 5, 5)
	camera.look_at(Vector3.ZERO)
	camera.rotate_y(PI * 0.5)
	effect._process(0.10)
	check(spark_samples(sparks) == points, "Q/E 和人物走位不移动已留下的火星")
	var clock := effect._clock
	session.set_combat_frozen(true)
	effect._process(0.5)
	check(effect._clock == clock and is_equal_approx(material.get_shader_parameter("effect_clock"), clock), "冻结同步停止地火笔触与飞火")
	session.set_combat_frozen(false)
	body.cancel()
	effect._process(0.10)
	check(sparks.count == split_count, "取消弹射后已有火星自然收尾")
	effect._process(3.0)
	check(sparks.count == 0 and not sparks.visible and not effect.is_processing(), "小火星和余烬到期后不留空闲工作")
	effect._travelled(Vector3.ZERO, Vector3.RIGHT * 0.5, Vector3.RIGHT, 0.05)
	effect._travelled(Vector3(10, 0, 0), Vector3(10.5, 0, 0), Vector3.RIGHT, 0.05)
	check(spark_samples(sparks).all(func(sample): return sample.x <= 0.5 or sample.x >= 10.0), "瞬移或不连续路段之间不补造火星")
	settings.fire_trail_flow_enabled = false
	effect._process(0.0)
	check(sparks.count == 0 and not sparks.visible and effect._count > 0, "关闭笔触保留原贴地火带")
	settings.fire_trail_flow_enabled = true
	effect._travelled(Vector3.ZERO, Vector3.RIGHT, Vector3.RIGHT, 0.1)
	check(sparks.batch == node and sparks.material == material, "反复开关和重新弹射复用网格、材质与实例池")
	effect.clear()
	check(sparks.count == 0 and not sparks.visible, "重试和清波清理全部立体残留")
	settings.fire_trail_spark_spacing = 0.15
	effect._travelled(Vector3.ZERO, Vector3.RIGHT * 10.0, Vector3.RIGHT, 0.25)
	check(sparks.count > 64 and node.multimesh.instance_count >= sparks.count, "长路段按真实距离补齐火星，容量增长不丢失活跃实例")
	var oldest := spark_samples(sparks)[0]
	check(is_equal_approx(oldest.x, settings.fire_trail_spark_spacing * 0.5), "容量增长保留最早真实落点")
	effect._process(0.30)
	effect._travelled(Vector3.RIGHT * 10.0, Vector3.RIGHT * 11.0, Vector3.RIGHT, 0.10)
	effect._process(0.39)
	check(sparks.count > 0 and spark_samples(sparks).all(func(sample): return sample.x >= 10.0), "旧火星独立过期，新路段保留自己的生命周期")
	var entries: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(player)
	for property in ["fire_trail_flow_enabled", "fire_trail_brush", "fire_trail_brush_region", "fire_trail_flow_speed", "fire_trail_spark_height", "fire_trail_spark_spacing", "fire_trail_flow_strength", "fire_trail_spark_amount", "fire_trail_body_clearance_pixels"]:
		check(entries.any(func(entry): return entry.object == settings and entry.property == property and entry.common and entry.category == "人物" and entry.label != property), "贴地笔触有中文常用调节入口：" + property)
	settings.fire_trail_spark_amount = 0.0
	effect._process(0.0)
	check(sparks.count == 0 and not sparks.visible and effect._count > 0, "飞火密度设为零只停火星，贴地燃烧继续")
	settings.fire_trail_brush = null
	effect._process(0.0)
	check(is_zero_approx(effect._material.get_shader_parameter("flow_strength")) and effect._count > 0, "清空笔触素材安全回退基础火带，不留下空材质错误")
	effect.clear()
	camera.queue_free()
	settings.show_fire_trail = false
