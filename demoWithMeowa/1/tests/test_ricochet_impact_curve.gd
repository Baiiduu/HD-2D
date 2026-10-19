extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func contact(serial := 1, normal := Vector3.LEFT, incoming := Vector3.RIGHT * 12.0, outgoing := Vector3.LEFT * 10.0) -> RicochetImpact:
	return RicochetImpact.new(Vector3.ZERO, normal, incoming, outgoing, serial, 1, serial * 0.03)

func run() -> void:
	var settings := load("res://data/combat/scenes/world/player/ricochet_camera.tres") as RicochetCameraSettings
	check(settings.impact_shot_offset_ratio >= 0.02 and settings.impact_shot_offset_ratio <= 0.03 and settings.impact_shot_yaw_degrees >= 1.0 and settings.impact_shot_yaw_degrees <= 2.0 and settings.impact_shot_roll_degrees <= 0.4 and settings.impact_shot_pullback_ratio >= 0.009 and settings.impact_shot_pullback_ratio <= 0.016, "World 使用两版之间的中等位移、转向和拉远，侧倾保持克制")
	var curve: Curve = settings.get("impact_shot_curve")
	check(curve != null, "World 配置可在编辑器调整的定向回弹曲线")
	if curve:
		settings = settings.duplicate() as RicochetCameraSettings
		settings.set("impact_split_enabled", false)
		curve_checks(settings, curve)
		continuity_checks(settings)
		strength_checks(settings)
	layered_checks()
	var city := load("res://data/combat/scenes/city/player/ricochet_camera.tres") as RicochetCameraSettings
	check(not city.impact_shot_enabled and city.get("impact_shot_curve") == null, "City 保留原有独立镜头配置")
	print("Ricochet impact curve: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func layered_checks() -> void:
	var settings := load("res://data/combat/scenes/world/player/ricochet_camera.tres") as RicochetCameraSettings
	if not "impact_split_enabled" in settings:
		check(false, "World 需要独立开启短冲击与出射跟随分层")
		return
	check(settings.get("impact_split_enabled") and not RicochetCameraSettings.new().get("impact_split_enabled"), "World 明确开启分层，保留共享配置默认")
	var shot: Variant = RicochetImpactShot.new()
	shot.start(contact(), settings, 12.0)
	shot.advance(0.02, settings)
	var front := Basis.IDENTITY
	var diagonal := Basis(Vector3.UP, PI * 0.25) * Basis(Vector3.RIGHT, -PI * 0.5 + 0.2)
	var a: Vector2 = shot.screen_punch(front, 800.0, settings)
	var b: Vector2 = shot.screen_punch(diagonal, 800.0, settings)
	check(a.length() > 0.001 and is_equal_approx(a.length(), b.length()), "同一正撞在不同镜头朝向下保持相同屏幕冲击幅度")
	check(a.length() * 800.0 <= float(settings.get("impact_punch_pixels")) + 0.001, "短冲击遵守真实视口像素上限")
	var before: Vector2 = shot.screen_punch(front, 800.0, settings)
	var position: Vector3 = shot.offset
	var velocity: Vector3 = shot.velocity
	shot.start(contact(2), settings, 12.0)
	shot.advance(0.0, settings)
	check(shot.screen_punch(front, 800.0, settings).is_equal_approx(before), "密集碰撞不反复重置或叠加短冲击")
	check(shot.offset.distance_to(position) < 0.00001 and shot.velocity.distance_to(velocity) < 0.00001, "分层机位在连续碰撞时保留位置与速度连续")
	shot.advance(0.10, settings)
	check(shot.screen_punch(front, 800.0, settings).is_zero_approx() and shot.active and shot.offset.x < 0.0, "短冲击结束后机位继续沿真实出射方向跟进")
	check(absf(shot.yaw) > 0.1 and shot.pullback > 0.0, "低频转向与拉远独立于短冲击收尾")
	shot.release(0.10)
	shot.advance(0.11, settings)
	check(shot.offset.is_zero_approx() and shot.screen_punch(front, 800.0, settings).is_zero_approx(), "取消后两层均无残留")
	var first: Variant = RicochetImpactShot.new()
	var second: Variant = RicochetImpactShot.new()
	first.start(contact(), settings, 12.0)
	second.start(contact(), settings, 12.0)
	for frame in 6: first.advance(1.0 / 60.0, settings)
	for frame in 12: second.advance(1.0 / 120.0, settings)
	check(first.offset.distance_to(second.offset) < 0.00001 and first.screen_punch(front, 800.0, settings).distance_to(second.screen_punch(front, 800.0, settings)) < 0.00001, "两层运动不随帧率改变")

func curve_checks(settings: RicochetCameraSettings, curve: Curve) -> void:
	check(is_zero_approx(curve.sample_baked(0.0)) and is_zero_approx(curve.sample_baked(1.0)), "回弹曲线首尾为零，不从撞击点跳出或留下余震")
	var shot := RicochetImpactShot.new()
	shot.start(contact(), settings, 12.0)
	shot.advance(0.0, settings)
	check(shot.offset.is_zero_approx() and shot.velocity.length() < 0.01, "第一帧从原有机位和速度开始")
	var peak := 0.0
	var peak_time := 0.0
	var return_peak := 0.0
	var late_peak := 0.0
	var side_peak := 0.0
	var normal_peak := 0.0
	var main_seconds := 0.0
	for frame in 240:
		var time := (frame + 1) * settings.impact_shot_seconds / 240.0
		shot.advance(settings.impact_shot_seconds / 240.0, settings)
		var displacement := shot.offset.x
		if displacement > peak:
			peak = displacement
			peak_time = time
		return_peak = maxf(return_peak, -displacement)
		if displacement >= 12.0 * settings.impact_shot_offset_ratio * 0.5: main_seconds += settings.impact_shot_seconds / 240.0
		if time >= settings.impact_shot_seconds * 0.5: late_peak = maxf(late_peak, shot.offset.length())
		side_peak = maxf(side_peak, absf(shot.offset.z))
		normal_peak = maxf(normal_peak, absf(shot.offset.x))
	check(peak > 0.0 and peak_time <= settings.impact_shot_seconds * 0.25, "碰撞重心在前四分之一，先短促沿法向轻压")
	var reference_pixels := peak / 12.0 * 800.0
	check(reference_pixels >= 12.0 and reference_pixels <= 24.0 and main_seconds >= 0.05 and main_seconds <= 0.10, "参考 800 像素短边时主冲击为中等幅度，并保留数帧可读的主峰")
	check(return_peak > 0.0 and return_peak <= peak * 0.25, "随后只有小幅反向回弹，不持续等幅摆动")
	check(late_peak <= peak * 0.20, "后半段快速收敛，不在出射后继续大幅摆镜头")
	check(side_peak < 0.00001 and normal_peak <= 12.0 * settings.impact_shot_offset_ratio + 0.00001, "正撞定向回应实际碰撞，不额外横向绕一大圈")
	shot.advance(0.001, settings)
	check(not shot.active and shot.offset.is_zero_approx() and shot.velocity.is_zero_approx(), "完整曲线按时结束，无残余位移或速度")

func continuity_checks(settings: RicochetCameraSettings) -> void:
	var shot := RicochetImpactShot.new()
	shot.start(contact(), settings, 12.0)
	shot.advance(0.052, settings)
	var offset := shot.offset
	var velocity := shot.velocity
	var yaw := shot.yaw
	shot.start(contact(), settings, 12.0)
	check(shot.offset == offset and shot.velocity == velocity, "同一事件重复通知不重新震动")
	shot.start(contact(2, Vector3.FORWARD, Vector3.BACK * 12.0, Vector3.FORWARD * 10.0), settings, 12.0)
	shot.advance(0.0, settings)
	check(shot.offset.is_equal_approx(offset) and shot.velocity.distance_to(velocity) < 0.01 and is_equal_approx(shot.yaw, yaw), "连续反弹接住当前机位及速度，不猛地重置")
	var bounded := true
	for serial in range(3, 20):
		shot.advance(0.03, settings)
		shot.start(contact(serial), settings, 12.0)
		bounded = bounded and shot.offset.length() <= 12.0 * settings.impact_shot_offset_ratio + 0.00001
	check(bounded, "密集反弹不会不断叠大震幅")
	var before := shot.offset
	shot.release(0.10)
	shot.advance(0.0, settings)
	check(shot.offset.is_equal_approx(before), "取消从当前曲线位置平滑收回")
	shot.advance(0.11, settings)
	check(not shot.active and shot.offset.is_zero_approx(), "取消后及时归位")
	shot.start(contact(21), settings, 12.0)
	shot.advance(0.03, settings)
	settings = settings.duplicate() as RicochetCameraSettings
	settings.impact_shot_enabled = false
	shot.advance(0.01, settings)
	check(not shot.active and shot.offset.is_zero_approx(), "关闭效果立即清理临时机位")

func strength_checks(settings: RicochetCameraSettings) -> void:
	var strong := RicochetImpactShot.new()
	var light := RicochetImpactShot.new()
	strong.start(contact(), settings, 12.0)
	light.start(contact(2, Vector3.LEFT, Vector3(2.4, 0, 11.7), Vector3(-2.0, 0, 11.7)), settings, 12.0)
	var strong_peak := 0.0
	var light_peak := 0.0
	for frame in 120:
		strong.advance(0.003, settings)
		light.advance(0.003, settings)
		strong_peak = maxf(strong_peak, strong.offset.length())
		light_peak = maxf(light_peak, light.offset.length())
	check(light_peak > 0.0 and light_peak < strong_peak * 0.25, "同样高速的擦墙按真实法向速度减弱反馈")
	var first := RicochetImpactShot.new()
	var second := RicochetImpactShot.new()
	first.start(contact(), settings, 12.0)
	second.start(contact(), settings, 12.0)
	for frame in 6: first.advance(1.0 / 60.0, settings)
	for frame in 12: second.advance(1.0 / 120.0, settings)
	check(first.offset.distance_to(second.offset) < 0.00001 and absf(first.yaw - second.yaw) < 0.00001, "不同帧率的同一时间采到相同曲线，不随帧数抖动")
