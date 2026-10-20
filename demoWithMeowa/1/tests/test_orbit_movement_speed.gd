extends "res://tests/test_crowd_deflection.gd"

var motion_records: Array[Dictionary] = []

func path_checks() -> void:
	var settings: PlayerRicochetRules = load("res://data/combat/scenes/world/player/body_ricochet.tres").duplicate()
	var world_time := Engine.time_scale
	check("orbit_speed_ratio" in settings and "movement_speed" in body, "Orbit movement speed is independent of the remaining ricochet speed")
	if not "orbit_speed_ratio" in settings or not "movement_speed" in body: return
	check(is_equal_approx(settings.get("orbit_speed_ratio"), 0.7), "World enables seventy-percent orbit movement")
	check(is_equal_approx(PlayerRicochetRules.new().get("orbit_speed_ratio"), 1.0), "Other scenes retain their authored movement by default")
	for property in ["orbit_speed_ratio", "orbit_enter_seconds", "orbit_exit_seconds"]:
		var invalid: PlayerRicochetRules = settings.duplicate()
		invalid.set(property, NAN)
		check(not invalid.validation_error().is_empty(), "Non-finite orbit speed settings are rejected")
	terrain.data.resize(Vector2i(-16, -16), Vector2i(32, 32))
	player.ricochet_rules = settings
	settings.minimum_launch_speed = 12.0
	settings.maximum_launch_speed = 12.0
	settings.flight_deceleration = 0.5
	player.sword.rules.enabled = false
	body.flight_segment_travelled.connect(func(start, end, _heading, seconds):
		motion_records.append({"distance":TerrainPath.horizontal_distance(start, end), "seconds":seconds, "timing":body.motion_timing(seconds)}))
	for step in [1.0 / 30.0, 1.0 / 120.0]:
		await enter_orbit(step)
		var reserve := body.flight_speed
		var clock := body.flight_elapsed
		body.advance(step, Vector3.ZERO, false)
		check(body.movement_speed / body.flight_speed < 1.0 and body.movement_speed / body.flight_speed > 0.7, "Orbit entry slows gradually instead of jumping immediately")
		for frame in ceili(0.2 / step): body.advance(step, Vector3.ZERO, false)
		check(body.orbiting and is_equal_approx(body.movement_speed / body.flight_speed, 0.7), "The settled orbit uses exactly seventy percent of remaining speed")
		check(absf(body.flight_speed - (reserve - settings.flight_deceleration * (body.flight_elapsed - clock))) < 0.002, "Entry slowdown neither deducts energy nor extends the coast clock")
		motion_records.clear()
		reserve = body.flight_speed
		for frame in ceili(0.3 / step): body.advance(step, Vector3.ZERO, false)
		var seconds := 0.0
		var distance := 0.0
		var timing_matches := true
		for piece in motion_records:
			seconds += piece.seconds
			distance += piece.distance
			timing_matches = timing_matches and absf(piece.distance - (piece.timing.x * piece.seconds - 0.5 * piece.timing.y * piece.seconds * piece.seconds)) < 0.0005
		check(absf(seconds - ceili(0.3 / step) * step) < 0.002 and absf(distance - settings.coast_distance(reserve, seconds) * 0.7) < 0.003, "Orbit displacement is scaled while the full elapsed time still drains energy")
		check(timing_matches and body.crowd_deflection_count == 1, "Sword and trail motion timing matches real segments; continuation does not charge another collision")
		var frozen_position := player.global_position
		var frozen_speed: float = body.movement_speed
		session.set_combat_frozen(true)
		body.advance(0.5, Vector3.ZERO, false)
		check(player.global_position == frozen_position and body.movement_speed == frozen_speed, "Upgrade freeze also freezes the speed transition")
		session.set_combat_frozen(false)
		reserve = body.flight_speed
		clock = body.flight_elapsed
		body.detach_from_crowd()
		check(not body.orbiting and is_equal_approx(body.movement_speed / body.flight_speed, 0.7), "Detaching preserves the current motion speed before smooth recovery")
		body.advance(step, Vector3.ZERO, false)
		check(body.movement_speed / body.flight_speed > 0.7 and body.movement_speed / body.flight_speed < 1.0, "Exit recovers speed gradually")
		for frame in ceili(0.15 / step): body.advance(step, Vector3.ZERO, false)
		check(is_equal_approx(body.movement_speed, body.flight_speed) and absf(body.flight_speed - (reserve - settings.flight_deceleration * (body.flight_elapsed - clock))) < 0.002, "Exit restores the current remaining speed, not the original entry speed")
		body.advance(step, Vector3.RIGHT, false, 1)
		check(not body.flying and is_zero_approx(body.movement_speed) and body.state == PlayerRicochet.State.IDLE, "Movement-key cancellation still hands control back immediately")
		await clear()
	await enter_orbit(1.0 / 60.0)
	for frame in 20: body.advance(1.0 / 60.0, Vector3.ZERO, false)
	for actor in session.enemies: actor.dead = true
	for frame in 20: body.advance(1.0 / 60.0, Vector3.ZERO, false)
	check(body.flying and not body.orbiting and is_equal_approx(body.movement_speed, body.flight_speed), "Losing the whole group also releases the speed reduction")
	await clear()
	await preview_checks()
	await wall_checks()
	await attack_checks()
	check(is_equal_approx(Engine.time_scale, world_time), "Orbit movement scaling does not change world time or attack time")

