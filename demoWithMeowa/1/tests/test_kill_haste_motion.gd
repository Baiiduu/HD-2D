extends "res://tests/test_aim_path_preview.gd"

func path_checks() -> void:
	player.action_visuals.show_aim_guide = false
	session.combat_modifiers.growth_rules = RunGrowthRules.new()
	session.combat_modifiers.growth_rules.kill_haste_seconds = 0.25
	var card: GrowthBuffDefinition = load("res://data/combat/scenes/world/growth/legendary/kill_haste.tres")
	session.combat_modifiers.apply_buff(card)
	for index in 4: session.combat_modifiers.record_kill()
	var route := await predict(Vector3.RIGHT, 1, 30.0)
	var before := session.combat_modifiers.haste_stacks()
	check(before == 4 and route.total_distance > 12.0, "Haste extends the actual path within unchanged energy duration")
	await compare_haste_flight(route)
	check(session.combat_modifiers.haste_stacks() == 0, "The real flight expires timed stacks while moving")
	var wall := box(Vector3(3,0.6,0), Vector3(0.05,1.2,8))
	await settle()
	for index in 4: session.combat_modifiers.record_kill()
	route = await predict(Vector3.RIGHT, 1, 30.0)
	check(route.contacts.size() == 1, "Haste prediction retains the real wall reflection")
	await compare_haste_flight(route)
	wall.queue_free()
	await settle()
	await orbit_haste_checks()

func orbit_haste_checks() -> void:
	var configuration: SceneCombatConfiguration = load("res://data/combat/scenes/world/configuration.tres")
	player.ricochet_rules = configuration.ricochet_rules.duplicate()
	session.growth_rules = configuration.growth_rules.duplicate()
	var mods := session.combat_modifiers
	mods.growth_rules = session.growth_rules
	player.sword.rules.enabled = false
	var card: GrowthBuffDefinition = load("res://data/combat/scenes/world/growth/legendary/kill_haste.tres")
	# 读取真实胶囊移动路段，而不是仅检查面板速度；分别覆盖低频与高频物理步。
	for step in [1.0 / 30.0, 1.0 / 120.0]:
		for kills in [0, 1, 10]:
			clear_enemies()
			mods.reset()
			check(mods.apply_buff(card) and mods.level_for(card.id) == 1, "Orbit sample learns only the first legendary rank")
			for row in 5:
				for column in 5: enemy(Vector3(3.0 + column * 0.65, 0.0, (row - 2) * 0.65))
			await reset()
			check(body.begin_charge(Vector3.RIGHT), "First-rank haste orbit sample can charge")
			body.advance(0.8, Vector3.ZERO, false)
			check(body.release_charge(), "First-rank haste orbit sample launches the actual player")
			for frame in 240:
				if body.orbiting or not body.flying: break
				body.advance(step, Vector3.ZERO, false)
			check(body.orbiting, "First-rank haste sample captures an actual persistent orbit")
			for frame in ceili(0.2 / step): body.advance(step, Vector3.ZERO, false)
			for index in kills:
				var target := enemy(Vector3(-6, 0, -6))
				target.defeated.connect(session._enemy_defeated)
				target.take_damage(10000.0)
			check(mods.haste_stacks() == kills, "Actual kills during orbit grant the expected first-rank stacks")
			var energy := body.flight_speed
			var sample := {"distance": 0.0, "seconds": 0.0}
			var capture := func(start: Vector3, end: Vector3, _heading: Vector3, seconds: float):
				sample.distance += TerrainPath.horizontal_distance(start, end)
				sample.seconds += seconds
			body.flight_segment_travelled.connect(capture)
			for frame in ceili(0.3 / step):
				body.advance(step, Vector3.ZERO, false)
				mods.advance_temporary(step)
			body.flight_segment_travelled.disconnect(capture)
			var multiplier: float = 1.0 + kills * card.bonus_per_level
			var expected: float = body._settings.coast_distance(energy, sample.seconds) * body._settings.orbit_speed_ratio * multiplier
			check(body.orbiting and absf(sample.distance - expected) < 0.003, "Real orbit distance includes first-rank haste at %d stacks and %.4f-second steps" % [kills, step])
			check(absf(body.flight_speed - body._settings.speed_after_coast(energy, sample.seconds)) < 0.002, "Haste increases displacement without refilling or double-consuming remaining energy")
			print("Orbit haste sample: stacks=%d multiplier=%.2f distance=%.4f seconds=%.4f" % [kills, multiplier, sample.distance, sample.seconds])
	clear_enemies()
	mods.reset()
	await reset()

func compare_haste_flight(route: AimPathData) -> void:
	var expected: Vector3 = route.segments.back().end
	var reserve := body.flight_speed
	check(body.release_charge(), "Haste flight can launch")
	reserve = body.flight_speed
	check(is_equal_approx(body.movement_speed, reserve * 1.2), "A fresh launch applies haste live instead of baking it into energy")
	for frame in 1200:
		if not body.flying: break
		body.advance(1.0 / 120.0, Vector3.ZERO, false)
		session.combat_modifiers.advance_temporary(1.0 / 120.0)
	check(TerrainPath.horizontal_distance(player.global_position, expected) < 0.07, "Prediction and actual motion agree when haste expires during flight")

func target_checks() -> void:
	pass
