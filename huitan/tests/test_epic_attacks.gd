extends "res://tests/test_player_sword.gd"

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	terrain = Terrain.new()
	var data := TerrainData.new()
	data.size = Vector2i.ZERO
	data.resize(Vector2i(-12, -12), Vector2i(24, 24))
	terrain.data = data
	world.add_child(terrain)
	session = SESSION.new()
	session.name = "WavePrototype"
	session.terrain = terrain
	session.phase = WavePrototype.Phase.BATTLE
	world.add_child(session)
	session._attack_root = Node3D.new()
	session.add_child(session._attack_root)
	var score := RunScore.new()
	score.name = "RunScore"
	score.session = session
	score.rules = RunScoreRules.new()
	session.add_child(score)
	player = Player.new()
	player.animations = load("res://assets/meowa/player/animations.tres")
	player.action_visuals = PlayerActionVisuals.new()
	player.action_visuals.show_aim_guide = false
	player.ricochet_rules = PlayerRicochetRules.new()
	player.ricochet_rules.minimum_launch_speed = 8.0
	player.ricochet_rules.maximum_launch_speed = 8.0
	player.ricochet_rules.push_radius = 3.0
	player.sword_rules = PlayerSwordRules.new()
	player.sword_rules.audio_enabled = false
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	var shape := CapsuleShape3D.new()
	shape.radius = 0.24
	shape.height = 1.06592
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position.y = shape.height * 0.5
	player.add_child(collision)
	session.player = player
	world.add_child(player)
	sword = player.sword
	sword.strike_started.connect(func(direction, flying, reverse): strikes.append({"direction":direction, "flying":flying, "reverse":reverse}))
	sword.hit_landed.connect(func(enemy, damage, flying): damage_events.append({"enemy":enemy, "damage":damage, "flying":flying}))
	player.body_ricochet.enemy_pushed.connect(func(mob, _heading):
		check(mob.health < mob.max_health, "拨怪发生在真实伤害之后")
		pushes += 1)
	await settle()
	session._path.build(terrain, 0.32, [player.get_rid()])
	player.set_physics_process(false)
	sword.set_physics_process(false)

	session.growth_rules = RunGrowthRules.new()
	session.combat_modifiers.growth_rules = session.growth_rules
	session._survival.rules = session.growth_rules
	var defs: Array[GrowthBuffDefinition] = []
	for name in ["global_range", "speed_damage", "multistrike", "heavy_strike", "omnivamp"]:
		defs.append(load("res://data/combat/scenes/world/growth/epic/" + name + ".tres"))
	check(load("res://data/combat/scenes/world/configuration.tres").validation_error().is_empty(), "Formal growth resources validate")
	var mods := session.combat_modifiers
	mods.apply_buff(defs[2])
	mods.apply_buff(defs[1])
	var mob := enemy(Vector3(1, 0, 0), 10000)
	mob.damaged.connect(session._growth_damage)
	player.current_health = 50
	player.body_ricochet.state = PlayerRicochet.State.FLYING
	player.body_ricochet.flight_speed = 12
	sword._begin(Vector3.RIGHT, true, 12)
	var snapshot: CombatAttackSnapshot = sword._stats.attack_snapshot
	var root_duration := sword._settings.duration() * snapshot.strikes
	var hit_damage: float = sword._stats.damage
	check(snapshot.strikes == 4 and snapshot.remaining_speed == 12, "A flight sword snapshots four true slashes at speed twelve")
	var before := mob.health
	# Changing energy after root start cannot change its damage or strike count.
	player.body_ricochet.flight_speed = 4
	sword._simulate(player.global_position, player.global_position, root_duration + 0.00001, true, Vector3.RIGHT)
	sword._drain_hits()
	check(is_equal_approx(before - mob.health, hit_damage * 2), "Three real additional slashes total one base slash, keeping first-card gain within 100 percent")
	check(is_equal_approx(player.current_health, 51.5), "Four repeated slashes grant one baseline recovery")
	check(not sword.swinging, "Repeats complete within the root motion duration")
	sword._begin(Vector3.RIGHT, true, 4)
	check(sword._stats.attack_snapshot.strikes == 2 and sword._stats.damage < hit_damage, "Next attack reads reduced energy")
	var age: float = sword._age
	session.set_combat_frozen(true)
	sword._physics_process(0.4)
	check(sword._age == age, "Upgrade freeze preserves a pending multistrike")
	session.set_combat_frozen(false)
	sword.cancel()
	check(sword._strike_total == 1 and sword._pending_hits.is_empty(), "Cancel clears pending repeats and contacts")
	var wall := box(Vector3(0.5, 0.6, 0), Vector3(0.05, 1.2, 4))
	await settle()
	sword._begin(Vector3.RIGHT, true, 12)
	before = mob.health
	sword._simulate(player.global_position, player.global_position, 0.3, true, Vector3.RIGHT)
	sword._drain_hits()
	check(mob.health == before, "Every repeat obeys a real wall")
	wall.free()
	await settle()
	sword.cancel()
	player.body_ricochet.cancel(true)
	mods.reset()
	var rules := player.ricochet_rules
	rules.eccentric_enabled = true
	rules.eccentric_minimum_members = 1
	var edge_clearance := rules.eccentric_edge_clearance
	var crowd := PlayerCrowdDeflection.new(rules, session)
	var original_radius := crowd.capture_radius()
	mods.apply_buff(defs[0])
	var radius := crowd.capture_radius()
	check(radius > original_radius and radius > sword.get_stats(true).range, "Capture precedes enlarged flight sword reach")
	var prediction := PlayerCrowdDeflection.new(rules, session, null, preload("res://scripts/combat/preview_spatial_query_view.gd").new(session._spatial_index, session))
	check(is_equal_approx(radius, prediction.capture_radius()), "Prediction and movement use one capture radius")
	check(rules.eccentric_edge_clearance == edge_clearance, "Range never enlarges physical orbit spacing")
	var contact := crowd.contact(Vector3(-4, 0.03, 0), Vector3(1, 0.03, 0), Vector3.RIGHT)
	check(not contact.is_empty(), "Enlarged capture finds a living group before enlarged sword contact")
	if not contact.is_empty():
		var point := Vector3(-4, 0.03, 0).lerp(Vector3(1, 0.03, 0), contact.entry)
		check(crowd.begin_contact(contact, point, Vector3.RIGHT) and crowd.orbiting, "Early capture still builds the real close outer-edge orbit")
	mods.apply_buff(defs[3])
	var duration_before: float = sword.get_stats(true).interval
	mods.apply_buff(load("res://data/combat/scenes/world/growth/cooldown.tres"))
	check(sword.get_stats(true).interval < duration_before, "Global attack speed offsets heavy-strike cadence for sword")
	mods.reset()
	mods.apply_buff(defs[4])
	session._survival.reset()
	player.current_health = 50
	mob.take_damage(10, {"source": &"A02"})
	check(is_equal_approx(player.current_health, 50.3), "Real non-sword damage feeds the shared omnivamp event")
	mob.health_loss_disabled = true
	mob.take_damage(100, {"source": &"A02"})
	check(is_equal_approx(player.current_health, 50.3), "Simulated hits cannot restore life")
	mob.health_loss_disabled = false
	mob.health = 3000
	player.current_health = 10
	mob.take_damage(1000, {"source": &"A02"})
	check(is_equal_approx(player.current_health, 40.0), "A real large hit heals beyond the former omnivamp-per-second limit")
	mob.take_damage(1000, {"source": &"A02"})
	check(is_equal_approx(player.current_health, 70.0), "A second immediate real hit still grants full lifesteal without advancing time")
	var fragile := enemy(Vector3(1, 0, 0), 5)
	fragile.damaged.connect(session._growth_damage)
	session._survival.reset()
	player.current_health = 50
	fragile.take_damage(1000, {"source": &"A02"})
	check(is_equal_approx(player.current_health, 50.15), "Overkill heals only from the target's five real lost health")
	mods.reset()
	mods.apply_buff(defs[2])
	sword._begin(Vector3.RIGHT, false)
	check(sword._stats.attack_snapshot.strikes == 1, "Thousand hands never duplicates ordinary sword attacks")
	var buffs := RunBuffs.new()
	buffs.session = session
	session.growth_rules.maximum_strikes = 2
	check(not buffs._has_effect(defs[2]), "A configured strike cap filters upgrades with no actual extra slash")
	session.growth_rules.maximum_strikes = 8
	session.growth_rules.additional_strike_damage_ratio = 0
	check(not buffs._has_effect(defs[2]), "Zero-damage additional slashes do not create an ineffective card")
	buffs.free()
	for enemy in session.enemies: enemy.cancel()
	session.enemies.clear()
	world.queue_free()
	await settle()
	print("Epic attack integration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