func enter_orbit(step: float) -> void:
	group(Vector3(3, 0, 0), 5, 5)
	await reset()
	check(body.begin_charge(Vector3.RIGHT), "The orbit fixture can charge")
	body.advance(0.8, Vector3.ZERO, false)
	check(body.release_charge(), "The orbit fixture launches")
	check(is_equal_approx(body.movement_speed, body.flight_speed), "Every new launch starts with full remaining speed")
	for frame in 240:
		if body.orbiting or not body.flying: break
		body.advance(step, Vector3.ZERO, false)
	check(body.orbiting, "The real player captures the actual group contour")

func preview_checks() -> void:
	var settings := player.ricochet_rules
	settings.minimum_launch_speed = 2.7
	settings.maximum_launch_speed = 2.7
	group(Vector3(3, 0, 0), 5, 5)
	await reset()
	check(body.begin_charge(Vector3.RIGHT), "Low-energy preview can begin charging")
	body.advance(0.8, Vector3.ZERO, false)
	var route := AimPathData.new()
	var before := player.global_transform
	body.predict_path(query, route, 8.0, 1, 0.9)
	check(player.global_transform == before and route.crowd_contacts.size() == 1, "Slowed first-response prediction remains read-only and captures the same group")
	check(body.release_charge(), "Low-energy preview can launch")
	for frame in 600:
		if not body.flying: break
		body.advance(1.0 / 120.0, Vector3.ZERO, false)
	check(not body.flying and TerrainPath.horizontal_distance(player.global_position, route.segments.back().end) < 0.03, "Short-tail energy depletion agrees with the actual slowed route")
	settings.minimum_launch_speed = 12.0
	settings.maximum_launch_speed = 12.0
	await clear()
	settings.eccentric_enabled = false
	group(Vector3(3, 0, 0), 5, 5)
	await reset()
	body.begin_charge(Vector3.RIGHT)
	body.advance(0.8, Vector3.ZERO, false)
	body.release_charge()
	for frame in 120:
		if body.crowd_deflection_count > 0 or not body.flying: break
		body.advance(1.0 / 120.0, Vector3.ZERO, false)
	check(body.crowd_deflection_count == 1 and not body.orbiting and is_equal_approx(body.movement_speed, body.flight_speed), "Ordinary contact arcs retain their original speed")
	settings.eccentric_enabled = true
	await clear()

func wall_checks() -> void:
	await enter_orbit(1.0 / 120.0)
	for frame in 30: body.advance(1.0 / 120.0, Vector3.ZERO, false)
	var heading := body.direction
	var wall := box(player.global_position + heading * 0.6, Vector3(0.08, 3, 5), atan2(-heading.z, heading.x))
	await physics_frame
	var reserve := body.flight_speed
	var clock := body.flight_elapsed
	var impact_budget := [0.0]
	var capture := func(_impact): impact_budget[0] = body.flight_speed
	body.impact_recorded.connect(capture)
	for frame in 120:
		if body.bounce_count > 0 or not body.flying: break
		body.advance(1.0 / 120.0, Vector3.ZERO, false)
	check(body.bounce_count == 1, "A real wall interrupts the slowed orbit")
	if body.last_impact:
		var before := reserve - body._settings.flight_deceleration * (body.last_impact.seconds - clock)
		check(absf(impact_budget[0] - body._settings.rebound_speed(before, body._settings.bounce_speed_retention)) < 0.002, "Wall collisions retain the original stored-speed cost")
	body.impact_recorded.disconnect(capture)
	wall.queue_free()
	await clear()

func attack_checks() -> void:
	var storm: RicochetStorm = load("res://scenes/combat/ricochet_storm.tscn").instantiate()
	storm.session = session
	storm.audio_enabled = false
	world.add_child(storm)
	session._path_ready = true
	session._path = navigation
	session.combat_modifiers.damage_disabled = true
	player.sword.rules.enabled = true
	var sword_hits := [0]
	var hit := func(_enemy, _damage, flying):
		if flying: sword_hits[0] += 1
	player.sword.hit_landed.connect(hit)
	var hits := {}
	var rounds := [0]
	storm.discharge_started.connect(func(_point): rounds[0] += 1)
	storm.hit_landed.connect(func(actor, _damage): hits[actor.get_instance_id()] = int(hits.get(actor.get_instance_id(), 0)) + 1)
	check(storm.apply_skill_level(1), "The fixture carries level-one storm without range growth")
	storm.set_physics_process(false)
	await enter_orbit(1.0 / 120.0)
	for actor in session.enemies: actor.health_loss_disabled = true
	for frame in 300:
		body.advance(1.0 / 120.0, Vector3.ZERO, false)
		player.sword._physics_process(1.0 / 120.0)
		storm._physics_process(1.0 / 120.0)
	check(sword_hits[0] > 0 and not hits.is_empty() and rounds[0] > 1, "Slower orbit still triggers real sword hits and repeated storm rounds")
	check(hits.values().all(func(count): return count <= rounds[0]), "Storm keeps per-round target deduplication")
	player.sword.hit_landed.disconnect(hit)
	storm.queue_free()
	player.sword.rules.enabled = false
	session.combat_modifiers.damage_disabled = false
	await clear()

func target_checks() -> void:
	pass
