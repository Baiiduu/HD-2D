extends "res://tests/test_kill_camera_balance.gd"

func hit_target(source: StringName = &"basic_sword", simulated := false, damage := 1.0) -> SlimeEnemy:
	var enemy := spawn("wave_slime", Vector3.RIGHT * 1.5, 100.0)
	enemy.health_loss_disabled = simulated
	session.enemy_spawned.emit(enemy)
	enemy.take_damage(damage, {"source":source, "direction":Vector3.RIGHT})
	impact.set_process(false)
	return enemy

func run() -> void:
	await setup()
	var previous := player.movement_camera
	camera = FollowCamera.new()
	camera.target = player
	camera.distance = 25.0
	camera.pitch_degrees = 30.627
	camera.yaw_degrees = 135.0
	camera.fov = 28.0
	world.add_child(camera)
	player.movement_camera = camera
	previous.free()
	camera.set_process(false)
	impact = load("res://scripts/world/hit_impact_presentation.gd").new()
	impact.session = session
	world.add_child(impact)
	impact.set_process(false)
	var visuals := player.action_visuals
	var enemy := hit_target()
	check(Engine.time_scale < 0.01 and camera.hit_stop_active, "A real nonlethal basic sword hit immediately gives a short hold")
	check(visuals.get("sword_hit_impact_enabled") and not PlayerActionVisuals.new().get("sword_hit_impact_enabled") and not load("res://data/combat/scenes/city/player/action_visuals.tres").get("sword_hit_impact_enabled"), "World opts into basic hit impacts without enabling City or shared defaults")
	impact.advance(0.012)
	var age: float = impact.get("_age")
	var remaining: float = impact.stop_remaining
	var beat_count: int = impact.beats
	for index in 4: hit_target()
	check(impact.beats == beat_count and is_equal_approx(float(impact.get("_age")), age) and is_equal_approx(impact.stop_remaining, remaining), "One sweep hitting many living monsters neither restarts nor extends the hold")
	check(not camera.hit_shake_offset.is_zero_approx() and camera.hit_shot_distance_scale == 1.0 and camera.hit_shot_weight == 0.0, "A basic hit adds light curve shake without zoom or focus pull")
	check(enemy.health == 99.0 and impact.slashes.emitted == 0 and int(impact.get("_group_count")) == 0, "Basic hit impact changes no damage and manufactures neither death slash nor group kills")
	impact.advance(0.04)
	check(Engine.time_scale == 1.0 and not camera.hit_stop_active, "The light hit hold releases directly without a slow-motion tail")
	hit_target()
	check(impact.beats == beat_count, "Rapid repeated basic hits respect the shared light-hit interval")
	impact.advance(0.35)
	hit_target()
	check(impact.beats == beat_count + 1 and Engine.time_scale < 0.01, "A later real basic hit can produce another bounded impact")
	impact.clear()
	hit_target()
	impact.advance(0.012)
	age = impact.get("_age")
	beat_count = impact.beats
	emit_kill()
	check(impact.beats == beat_count and is_equal_approx(float(impact.get("_age")), age) and impact.stop_remaining > 0.05, "An immediate lethal follow-up upgrades the same beat without consuming or restarting the kill opportunity")
	emit_kill(&"basic_sword")
	emit_kill(&"ricochet_storm")
	impact.advance(0.04)
	check(camera.hit_shot_distance_scale < 1.0 and Engine.time_scale < 0.01, "A light hit cannot block the independent group camera or the stronger lethal hold")
	impact.advance(0.8)
	beat_count = impact.beats
	hit_target()
	check(impact.beats == beat_count and Engine.time_scale == 1.0, "Ordinary hits do not insert extra shakes during the lethal beat cooldown")
	impact.clear()
	for source in [&"flight_sword", &"ricochet_storm", &"A02"]: hit_target(source)
	hit_target(&"basic_sword", true)
	hit_target(&"basic_sword", false, 0.0)
	check(Engine.time_scale == 1.0 and not camera.hit_shot_active, "Flight hits, storm hits, simulation and zero damage do not inherit basic-hit world holds")
	impact.clear()
	visuals.set("kill_impact_enabled", false)
	hit_target()
	impact.advance(0.012)
	check(Engine.time_scale < 0.01 and camera.hit_stop_active, "Basic-hit presentation works independently of the kill impact switch")
	visuals.set("sword_hit_impact_enabled", false)
	impact.advance(0.0)
	check(Engine.time_scale == 1.0 and not camera.hit_shot_active, "Disabling the light-hit feature immediately returns its camera and time ownership")
	visuals.set("sword_hit_impact_enabled", true)
	visuals.set("kill_impact_enabled", true)
	impact.clear()
	Engine.time_scale = 0.5
	hit_target()
	impact.advance(0.06)
	check(Engine.time_scale == 0.5, "A light hit restores a pre-existing time baseline exactly")
	Engine.time_scale = 1.0
	impact.clear()
	hit_target()
	session.set_combat_frozen(true)
	check(Engine.time_scale == 1.0 and not camera.hit_shot_active, "Upgrade freeze cancels the light hit immediately")
	session.set_combat_frozen(false)
	impact.clear()
	camera.wave_shot_active = true
	hit_target()
	check(Engine.time_scale == 1.0 and not camera.hit_shot_active, "Wave-final cinematics suppress ordinary hit holds")
	camera.wave_shot_active = false
	var blocker := Node.new()
	world.add_child(blocker)
	blocker.add_to_group(&"gameplay_input_blockers")
	hit_target()
	check(Engine.time_scale == 1.0 and not camera.hit_shot_active, "Management input ownership suppresses ordinary hit holds")
	blocker.free()
	impact.clear()
	hit_target()
	impact.free()
	check(Engine.time_scale == 1.0 and not camera.hit_shot_active, "Scene cleanup restores the light-hit baseline")
	var actor := Player.new()
	actor.action_visuals = visuals
	var parameters: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(actor)
	for property in ["sword_hit_impact_enabled", "sword_hitstop_seconds", "sword_hit_impact_interval", "sword_hit_shake_seconds", "sword_hit_shake_pixels"]:
		check(parameters.any(func(item): return item.property == property and item.common and item.label != property), "Chinese parameter overview exposes " + property)
	actor.free()
	world.queue_free()
	await settle(4)
	print("Sword hit impact: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
