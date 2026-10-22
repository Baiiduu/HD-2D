extends "res://tests/test_preview_query_view.gd"

func outline_bytes(value: Dictionary) -> PackedByteArray:
	if value.is_empty(): return var_to_bytes([])
	return var_to_bytes([value.positions, value.body_radius, value.player_radius, value.members.keys()])

func compare_capture(label: String) -> void:
	var rules := player.ricochet_rules.duplicate() as PlayerRicochetRules
	rules.eccentric_enabled = true
	var capture := PlayerCrowdDeflection.new(rules, session)
	var seed := session.enemies[5]
	var point := Vector3(0, 0.03, 0)
	var expected := capture._legacy_eccentric_outline(seed, point, {})
	var actual := capture._eccentric_outline(seed, point)
	check(outline_bytes(actual) == outline_bytes(expected), "实际接群轮廓、成员顺序和体型与原查询完全一致：" + label)
	if not actual.is_empty():
		var renewed := capture._eccentric_outline(seed, point, actual.members)
		var old_renewed := capture._legacy_eccentric_outline(seed, point, actual.members)
		check(outline_bytes(renewed) == outline_bytes(old_renewed), "续段仅重读旧群存活相连成员：" + label)
	check(capture._query_view == null and capture._preview_obstacles == null, "实际飞行不保留同步查询视图或障碍证明：" + label)

func run() -> void:
	await fixture()
	await populate(128)
	wall.position.x = 20.0
	await settle()
	compare_capture("空地混编怪群")
	var rules := player.ricochet_rules.duplicate() as PlayerRicochetRules
	rules.eccentric_enabled = true
	var capture := PlayerCrowdDeflection.new(rules, session)
	terrain.query_diagnostics_enabled = true
	terrain.reset_query_metrics()
	var old := capture._legacy_eccentric_outline(session.enemies[5], Vector3(0, 0.03, 0), {})
	var old_queries: int = terrain.get_query_metrics().ray_requests
	terrain.reset_query_metrics()
	var actual := capture._eccentric_outline(session.enemies[5], Vector3(0, 0.03, 0))
	var new_queries: int = terrain.get_query_metrics().ray_requests
	check(not old.is_empty() and outline_bytes(old) == outline_bytes(actual), "性能资格使用同一完整怪群")
	check(new_queries < old_queries / 2, "空地实际接群复用一次实时障碍收集，避免逐怪重复射线")
	wall.position = Vector3(0, 0.5, -1.1)
	wall.get_child(0).shape.size = Vector3(8, 1, 0.025)
	await settle()
	compare_capture("新移入的薄墙")
	wall.collision_layer = ProjectileCollision.MIRROR_SURFACE.COLLISION_LAYER
	await settle()
	compare_capture("动态镜面")
	wall.position.x = 20.0
	await settle()
	var actor := session.enemies[5]
	actor.global_position += Vector3(0.4, 0, 0.3)
	actor.commit_spatial_state()
	compare_capture("本帧提交后的新位置")
	var custom := CustomIndex.new()
	for enemy in session.enemies: custom.update(enemy)
	session._spatial_index = custom
	check(capture._eccentric_outline(actor, Vector3.ZERO).is_empty(), "自定义索引保留公共查询覆写，不绕过扩展接口")
	body.cancel(true)
	clear_enemies()
	world.queue_free()
	await settle()
	print("Live orbit queries: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
