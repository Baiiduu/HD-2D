extends "res://tests/test_ricochet_camera.gd"

func settings_checks() -> void:
	await super.settings_checks()
	if not "charge_tremor_enabled" in settings:
		check(false, "蓄力镜头需要独立的混合波颤动配置")
		return
	await tremor_checks()

func tremor_checks() -> void:
	var profile := load("res://data/combat/scenes/world/player/ricochet_camera.tres")
	var city := load("res://data/combat/scenes/city/player/ricochet_camera.tres")
	check(profile.get("charge_tremor_enabled") and not city.get("charge_tremor_enabled"), "混合波颤动仅由 World 独立启用")
	settings.charge_focus_enabled = true
	settings.charge_staging_enabled = true
	settings.charge_full_shake_enabled = false
	settings.charge_full_punch_ratio = 0.0
	settings.set("charge_tremor_enabled", true)
	player.movement_camera = camera
	await reset()
	var initial := camera.global_transform
	check(body.begin_charge(Vector3.RIGHT), "混合波颤动由真实蓄力触发")
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(initial), "颤动起手不跳变")
	body.advance(0.1, Vector3.ZERO, false)
	var low := sample_motion(120, 0.5)
	body.advance(0.4, Vector3.ZERO, false)
	var full := sample_motion(120, 1.2)
	var feedback := camera._ricochet_camera
	var amplitude := float(settings.get("charge_tremor_pixels"))
	check(float(full.peak) > float(low.peak) * 1.8, "真实蓄力增强颤动幅度")
	check(float(full.peak) <= amplitude + 0.001, "横纵混合后的总颤动仍服从像素幅度上限")
	check(full.changes.x >= 4 and full.changes.y >= 4, "满蓄仍有连续的横纵混合波，而非只在满蓄瞬间反馈")
	check(float(full.max_step) < amplitude * 0.8, "高帧率下颤动平滑连续")
	var offset := camera.global_position - (camera.focus + camera._orbit_offset())
	check(offset.length() > 0.00001, "颤动叠加到真实相机位置")
	check(feedback.framing.length() < 0.0001 and is_equal_approx(feedback.pitch_offset, -settings.charge_pitch_drop), "颤动不改写主运镜轨迹及低角度")
	var cursor := Vector2(880, 475)
	var aim: Vector3 = camera.project_charge_aim(cursor, player.global_position.y)
	for frame in 18: camera._process(1.0 / 120.0)
	check(aim.distance_to(camera.project_charge_aim(cursor, player.global_position.y)) < 0.001, "颤动不带偏固定鼠标的地面瞄准")
	camera._yaw_offset_degrees = 45.0
	camera._process(0.0)
	var rotated_aim: Vector3 = camera.project_charge_aim(cursor, player.global_position.y)
	for frame in 18: camera._process(1.0 / 120.0)
	check(rotated_aim.distance_to(camera.project_charge_aim(cursor, player.global_position.y)) < 0.001 and aim.distance_to(rotated_aim) > 0.1, "Q/E 朝向参与瞄准，颤动保持补偿")
	var held := camera.global_transform
	session.set_combat_frozen(true)
	camera._process(0.4)
	check(camera.global_transform.is_equal_approx(held), "升级冻结保留颤动相位与机位")
	session.set_combat_frozen(false)
	var direction := body.direction
	check(body.release_charge(), "颤动不延迟真实发射")
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(held) and body.direction == direction, "松手当帧继承颤动位置，保留发射方向")
	var released := feedback.shake.length()
	camera._process(0.02)
	check(feedback.shake.length() > 0.0 and feedback.shake.length() < released, "松手后从当前偏移平滑衰减")
	for frame in 36: camera._process(1.0 / 120.0)
	check(feedback.shake.is_zero_approx(), "飞行中不会持续播放蓄力颤动")
	body.cancel(true)
	camera._yaw_offset_degrees = 0.0
	await reset()
	check(body.begin_charge(Vector3.RIGHT), "取消及重按用例可蓄力")
	body.advance(0.35, Vector3.ZERO, false)
	sample_motion(120, 0.2)
	var cancel_pose := camera.global_transform
	body.cancel(true)
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(cancel_pose), "取消当帧接住当前颤动位置")
	camera._process(0.03)
	var return_pose := camera.global_transform
	check(body.begin_charge(Vector3.RIGHT), "衰减中可以重新蓄力")
	camera._process(0.0)
	check(camera.global_transform.is_equal_approx(return_pose), "快速重按不重置相位或造成机位跳变")
	settings.set("charge_tremor_enabled", false)
	for frame in 60: camera._process(1.0 / 120.0)
	check(feedback.shake.is_zero_approx() and feedback.active, "独立关闭颤动后清零偏移，主蓄力镜头继续")
	settings.set("charge_tremor_enabled", true)
	for frame in 12: camera._process(1.0 / 120.0)
	camera.snap_to_target()
	check(feedback.shake.is_zero_approx() and not feedback.active, "显式重置清除颤动")
	await reset()
	check(body.begin_charge(Vector3.RIGHT), "高帧率对照可蓄力")
	body.advance(0.5, Vector3.ZERO, false)
	sample_motion(120, 1.0)
	var high_rate := feedback.shake
	await reset()
	check(body.begin_charge(Vector3.RIGHT), "低帧率对照可蓄力")
	body.advance(0.5, Vector3.ZERO, false)
	sample_motion(30, 1.0)
	check(high_rate.distance_to(feedback.shake) < 0.000001, "相同经过时间在不同帧率下产生相同混合波位置")
	settings.charge_staging_enabled = false
	var basic_aim: Vector3 = camera.project_charge_aim(cursor, player.global_position.y)
	for frame in 18: camera._process(1.0 / 120.0)
	check(basic_aim.distance_to(camera.project_charge_aim(cursor, player.global_position.y)) < 0.001, "关闭分段运镜后颤动仍独立补偿瞄准")
	settings.enabled = false
	camera._process(0.1)
	check(feedback.shake.is_zero_approx(), "总开关关闭无残留")
	body.cancel(true)
	settings.enabled = true
	settings.set("charge_tremor_enabled", false)
	settings.charge_focus_enabled = false
	settings.charge_staging_enabled = false

func sample_motion(rate: int, seconds: float) -> Dictionary:
	var peak := 0.0
	var max_step := 0.0
	var changes := Vector2i.ZERO
	var previous := camera._ricochet_camera.shake * 800.0
	for frame in int(rate * seconds):
		camera._process(1.0 / rate)
		var current := camera._ricochet_camera.shake * 800.0
		peak = maxf(peak, current.length())
		max_step = maxf(max_step, current.distance_to(previous))
		if current.x * previous.x < 0.0: changes.x += 1
		if current.y * previous.y < 0.0: changes.y += 1
		previous = current
	return {"peak": peak, "max_step": max_step, "changes": changes}
