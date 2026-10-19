extends "res://tests/test_aim_path_preview.gd"

var prism: PrismRicochetAutoAttack

func clear_case() -> void:
	prism.cancel_current()
	clear_enemies()
	await settle()

func target_checks() -> void:
	pass

func path_checks() -> void:
	session._path = navigation
	session._path_ready = true
	player.sword.rules.enabled = false
	prism = load("res://scenes/combat/prism_ricochet_auto_attack.tscn").instantiate()
	prism.session = session
	prism.audio_enabled = false
	world.add_child(prism)
	prism.apply_skill_level(1)
	prism.set_physics_process(false)
	var stats := prism.get_attack_stats()
	var front := enemy(Vector3(2, 0, 0))
	var behind := enemy(Vector3(4, 0, 0))
	front.health = 1000
	behind.health = 1000
	await settle()
	prism.launch(Vector3.ZERO, Vector3.RIGHT, stats)
	var shot: Dictionary = prism._shots[-1]
	prism._advance_shot(shot, 0.25)
	check(shot.bounces == 1 and shot.direction.x < -0.99 and shot.position.x < front.position.x, "Front monster reflects the crystal at its body instead of allowing penetration")
	check(is_equal_approx(front.health, 1000 - stats.damage) and behind.health == 1000, "Only the first monster receives damage before reflection")
	prism._advance_shot(shot, 0.02)
	check(is_equal_approx(front.health, 1000 - stats.damage) and shot.bounces == 1, "Leaving a body does not repeat damage or spend extra bounces")
	await clear_case()
	front = enemy(Vector3(2, 0, 0.2))
	front.health = 1000
	await settle()
	prism.launch(Vector3.ZERO, Vector3.RIGHT, stats)
	shot = prism._shots[-1]
	prism._advance_shot(shot, 0.25)
	check(shot.bounces == 1 and shot.direction.z < -0.1 and is_zero_approx(shot.direction.y), "Grazing a capsule uses its actual curved normal projected to the ground")
	var coarse_position: Vector3 = shot.position
	prism.cancel_current()
	front.health = 1000
	prism.launch(Vector3.ZERO, Vector3.RIGHT, stats)
	shot = prism._shots[-1]
	for index in 25: prism._advance_shot(shot, 0.01)
	check(shot.position.distance_to(coarse_position) < 0.06 and shot.bounces == 1 and is_equal_approx(front.health, 1000 - stats.damage), "Frame partition preserves contact, damage and the remaining reflected travel")
	await clear_case()
	front = enemy(Vector3(2, 0, 0))
	front.health = 1000
	var wall := box(Vector3(-1, 0.6, 0), Vector3(0.02, 1.2, 6))
	await settle()
	prism.launch(Vector3.ZERO, Vector3.RIGHT, stats)
	shot = prism._shots[-1]
	prism._advance_shot(shot, 1.0)
	check(prism._shots.is_empty() and shot.bounces == 2, "Monster and wall share one finite bounce budget in a long frame")
	check(is_equal_approx(front.health, 1000 - stats.damage * 2), "A real wall return may hit the previous monster once again")
	wall.free()
	await clear_case()
	front = enemy(Vector3(2, 0, 0))
	behind = enemy(Vector3(4, 0, 0))
	front.health = 1000
	behind.health = 1000
	await settle()
	var capped := stats.duplicate()
	capped.bounces = 0
	prism.launch(Vector3.ZERO, Vector3.RIGHT, capped)
	shot = prism._shots[-1]
	prism._advance_shot(shot, 0.5)
	check(prism._shots.is_empty() and shot.bounces == 0 and is_equal_approx(front.health, 1000 - stats.damage) and behind.health == 1000, "Exhausted budget applies the final contact and stops without piercing")
	prism.launch(front.global_position, Vector3.RIGHT, stats)
	shot = prism._shots[-1]
	var health := front.health
	prism._advance_shot(shot, 0.2)
	check(is_equal_approx(front.health, health - stats.damage) and shot.bounces <= stats.bounces, "Starting inside a body cannot create repeated damage or an unbounded collision loop")
	await clear_case()
	front = enemy(Vector3(2, 0, 0))
	front.health = 1
	behind = enemy(Vector3(4, 0, 0))
	behind.health = 1000
	await settle()
	prism.launch(Vector3.ZERO, Vector3.RIGHT, stats)
	shot = prism._shots[-1]
	prism._advance_shot(shot, 0.3)
	check(front.dead and shot.bounces == 1 and shot.direction.x < -0.99 and behind.health == 1000, "A lethal hit still reflects from the captured body contact")
	await clear_case()
	front = enemy(Vector3(2, 0, 0))
	front.health = 1000
	front.damaged.connect(func(_event): session.set_combat_frozen(true), CONNECT_ONE_SHOT)
	await settle()
	prism.launch(Vector3.ZERO, Vector3.RIGHT, stats)
	shot = prism._shots[-1]
	prism._advance_shot(shot, 0.25)
	check(session.combat_frozen and shot.bounces == 1 and shot.direction.x < -0.99, "An upgrade freeze triggered by damage cannot discard the pending reflection")
	session.set_combat_frozen(false)
	prism.set_physics_process(false)
	prism._advance_shot(shot, 0.02)
	check(is_equal_approx(front.health, 1000 - stats.damage) and shot.bounces == 1, "Resuming after a hit freeze continues outward without duplicate damage")
	await clear_case()
