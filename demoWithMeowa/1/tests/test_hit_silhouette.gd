extends "res://tests/test_enemy_hit_reaction.gd"

func amount(subject: GeometryInstance3D) -> float:
	var value: Variant = subject.get_instance_shader_parameter(&"hit_silhouette_amount")
	return float(value) if value != null else 0.0

func run() -> void:
	var visuals: PlayerActionVisuals = load("res://data/combat/scenes/world/player/action_visuals.tres")
	check(visuals.get("enemy_hit_silhouette_enabled") == false, "World retracts the high-contrast local flight-hit silhouette")
	if failures:
		print("Hit silhouette: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	check(load("res://data/combat/scenes/city/player/action_visuals.tres").get("enemy_hit_silhouette_enabled") == false, "City retains its original hit presentation")
	var scene := Player.new()
	scene.action_visuals = visuals
	var entries: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(scene)
	for property in ["enemy_hit_silhouette_enabled", "enemy_hit_silhouette_seconds", "enemy_hit_silhouette_strength", "enemy_hit_silhouette_interval", "enemy_hit_silhouette_color"]:
		check(entries.any(func(item): return item.property == property and item.common and item.label != property), "Parameter overview exposes the local silhouette setting: " + property)
	scene.free()
	await setup()
	var unaltered := spawn("wave_slime", Vector3(2, 0, 0), 100.0)
	unaltered.take_damage(1.0, {"source":&"flight_sword", "direction":Vector3.RIGHT})
	check(is_zero_approx(amount(unaltered.sprite)) and unaltered.health == 99.0, "Formal flight hits retain the native monster colors and real damage")
	unaltered.cancel()
	session.enemies.erase(unaltered)
	# 原型开关仍可独立使用，但正式地图不再启用。
	player.action_visuals.enemy_hit_silhouette_enabled = true
	for id in ["wave_slime", "leaf_charger", "lantern_spitter", "pot_brood", "bell_frog", "mini_slime"]:
		var enemy := spawn(id, Vector3(2, 0, 0), 100.0)
		var original := enemy.global_transform
		var original_texture := enemy.sprite.texture
		enemy.take_damage(1.0, {"source":&"flight_sword", "direction":Vector3.RIGHT})
		check(amount(enemy.sprite) > 0.8, id + " real flight sword hit immediately emphasizes this target")
		check(enemy.health == 99.0 and enemy.global_transform == original and enemy.sprite.texture == original_texture, id + " silhouette preserves damage, position and native animation frame")
		enemy.sprite._process(0.04)
		enemy.take_damage(1.0, {"source":&"ricochet_storm"})
		enemy.sprite._process(0.13)
		check(is_zero_approx(amount(enemy.sprite)), id + " rapid sword/storm hits merge instead of indefinitely prolonging the flash")
		enemy.sprite._process(0.08)
		enemy.take_damage(1.0, {"source":&"ricochet_storm"})
		check(amount(enemy.sprite) > 0.8, id + " a later real storm hit can emphasize the target again")
		enemy.cancel()
		check(is_zero_approx(amount(enemy.sprite)), id + " cancellation clears instance appearance")
		session.enemies.erase(enemy)
	await settle(1)
	var first := spawn("wave_slime", Vector3(2, 0, 0), 100.0)
	var second := spawn("wave_slime", Vector3(3, 0, 0), 100.0)
	first.take_damage(1.0, {"source":&"flight_sword"})
	second.take_damage(1.0, {"source":&"basic_sword"})
	first._process(0.0)
	second._process(0.0)
	first.sprite._process(0.0)
	second.sprite._process(0.0)
	check(first.sprite.material_override == second.sprite.material_override, "Hit targets keep sharing their existing material")
	check(amount(first.sprite) > 0.0 and is_zero_approx(amount(second.sprite)) and is_zero_approx(amount(player.sprite)), "Local silhouettes do not recolor companions or the player")
	check(Engine.time_scale == 1.0 and not paused, "Ordinary hit silhouettes never slow or pause the world")
	session.register_combat_node(first)
	session.set_combat_frozen(true)
	var saved := amount(first.sprite)
	first.sprite._process(0.2)
	check(is_equal_approx(amount(first.sprite), saved), "Upgrade freeze preserves the local pulse")
	session.set_combat_frozen(false)
	Engine.time_scale = 0.2
	first.sprite._process(0.034)
	check(is_zero_approx(amount(first.sprite)), "Pulse lasts the configured real time during other slow-motion effects")
	Engine.time_scale = 1.0
	second.sprite.lighting_enabled = false
	second.sprite.apply_lighting()
	second.take_damage(1.0, {"source":&"flight_sword"})
	check(second.sprite.material_override == second.sprite.get("_material"), "Silhouette works when custom character lighting is disabled")
	second.sprite._process(0.18)
	check(second.sprite.material_override == second.sprite.get("_original_material"), "Unlit target restores its previous material after the pulse")
	for enemy in [first, second]:
		enemy.cancel()
		session.enemies.erase(enemy)
	await settle(1)
	var lethal := spawn("wave_slime", Vector3(1, 0, 0), 1.0)
	var effect := kill(lethal, &"flight_sword", Vector3.RIGHT)
	check(lethal.dead and effect != null and amount(effect.get_focus_subject()) > 0.0, "Lethal flight hit transfers the silhouette to the real death snapshot")
	if effect:
		effect.get_focus_subject().set_instance_shader_parameter(&"wave_finish_silhouette", 0.8)
		effect._process(0.18)
		check(is_zero_approx(amount(effect.get_focus_subject())) and is_equal_approx(effect.get_focus_subject().get_instance_shader_parameter(&"wave_finish_silhouette"), 0.8), "Short local pulse cannot clear the independent three-second wave-finish silhouette")
		effect.stop()
		check(is_zero_approx(amount(effect.get_focus_subject())), "Pooled death object clears the local pulse")
	clear_effects()
	await settle(1)
	var sword_target := spawn("wave_slime", Vector3(0.5, 0, -0.5), 100.0)
	var sword_events: Array[CombatDamageEvent] = []
	sword_target.damaged.connect(func(event): sword_events.append(event))
	player.sword_rules = PlayerSwordRules.new()
	var sword := PlayerSword.new()
	player.sword = sword
	player.add_child(sword)
	sword.cancel()
	sword.set_physics_process(false)
	sword._begin(Vector3.FORWARD, true)
	sword._collect_hits(Vector3.ZERO, Vector3.RIGHT, 0.0, 1.0, true, 0.0, 0.1)
	sword._drain_hits()
	check(sword_target.health < 100.0 and amount(sword_target.sprite) > 0.0, "Actual moving sword sweep delivers the local silhouette through its unchanged damage queue")
	check(not sword_events.is_empty() and sword_events[0].get("slash_direction") is Vector3 and not sword_events[0].get("slash_direction").is_zero_approx(), "The actual moving blade publishes its visual sweep direction independently of damage and knockback")
	sword_target.cancel()
	session.enemies.erase(sword_target)
	sword.cancel()
	await settle(1)
	var storm := load("res://scenes/combat/ricochet_storm.tscn").instantiate() as RicochetStorm
	storm.session = session
	storm.audio_enabled = false
	world.add_child(storm)
	storm.apply_skill_level(1)
	session._path_ready = true
	storm.set_physics_process(false)
	var storm_target := spawn("wave_slime", Vector3(1, 0, 0), 100.0)
	check(storm.discharge(Vector3(0, 0.03, 0)) and amount(storm_target.sprite) > 0.0, "Actual storm discharge delivers the same local pulse")
	storm.set_physics_process(false)
	storm.cancel_current()
	storm.queue_free()
	storm_target.cancel()
	session.enemies.erase(storm_target)
	await settle(1)
	var sample := spawn("wave_slime", Vector3(1, 0, 0), 1.0)
	player.action_visuals.set("enemy_hit_silhouette_enabled", false)
	sample.take_damage(0.1, {"source":&"flight_sword"})
	check(is_zero_approx(amount(sample.sprite)), "Independent visual switch disables local silhouettes without blocking damage")
	sample.cancel()
	session.enemies.erase(sample)
	world.queue_free()
	await settle()
	print("Hit silhouette: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
