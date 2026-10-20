extends "res://tests/test_player_sword.gd"

func flight_checks() -> void:
	var original := sword.rules
	var formal := load("res://data/combat/scenes/world/player/basic_sword.tres").duplicate() as PlayerSwordRules
	check(is_equal_approx(formal.flight_angle, 360.0), "World 弹射每刀扫满一圈")
	check(formal.get("flight_ribbon_visual") != null, "弹射剑光有独立外观，保留普通短弧")
	if failures: return
	formal.audio_enabled = false
	sword.rules = formal
	player.ricochet_rules.enemy_push_enabled = false
	for step in [0.15, 1.0 / 30.0, 1.0 / 120.0]:
		await reset()
		var targets: Array[WaveEnemy] = []
		var directions: Array[Vector3] = []
		for index in 16:
			var angle := TAU * index / 16.0
			targets.append(enemy(Vector3(cos(angle), 0, sin(angle)) * 1.1))
			targets[-1].damaged.connect(func(event: CombatDamageEvent):
				var outward := event.world_position - player.global_position
				outward.y = 0.0
				directions.append(event.direction - outward.normalized()))
		var far := enemy(Vector3.RIGHT * (formal.flight_range + 0.005))
		var high := enemy(Vector3(0, 1.0, -1))
		var warning := enemy(Vector3(0, 0, 1))
		warning.spawn_delay = 2.0
		var time := 0.0
		while time < 0.15 - 0.000001:
			var delta := minf(step, 0.15 - time)
			sword._simulate(player.global_position, player.global_position, delta, true, Vector3.RIGHT)
			sword._drain_hits()
			time += delta
		check(targets.all(func(mob): return mob.health == 190.0) and damage_events.size() == 16, "整圈各方位和接缝每怪仅一次，物理步长 %s" % step)
		check(far.health == 200.0 and high.health == 200.0 and warning.health == 200.0, "整圈仍遵守真实半径、高度和出场保护")
		check(strikes.size() == 1 and damage_events.all(func(hit): return hit.flying), "一圈仍是一刀真实弹射攻击")
		check(pushes == 0, "整圈伤害不恢复正式关闭的拨怪和眩晕")
		check(directions.size() == 16 and directions.all(func(offset): return offset.is_zero_approx()), "各方向受击反馈使用真实向外来向，不全部朝飞行前方")
		sword._simulate(player.global_position, player.global_position, 0.30, true, Vector3.RIGHT)
		sword._drain_hits()
		check(targets.all(func(mob): return mob.health == 180.0) and strikes.size() == 2, "下一攻击周期可再次整圈伤害，不每帧扣血")
		check(not strikes[0].reverse and not strikes[1].reverse, "环绕剑光保持同一旋向，普通攻击仍交替")
	await reset()
	var rear := enemy(Vector3.LEFT)
	check(sword._first_target(player.global_position, player.global_position, Vector3.RIGHT, sword.get_stats(true)).entry == 0.0, "身后目标也能触发弹射环绕出剑")
	sword._simulate(player.global_position, player.global_position + Vector3.RIGHT * 0.7, 0.15, true, Vector3.RIGHT)
	sword._drain_hits()
	check(rear.health == 190.0, "高速移动时连续旋转刀锋仍命中起点后方，不漏判")
	await reset()
	rear = enemy(Vector3.LEFT)
	var front := enemy(Vector3.RIGHT)
	var wall := box(Vector3(-0.5, 0.6, 0), Vector3(0.02, 1.2, 5))
	await settle()
	sword._simulate(player.global_position, player.global_position, 0.15, true, Vector3.RIGHT)
	sword._drain_hits()
	check(rear.health == 200.0 and front.health == 190.0, "整圈只打到真实墙体同侧，不穿墙伤害")
	wall.queue_free()
	await settle()
	await reset()
	var over_water := enemy(Vector3(1.2, 0, 0))
	terrain.data.set_overlay(Vector2i(1, 0), TerrainData.OVERLAY_WATER, true)
	await settle()
	sword._simulate(player.global_position, player.global_position, 0.15, true, Vector3.RIGHT)
	sword._drain_hits()
	check(over_water.health == 200.0, "整圈继续遵守真实水面阻隔")
	terrain.data.set_overlay(Vector2i(1, 0), TerrainData.OVERLAY_WATER, false)
	await settle()
	await reset()
	enemy(Vector3.LEFT)
	sword._begin(Vector3.RIGHT, true)
	check(sword._settings.ribbon_visual != formal.ribbon_visual and sword._settings.ribbon_visual != formal.flight_ribbon_visual, "弹射独立样式在起刀时取快照")
	var width := sword._settings.ribbon_visual.ribbon_width
	formal.flight_ribbon_visual.ribbon_width *= 1.5
	check(is_equal_approx(sword._settings.ribbon_visual.ribbon_width, width), "编辑弹射外观不改写当前刀或普攻外观")
	formal.flight_ribbon_visual.ribbon_width = width
	await reset()
	var targets: Array[WaveEnemy] = []
	for index in 8:
		var angle := TAU * index / 8.0
		targets.append(enemy(Vector3(cos(angle), 0, sin(angle)) * 1.1))
	sword._begin(Vector3.RIGHT, true)
	sword._simulate(player.global_position, player.global_position, 0.10, true, Vector3.RIGHT)
	sword._drain_hits()
	var before := damage_events.size()
	var age := sword._age
	session.set_combat_frozen(true)
	sword._physics_process(0.5)
	check(sword._age == age and damage_events.size() == before and before > 0 and before < 8, "半圈冻结保留真实进度和已命中集合")
	session.set_combat_frozen(false)
	sword._simulate(player.global_position, player.global_position, 0.05, true, Vector3.RIGHT)
	sword._drain_hits()
	check(targets.all(func(mob): return mob.health == 190.0) and damage_events.size() == 8, "恢复后扫完另外半圈，首半圈不重复结算")
	await reset()
	for rank in 30: session.combat_modifiers.apply_buff(load("res://data/growth/cooldown.tres"))
	session.combat_modifiers.apply_buff(load("res://data/growth/range.tres"))
	session.combat_modifiers.apply_buff(load("res://data/growth/damage.tres"))
	var grown := enemy(Vector3.LEFT * 1.7, 10000.0)
	for frame in 120:
		sword._simulate(player.global_position, player.global_position, 1.0 / 120.0, true, Vector3.RIGHT)
		sword._drain_hits()
	check(strikes.size() == 9 and damage_events.size() == 9 and grown.health == 9892.0, "整圈按共享伤害、范围与攻速成长，每刀独立结算")
	sword.rules = original
	player.ricochet_rules.enemy_push_enabled = true
	await reset()

