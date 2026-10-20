extends "res://tests/test_ricochet_impact_feedback.gd"

func presentation_checks() -> void:
	await super.presentation_checks()
	if not "speed_flow_enabled" in player.action_visuals:
		check(false, "新版速度表现需使用纹理气流，不再给人物贴图描亮边")
		return
	var feedback: Variant = player.get("surface_feedback")
	await reset()
	feedback.clear()
	feedback.set_process(false)
	var formal: Resource = load("res://data/combat/scenes/world/player/action_visuals.tres")
	player.action_visuals.surface_wave_enabled = true
	player.action_visuals.set("surface_wave_texture", formal.get("surface_wave_texture"))
	player.action_visuals.set("speed_flow_enabled", true)
	player.action_visuals.set("speed_flow_texture", formal.get("speed_flow_texture"))
	player.action_visuals.speed_rim_enabled = false
	impacts.clear()
	check(body.begin_charge(Vector3.RIGHT) and body.release_charge(), "新表现经过真实发射和碰撞")
	feedback.set_process(false)
	for frame in 30:
		body.advance(1.0 / 120.0, Vector3.ZERO, false)
		feedback.advance(1.0 / 120.0)
		if not impacts.is_empty(): break
	var flow: GPUParticles3D = feedback.get("_flow")
	check(flow != null and flow.emitting and flow.amount_ratio > 0.0, "高速飞行发出贴身纹理气流")
	check(feedback.active_count() == 1, "真实反弹产生一片表面贴花")
	if flow == null or feedback.active_count() != 1 or impacts.is_empty(): return
	var process := flow.process_material as ParticleProcessMaterial
	check(not flow.local_coords and flow.transform_align == GPUParticles3D.TRANSFORM_ALIGN_Z_BILLBOARD_Y_TO_VELOCITY, "气流保留世界轨迹，并朝速度方向面向镜头")
	check(process.gravity.is_zero_approx() and process.color_ramp != null and process.scale_curve != null, "气流使用生命周期颜色和缩放曲线")
	check((flow.global_basis * process.direction).is_equal_approx(-body.direction), "气流沿真实出射方向向后流动")
	check(process.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_POINTS and process.emission_point_count == 2, "只从身体两侧流出，避免环形随机喷散")
	check(flow.amount <= 4, "同时只保留少量清晰流线")
	if process.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_POINTS:
		var points: Image = feedback.get("_flow_points")
		var left := points.get_pixel(0, 0)
		var right := points.get_pixel(1, 0)
		check(left.r < 0.0 and right.r > 0.0 and is_equal_approx(left.r, -right.r), "两侧流线对称留出人物中心")
		var texture_before: Texture2D = process.emission_point_texture
		feedback.advance(0.01)
		check(process.emission_point_texture == texture_before, "飞行与转向复用发射点纹理，不逐帧重建")
	check(process.scale_curve.curve.sample_baked(0.9) > 0.6, "消散保持长条形，不缩成散碎点")
	check(player.sprite.get_instance_shader_parameter("speed_rim_data").x == 0.0, "新版不启用人物内侧描边")
	var item: Dictionary = feedback._active.front()
	var decal: Decal = item.decal
	check(decal != null and decal.texture_emission == formal.get("surface_wave_texture"), "扩散使用原生发光贴花和 Meowa 冲击纹理")
	check(decal.albedo_mix == 0.0 and decal.normal_fade > 0.0, "贴花不覆盖建筑原色，并排除侧向误投影")
	check(decal.global_position.is_equal_approx(impacts.back().point) and decal.global_basis.y.is_equal_approx(impacts.back().normal), "贴花中心和投影轴遵守真实碰点与法线")
	var fixed := decal.global_transform
	var size := decal.size
	var energy := decal.emission_energy
	var clock: float = item.age
	feedback._collided(impacts.back())
	check(feedback.active_count() == 1, "重复通知不会叠加效果")
	session.set_combat_frozen(true)
	feedback.advance(0.2)
	check(item.age == clock and decal.size == size and decal.emission_energy == energy and flow.speed_scale == 0.0, "冻结同时暂停扩张、消散与 GPU 气流")
	session.set_combat_frozen(false)
	var position := player.global_position
	var speed := body.flight_speed
	feedback.advance(0.06)
	check(flow.speed_scale == 1.0 and decal.size.x > size.x, "恢复后继续扩张而不跳过冻结时间")
	check(player.global_position == position and body.flight_speed == speed, "新表现不修改运动和耗速")
	camera.rotation.y += PI * 0.5
	feedback.advance(0.01)
	check(decal.global_transform == fixed, "人物与镜头运动不拖走表面效果")
	var source: Texture2D = player.sprite.texture
	var pixels := source.get_image().get_data()
	body.cancel(true)
	for frame in 80: feedback.advance(0.01)
	check(not flow.emitting and not flow.visible and feedback.active_count() == 0 and not feedback.is_processing(), "取消后自然收尾并停止空闲工作")
	check(player.sprite.texture == source and source.get_image().get_data() == pixels, "人物原纹理和透明度保持不变")
	var children: int = feedback.get_child_count()
	var last: RicochetImpact = impacts.back()
	feedback._collided(RicochetImpact.new(last.point, last.normal, last.incoming_velocity, last.outgoing_velocity, last.serial + 1, body.flight_serial, 1.0))
	check(feedback._active.front().decal == decal and feedback.get_child_count() == children, "后续碰撞复用原生贴花节点")
	for index in 12:
		feedback._collided(RicochetImpact.new(last.point, last.normal, last.incoming_velocity, last.outgoing_velocity, feedback._serial + 1, body.flight_serial, 1.0))
	check(feedback.active_count() == feedback.MAX_WAVES and feedback.get_child_count() == feedback.MAX_WAVES + 1, "密集反弹保持有限贴花池与一个气流系统")
	feedback._phase(WavePrototype.Phase.REST)
	check(feedback.active_count() == 0 and not flow.emitting and not flow.visible and not feedback.is_processing(), "清波立即清理并停止处理")
	player.action_visuals.surface_wave_enabled = false
	feedback._collided(RicochetImpact.new(last.point, last.normal, last.incoming_velocity, last.outgoing_velocity, feedback._serial + 1, body.flight_serial, 2.0))
	check(feedback.active_count() == 0, "扩散独立开关生效")
	await air_checks(feedback)

