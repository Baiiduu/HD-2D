extends "res://tests/test_sword_meowa_arc.gd"

func active_tails() -> Array[Dictionary]:
	return sword._tail_pool.filter(func(tail): return tail.age >= 0.0)

func input_and_art_checks() -> void:
	await super.input_and_art_checks()
	await reset()
	var original := sword.rules
	var meowa := load("res://data/player/basic_sword.tres").duplicate() as PlayerSwordRules
	meowa.audio_enabled = false
	sword.rules = meowa
	var mob := enemy(Vector3(1, 0, 0))
	check(sword.request_manual(Vector3.RIGHT), "拖尾试玩沿用真实普攻请求")
	sword._physics_process(0.16)
	check(not sword._effect.visible and active_tails().size() == 1, "扫刃结束转入独立余迹，不同时叠加第二片主体")
	var tail: Dictionary = active_tails()[0]
	var effect: GroundSlashEffect = tail.effect
	var origin: Vector3 = tail.origin
	check(effect.visible and is_equal_approx(tail.age, 0.01), "跨过扫击边界后余迹只推进本物理帧剩余时间")
	check(is_equal_approx(effect._material.get_shader_parameter("body_opacity"), meowa.meowa_body_opacity) and is_equal_approx(effect._material.next_pass.get_shader_parameter("tail_spread"), meowa.meowa_tail_spread) and is_equal_approx(effect._material.next_pass.get_shader_parameter("tail_inner_ratio"), meowa.meowa_tail_inner_ratio), "白刃削弱、拖尾展开及贴身曲率同步到怪物轮廓补画")
	sword._physics_process(0.10)
	check(not sword.swinging and effect.visible and mob.health == 190.0, "物理收尾结束后原生破碎继续播放，不延长或追加伤害")
	check(not sword.request_manual(Vector3.RIGHT), "视觉余迹不改变下一刀真实冷却")
	player.global_position += Vector3.RIGHT * 0.5
	sword._physics_process(0.02)
	check(effect.global_position.is_equal_approx(origin) and tail.origin == origin, "人物离开后余迹留在实际挥砍位置")
	var cached_mesh := effect.mesh
	var wall := box(Vector3(0.8, 0.6, 0), Vector3(0.02, 1.2, 5))
	await settle()
	sword._physics_process(0.01)
	var vertices: PackedVector3Array = effect.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var clipped := true
	for point in vertices:
		if (effect.global_transform * point).x > 0.8001: clipped = false
	check(effect.mesh != cached_mesh and clipped, "已释放的破碎余迹仍响应后来出现的真实挡墙")
	wall.queue_free()
	await settle()
	sword._physics_process(0.01)
	check(effect.mesh == cached_mesh, "移走挡墙后余迹恢复已有平地网格")
	var age: float = tail.age
	var rectangle: Vector4 = effect._material.get_shader_parameter("frame_rect")
	session.set_combat_frozen(true)
	sword._physics_process(0.5)
	check(is_equal_approx(tail.age, age) and effect._material.get_shader_parameter("frame_rect") == rectangle, "升级冻结同时暂停独立破碎与当前原生帧")
	session.set_combat_frozen(false)
	sword._physics_process(0.11)
	check(active_tails().is_empty() and not effect.visible and damage_events.size() == 1, "完整播放后余迹回池，原攻击仍只扣一次血")
	sword._physics_process(0.20)
	check(sword.request_manual(Vector3.RIGHT), "余迹结束后按原间隔正常出下一刀")
	sword._physics_process(0.16)
	check(active_tails().size() == 1 and active_tails()[0].effect == effect, "下一刀复用已有余迹节点")
	meowa.meowa_tail_seconds = 0.32
	check(is_equal_approx(active_tails()[0].settings.meowa_tail_seconds, 0.24), "正在消散的余迹保留该刀参数快照")
	meowa.meowa_tail_seconds = 0.24
	sword._on_phase(0)
	check(active_tails().is_empty() and not effect.visible, "清波与阶段切换立即清理独立余迹")
	for step in [0.60, 0.01]:
		await reset()
		mob = enemy(Vector3(1, 0, 0), 10000.0)
		for rank in 30: session.combat_modifiers.apply_buff(load("res://data/growth/cooldown.tres"))
		await flight()
		var maximum := 0
		var elapsed := 0.0
		while elapsed < 0.60 - 0.000001:
			var delta := minf(step, 0.60 - elapsed)
			sword._physics_process(delta)
			maximum = maxi(maximum, active_tails().size())
			elapsed += delta
		check(strikes.size() == 5 and damage_events.size() == 5 and is_equal_approx(mob.health, 9950.0), "步长 %.2f 的延长破碎不改变高攻速五刀五次伤害" % step)
		var ages: Array[float] = []
		for entry in active_tails(): ages.append(entry.age)
		ages.sort()
		check(ages.size() == 2 and is_equal_approx(ages[0], 0.06) and is_equal_approx(ages[1], 0.18), "步长 %.2f 只保留真实尚未结束的两道破碎" % step)
		check(maximum <= 2 and sword._tail_pool.size() <= 2, "步长 %.2f 的高攻速复用两枚余迹，不累计生成节点" % step)
	sword.cancel()
	check(active_tails().is_empty() and sword._tail_pool.all(func(entry): return not entry.effect.visible), "退出或重试清空所有余迹并保留闲置池")
	var catalog := preload("res://addons/parameter_hub/catalog.gd").new()
	var entries: Array[Dictionary] = catalog.collect(player)
	for property in ["meowa_body_opacity", "meowa_tail_spread", "meowa_tail_inner_ratio", "meowa_tail_seconds"]:
		check(entries.any(func(entry): return entry.object == player.sword_rules and entry.property == property and entry.common and entry.category == "人物" and entry.label != property), "参数总览暴露拖尾关键项：" + property)
	sword.rules = original
	await reset()
