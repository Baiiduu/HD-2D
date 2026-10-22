extends "res://tests/test_crowd_deflection.gd"

class CountingPath extends "res://scripts/player/player_eccentric_ricochet.gd":
	var builds := 0
	func build(point: Vector3, incoming: Vector3, surface: Dictionary) -> PackedVector3Array:
		builds += 1
		return super.build(point, incoming, surface)

class CountingCrowd extends PlayerCrowdDeflection:
	var outlines: int:
		get: return _eccentric.builds
	var samples := 0
	func _init(settings: PlayerRicochetRules, battle: WavePrototype) -> void:
		super(settings, battle)
		_eccentric = CountingPath.new(settings)
	func _eccentric_outline(seed: WaveEnemy, point: Vector3, allowed: Dictionary[int, WaveEnemy] = {}) -> Dictionary:
		samples += 1
		return super._eccentric_outline(seed, point, allowed)

func trace_short(settings: PlayerRicochetRules, followup: float) -> Array:
	var crowd := CountingCrowd.new(settings, session)
	var route := AimPathData.new()
	var speed := settings.maximum_launch_speed
	query.trace(player, Vector3.RIGHT, speed, settings.coast_seconds(speed), 8,
		settings.bounce_speed_retention, navigation, player.bounds, settings.ground_height_tolerance,
		route, 30.0, crowd, settings, followup)
	return [route, crowd]

func path_checks() -> void:
	player.ricochet_rules = load("res://data/player/body_ricochet.tres").duplicate()
	player.sword.rules.enabled = false
	var settings := player.ricochet_rules
	group(Vector3(2.6, 0, 0), 8, 7)
	var transform := player.global_transform
	var mask := PhysicsServer3D.body_get_collision_mask(player.get_rid())
	var clock := player.sword._since_strike
	var full := trace_short(settings, -1.0)
	var short := trace_short(settings, 1.0)
	check(full[1].outlines > 1 and short[1].outlines == 1, "蓄力短预测只建立一次轮廓，不续算后续绕圈")
	check(short[1].samples == 1, "提前判群的成员样本直接用于首次建线，不重复读取")
	check(short[0].crowd_contacts.size() == 1 and short[0].total_distance <= 2.5 and short[0].end_reason == &"preview_limit", "仅保留首次接群与短方向提示")
	check(short[0].crowd_contacts[0].is_equal_approx(full[0].crowd_contacts[0]), "缩短预测仍使用同一个真实接触点")
	check(player.global_transform == transform and PhysicsServer3D.body_get_collision_mask(player.get_rid()) == mask and player.sword._since_strike == clock, "短预测不改变人物、物理掩码或攻击时钟")
	var contact_only := trace_short(settings, 0.0)
	check(contact_only[1].outlines == 0 and contact_only[0].crowd_contacts.size() == 1, "尾段设为零时在首次接触点结束，不计算轮廓")
	settings.eccentric_step_distance = 0.6
	var small := trace_short(settings, 2.0)
	check(small[1].outlines == 1 and small[0].total_distance < 1.9, "缩小环绕更新路程也不会让预览重复建立轮廓")
	settings.eccentric_step_distance = 1.8
	await predict()
	check(body._charge_effect._route.total_distance < 2.5, "正式蓄力显示接入单次短预测")
	check(body.release_charge(), "优化预览后仍可以正常发射")
	for frame in 200:
		if not body.flying: break
		body.advance(1.0 / 60.0, Vector3.ZERO, false)
	check(TerrainPath.horizontal_distance(player.global_position, Vector3.ZERO) > 2.5 and body.crowd_deflection_count == 1, "实际弹射仍持续绕行，不受显示预测长度限制")
	await clear()
	var right := box(Vector3(0.7, 0.6, 0), Vector3(0.02, 1.2, 4))
	var left := box(Vector3(-0.7, 0.6, 0), Vector3(0.02, 1.2, 4))
	await settle()
	short = trace_short(settings, 2.0)
	check(short[0].contacts.size() == 1 and short[0].segments.size() == 2 and short[0].segments.back().heading.x < 0.0, "墙面仅预览一次反弹，第二面墙截断尾段")
	check(short[0].segments.back().end.x > -0.48, "短尾段仍按真实胶囊检查挡墙")
	left.queue_free()
	await settle()
	enemy(Vector3(-0.1, 0, 0))
	short = trace_short(settings, 1.0)
	check(short[0].contacts.size() == 1 and short[0].crowd_contacts.is_empty() and short[1].outlines == 0, "首次碰墙后遇到怪群只截断，不再计算第二种响应")
	right.queue_free()
	await clear()