func air_checks(feedback: Variant) -> void:
	if not "speed_flow_mode" in player.action_visuals:
		check(false, "需要连续空气绕流模式，不能只用独立笔触粒子")
		return
	await reset()
	feedback.clear()
	player.action_visuals.set("speed_flow_mode", 1)
	check(body.begin_charge(Vector3.RIGHT) and body.release_charge(), "空气绕流由真实弹射启动")
	feedback.set_process(false)
	feedback.advance(0.04)
	var air: Variant = feedback.get("_air")
	check(air != null and air.visible and air.amount > 0.0, "高速飞行显示连续绕流表面")
	if air == null: return
	check(air.mesh is ArrayMesh, "划过的空气使用开放风片，不能形成圆柱包裹表面")
	var air_shader: Shader = air.material_override.shader
	check(not air_shader.code.contains("hint_screen_texture") and not air_shader.code.contains("SCREEN_UV"), "气流不读取或重画背景，避免波纹镜面")
	check(not feedback._flow.emitting, "空气模式关闭独立笔触粒子")
	check(air.global_basis.z.is_equal_approx(body.direction), "空气绕流沿实际飞行方向定向")
	var phase: float = air.phase
	var mesh: Mesh = air.mesh
	var material: Material = air.material_override
	session.set_combat_frozen(true)
	feedback.advance(0.2)
	check(air.phase == phase, "冻结保持空气噪声流动相位")
	session.set_combat_frozen(false)
	feedback.advance(0.02)
	check(air.phase > phase and air.mesh == mesh and air.material_override == material, "恢复后继续流动，复用表面与材质")
	body.cancel(true)
	for frame in 80: feedback.advance(0.01)
	check(not air.visible and not feedback.is_processing(), "结束后绕流平滑消退并停止处理")
	feedback._phase(WavePrototype.Phase.REST)
	check(air.amount == 0.0 and air.phase == 0.0, "清波复位绕流状态")

func sample_path(enabled: bool) -> Array[Vector4]:
	if "speed_flow_enabled" in player.action_visuals:
		player.action_visuals.set("speed_flow_enabled", enabled)
		player.action_visuals.surface_wave_enabled = enabled
	return await super.sample_path(enabled)

func profile_checks() -> void:
	super.profile_checks()
	var formal: Resource = load("res://data/combat/scenes/world/player/action_visuals.tres")
	var city: Resource = load("res://data/combat/scenes/city/player/action_visuals.tres")
	check(formal.get("surface_wave_enabled") == true and formal.get("speed_flow_enabled") == true and not formal.speed_rim_enabled, "World 改用纹理气流与贴花，关闭旧速度描边")
	check(city.get("surface_wave_enabled") == false and city.get("speed_flow_enabled") == false, "City 保持独立")
	check(formal.get("surface_wave_texture") != null and formal.get("speed_flow_texture") != null, "正式资源必须绑定纹理，避免空白效果")
	check(formal.get("speed_flow_texture") != formal.get("departure_airflow_texture"), "持续速度流线使用独立的干净纹理，不再借用反弹喷气")
	check(formal.get("speed_flow_mode") == 1, "World 使用连续空气绕流，不用固定流线条数描述空气")
	var entries: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(player)
	for property in ["surface_wave_enabled", "surface_wave_texture", "surface_wave_radius", "surface_wave_seconds", "surface_wave_energy", "speed_flow_enabled", "speed_flow_mode", "speed_flow_texture", "speed_flow_texture_region", "speed_flow_opacity", "speed_flow_length", "speed_flow_lifetime", "speed_flow_radius"]:
		check(entries.any(func(item): return item.property == property and item.common and item.label != property), "参数总览提供中文入口：" + property)