func input_and_art_checks() -> void:
	await super.input_and_art_checks()
	await reset()
	var original := sword.rules
	var formal := load("res://data/combat/scenes/world/player/basic_sword.tres").duplicate() as PlayerSwordRules
	if formal.get("flight_ribbon_visual") == null: return
	check(formal.validation_error().is_empty(), "正式整圈资源通过校验")
	var invalid := formal.duplicate() as PlayerSwordRules
	invalid.flight_angle = 361.0
	check(not invalid.validation_error().is_empty(), "弹射扇角不能超过一整圈")
	invalid.flight_angle = 360.0
	invalid.normal_angle = 360.0
	check(not invalid.validation_error().is_empty(), "整圈能力不放宽普通攻击扇角")
	var city: PlayerSwordRules = load("res://data/combat/scenes/city/player/basic_sword.tres")
	check(city.flight_angle == 180.0 and city.flight_ribbon_visual == null, "City 与共享默认保留原扇区和样式")
	formal.audio_enabled = false
	sword.rules = formal
	enemy(Vector3.RIGHT)
	sword._simulate(player.global_position, player.global_position, 0.10, true, Vector3.RIGHT)
	sword._update_effect()
	var effect := sword._effect
	var material := effect._material
	check(material.shader.resource_path.ends_with("player_sword_orbit.gdshader"), "弹射使用独立极坐标环绕材质")
	check(material.get_shader_parameter("stroke_texture") == formal.flight_ribbon_visual.ribbon_brush, "环绕材质复用原生 Meowa 笔触")
	var mesh := effect.mesh
	check(mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 129 * 5, "整圈加密角度模板，保持原半圈的墙体裁切精度")
	var phase: float = material.get_shader_parameter("leading_angle")
	session.set_combat_frozen(true)
	sword._physics_process(0.5)
	check(is_equal_approx(material.get_shader_parameter("leading_angle"), phase), "冻结停止环绕相位和消散")
	session.set_combat_frozen(false)
	sword._simulate(player.global_position, player.global_position, 0.06, true, Vector3.RIGHT)
	sword._update_effect()
	var active := sword._tail_pool.filter(func(tail): return tail.age >= 0.0)
	check(active.size() == 1 and not effect.visible, "一圈结束交接池化世界余迹，不跟随人物拖动")
	if not active.is_empty():
		var tail: Dictionary = active[0]
		player.global_position += Vector3.RIGHT
		sword._update_tails()
		check(tail.effect.global_position == tail.origin, "破碎余迹保留真实挥砍位置")
	await reset()
	sword._begin(Vector3.RIGHT, false)
	sword._age = sword._settings.windup_seconds + 0.05
	sword._update_effect()
	check(effect._material.shader.resource_path.ends_with("player_sword_flow_slash.gdshader"), "切回普攻仍使用原来的短弧流动材质")
	await reset()
	sword._begin(Vector3.RIGHT, true)
	sword._age = sword._settings.windup_seconds + 0.05
	sword._update_effect()
	check(effect._material == material and effect.mesh == mesh, "反复切换复用环绕材质与平地整圈网格")
	for property in ["stroke_texture", "flow_noise", "leading_angle", "visual_age", "secondary_strength", "plane_slope"]:
		check(material.get_shader_parameter(property) == material.next_pass.get_shader_parameter(property), "怪物轮廓补画同步环绕参数：" + property)
	var wall := box(Vector3(0.8, 0.6, 0), Vector3(0.02, 1.2, 5))
	await settle()
	sword._update_effect()
	var clipped := true
	for vertex in effect.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		var point: Vector3 = effect.global_transform * vertex
		clipped = clipped and point.x <= 0.8001
	check(clipped, "整圈剑光继续按真实墙体裁切")
	wall.queue_free()
	await settle()
	var exported := player.sword_rules
	player.sword_rules = formal
	var entries: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(player)
	player.sword_rules = exported
	for property in ["ribbon_orbit_enabled", "ribbon_orbit_secondary_strength", "ribbon_orbit_secondary_offset"]:
		check(entries.any(func(entry): return entry.object == formal.flight_ribbon_visual and entry.property == property and entry.common and entry.label != property), "参数总览提供弹射环绕中文入口：" + property)
	sword.rules = original
	await reset()
