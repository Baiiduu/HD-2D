extends "res://tests/test_enemy_hit_reaction.gd"

class SlashProbe extends "res://scripts/enemies/kill_slash.gd":
	var center := Vector3.ZERO
	var heading := Vector3.ZERO
	func burst(point: Vector3, direction: Vector3, pixel: float, camera: Camera3D, settings: PlayerActionVisuals) -> void:
		center = point
		heading = direction
		super.burst(point, direction, pixel, camera, settings)

var impact: Node3D

func watched(point: Vector3, health := 100.0) -> SlimeEnemy:
	var enemy := spawn("wave_slime", point, health)
	session.enemy_spawned.emit(enemy)
	return enemy

func run() -> void:
	var visuals: PlayerActionVisuals = load("res://data/combat/scenes/world/player/action_visuals.tres")
	check(visuals.get("hit_debris_enabled") == true and visuals.get("kill_impact_enabled") == true, "World independently enables hit debris and the combined kill beat")
	check(not visuals.enemy_hit_silhouette_enabled, "World hit presentation retains the monster's native colors")
	check(visuals.hit_debris_count >= 14 and float(visuals.get("hit_debris_speed_multiplier")) >= 2.0, "World emits denser, faster native debris")
	check(visuals.get("kill_slash_enabled") == true, "World independently enables the directional death slash")
	check(visuals.get("kill_shot_enabled") == true and visuals.kill_hitstop_seconds >= 0.09, "World enables group framing independently of its visible kill hold")
	if failures:
		print("Hit impact: %d checks, %d failures" % [checks, failures])
		quit(1)
		return
	check(load("res://data/combat/scenes/city/player/action_visuals.tres").get("kill_impact_enabled") == false, "City retains its independent presentation")
	check(not load("res://data/combat/scenes/city/player/action_visuals.tres").kill_slash_enabled, "The death slash does not implicitly enable itself in City")
	var scene := Player.new()
	scene.action_visuals = visuals
	var parameters: Array[Dictionary] = preload("res://addons/parameter_hub/catalog.gd").new().collect(scene)
	for property in ["hit_debris_enabled", "hit_debris_count", "hit_debris_seconds", "hit_debris_interval", "hit_debris_speed_multiplier", "kill_slash_enabled", "kill_slash_seconds", "kill_slash_interval", "kill_impact_enabled", "kill_hitstop_seconds", "kill_slow_tail_seconds", "kill_hitstop_interval", "kill_shake_seconds", "kill_shake_pixels", "kill_shot_enabled", "kill_shot_seconds", "kill_shot_zoom_scale", "kill_shot_minimum_kills", "kill_shot_group_window", "kill_shot_enter_seconds", "kill_shot_interval"]:
		check(parameters.any(func(item): return item.property == property and item.common and item.label != property), "Chinese parameter overview exposes " + property)
	scene.free()
	await setup()
	# 本用例隔离击杀反馈；普通非致死命中的轻反馈由 test_sword_hit_impact 覆盖。
	player.action_visuals.sword_hit_impact_enabled = false
	var old_camera := player.movement_camera
	var camera := FollowCamera.new()
	camera.target = player
	camera.distance = 25.0
	camera.pitch_degrees = 30.627
	camera.yaw_degrees = 135.0
	camera.fov = 28.0
	world.add_child(camera)
	player.movement_camera = camera
	old_camera.free()
	camera.set_process(false)
	impact = load("res://scripts/world/hit_impact_presentation.gd").new()
	impact.session = session
	world.add_child(impact)
	impact.slashes.free()
	var probe := SlashProbe.new()
	impact.slashes = probe
	impact.add_child(probe)
	impact.set_process(false)
	var first := watched(Vector3.RIGHT * 2.0)
	seed(419)
	var expected_random := randi()
	seed(419)
	first.take_damage(1.0, {"source":&"basic_sword", "direction":Vector3.RIGHT})
	check(randi() == expected_random, "Visual debris does not consume the spawn and growth random stream")
	check(impact.debris.emitted == visuals.hit_debris_count and impact.debris.visible, "A real nonlethal sword hit emits one native pixel debris burst")
	var directed := true
	for index in 50:
		var velocity: Vector3 = impact.debris.launch_velocity(Vector3.RIGHT, visuals.hit_debris_speed_multiplier)
		directed = directed and velocity.x > 0.0 and velocity.y > 0.0 and velocity.length() > 3.5 and velocity.length() < 10.0
	check(directed, "Debris has varied directed horizontal velocity and an upward ballistic launch")
	check(Engine.time_scale == 1.0 and not paused, "Disabling basic hit impact leaves nonlethal particles independent of world time")
	check(impact.slashes.emitted == 0, "Nonlethal hits do not manufacture a death slash")
	var count: int = impact.debris.emitted
	first.take_damage(1.0, {"source":&"flight_sword", "direction":Vector3.RIGHT})
	check(impact.debris.emitted == count, "Rapid hits on one target share its debris interval")
	impact.advance(0.13)
	first.take_damage(1.0, {"source":&"ricochet_storm", "direction":Vector3.RIGHT})
	check(impact.debris.emitted > count, "Later real storm hits can emit again")
	check(first.health == 97.0 and impact.debris.get_child_count() == 0, "Real damage remains unchanged and debris uses a single batch without particle nodes")
	var simulated := watched(Vector3.FORWARD, 1.0)
	simulated.health_loss_disabled = true
	count = impact.debris.emitted
	simulated.take_damage(999.0, {"source":&"flight_sword", "direction":Vector3.FORWARD})
	impact.advance(0.0)
	check(not simulated.dead and impact.debris.emitted > count and impact.beats == 0 and impact.slashes.emitted == 0 and Engine.time_scale == 1.0, "Immortal simulation keeps hit particles without manufacturing a kill stop or death slash")
	simulated.cancel()
	session.enemies.erase(simulated)
	var a := watched(Vector3.RIGHT, 1.0)
	var b := watched(Vector3.RIGHT * 1.5, 1.0)
	var death_center := a.sprite.global_position
	a.take_damage(10.0, {"source":&"flight_sword", "direction":Vector3.RIGHT, "slash_direction":Vector3.FORWARD})
	check(Engine.time_scale < 0.01 and camera.hit_stop_active, "The lethal damage signal immediately holds the actual death frame")
	b.take_damage(10.0, {"source":&"basic_sword", "direction":Vector3.RIGHT})
	impact.advance(0.0)
	check(impact.beats == 1 and Engine.time_scale < 0.01 and camera.hit_stop_active, "Same-frame kills merge into one short world stop")
	check(impact.slashes.emitted == 1 and impact.slashes.active, "Same-frame kills share one prominent long slash instead of obscuring the crowd")
	check(probe.center.is_equal_approx(death_center) and probe.heading.is_equal_approx(Vector3.FORWARD), "The death slash is centered on the monster and follows the actual blade sweep rather than the damage direction")
	check(visuals.kill_slash_texture.get_size() == Vector2(128, 24) and not impact.slashes.is_processing() and impact.slashes.get_child_count() == 0, "The native 128 by 24 death slash uses a shared GPU batch without per-slash nodes")
	check(impact.debris.emitted >= count + visuals.hit_debris_count * 3, "Lethal hits add denser debris while the prominent slash is shared")
	var pending_time: float = impact.stop_remaining
	var c := watched(Vector3.RIGHT * 1.7, 1.0)
	c.take_damage(10.0, {"source":&"ricochet_storm", "direction":Vector3.RIGHT})
	impact.advance(0.012)
	check(impact.beats == 1 and impact.stop_remaining < pending_time, "Dense follow-up kills neither stack stops nor extend the current one")
	check(impact.slashes.emitted == 1, "Dense follow-up kills respect the independent slash interval")
	check(camera.hit_shake_offset.length() > 0.0 and camera.hit_shake_offset.length() < 0.3, "Kill shake follows a bounded multi-axis curve")
	check(camera.hit_shot_active and camera.hit_shot_distance_scale < 1.0 and camera.hit_shot_weight > 0.0, "The real camera pushes toward the merged kill region")
	check(camera.distance == 25.0 and camera.fov == 28.0 and camera.pitch_degrees == 30.627, "The temporary close-up preserves authored camera parameters")
	var particle_clock: float = impact.debris.clock
	impact.advance(0.05)
	check(Engine.time_scale < 0.01 and camera.hit_stop_active and not paused, "The real hold remains visible beyond the old 0.05-second tap")
	check(impact.debris.clock > particle_clock and not camera.hit_shake_offset.is_zero_approx(), "Debris and the curve shake continue during the held death frame")
	impact.advance(0.05)
	check(Engine.time_scale > 0.01 and Engine.time_scale < 1.0 and camera.hit_stop_active, "The hold releases through a brief slow-motion tail")
	impact.advance(0.08)
	check(Engine.time_scale == 1.0 and not camera.hit_stop_active and camera.hit_shot_distance_scale < 1.0 and camera.hit_shot_distance_scale >= visuals.kill_shot_zoom_scale, "World time resumes while the bounded group push continues independently")
	var flips_x := 0
	var flips_y := 0
	var previous := Vector3.ZERO
	for index in range(1, 52):
		var sample: Vector3 = impact.shake_curve(index * visuals.kill_shake_seconds / 52.0, visuals.kill_shake_seconds)
		if previous.x * sample.x < 0.0: flips_x += 1
		if previous.y * sample.y < 0.0: flips_y += 1
		previous = sample
	check(flips_x >= 4 and flips_y >= 4 and impact.shake_curve(visuals.kill_shake_seconds, visuals.kill_shake_seconds).is_zero_approx(), "Both shake axes repeatedly change direction and settle exactly, rather than playing one recoil")
	impact.advance(0.6)
	check(camera.hit_shake_offset.is_zero_approx() and not camera.hit_shot_active and camera.hit_shot_weight == 0.0 and camera.hit_shot_distance_scale == 1.0, "The camera restores its exact normal follow composition")
	check(not impact.debris.is_processing(), "GPU debris never starts an individual CPU particle update loop")
	impact.advance(0.5)
	var d := watched(Vector3.RIGHT, 1.0)
	d.take_damage(10.0, {"source":&"basic_sword", "direction":Vector3.RIGHT})
	impact.advance(0.0)
	session.set_combat_frozen(true)
	check(Engine.time_scale == 1.0 and not camera.hit_stop_active, "Upgrade freeze cancels and restores an active hit stop immediately")
	particle_clock = impact.debris.clock
	var slash_clock: float = impact.slashes.clock
	impact.advance(0.5)
	check(impact.debris.clock == particle_clock, "Upgrade selection holds visual particles at their current position")
	check(impact.slashes.clock == slash_clock, "Upgrade selection also holds the death slash at its current position")
	session.set_combat_frozen(false)
	impact.advance(0.5)
	var blocker := Node.new()
	world.add_child(blocker)
	blocker.add_to_group(&"gameplay_input_blockers")
	var blocked := watched(Vector3.RIGHT, 1.0)
	blocked.take_damage(10.0, {"source":&"basic_sword", "direction":Vector3.RIGHT})
	impact.advance(0.0)
	check(Engine.time_scale == 1.0 and camera.hit_shake_offset.is_zero_approx() and not camera.hit_shot_active, "Management input ownership keeps its UI free of new stops and close-ups")
	blocker.free()
	impact.advance(0.5)
	Engine.time_scale = 0.5
	var e := watched(Vector3.RIGHT, 1.0)
	e.take_damage(10.0, {"source":&"flight_sword", "direction":Vector3.RIGHT})
	impact.advance(0.0)
	check(Engine.time_scale < 0.01 and camera.hit_stop_active, "Kill holds also work when battle is already in slow motion")
	impact.cancel_beat()
	check(Engine.time_scale == 0.5 and camera.hit_shake_offset.is_zero_approx(), "Cancelling the close-up restores the previous slow-motion baseline")
	Engine.time_scale = 1.0
	impact.advance(1.0)
	var charge := ChargePresentation.new()
	impact.set("_charge", charge)
	charge._time_scale.advance(0.12, true, 0.6, 0.12, 0.06)
	var borrowed := watched(Vector3.RIGHT, 1.0)
	borrowed.take_damage(10.0, {"source":&"flight_sword", "direction":Vector3.RIGHT})
	check(Engine.time_scale < 0.01, "A real ricochet time owner lends its slow-motion frame to the kill hold")
	charge._restore_time()
	impact.advance(0.2)
	check(Engine.time_scale == 1.0, "Ending ricochet during the hold restores its underlying normal baseline")
	charge.free()
	impact.advance(1.0)
	var external := watched(Vector3.RIGHT, 1.0)
	external.take_damage(10.0, {"source":&"basic_sword", "direction":Vector3.RIGHT})
	Engine.time_scale = 0.7
	impact.advance(0.2)
	impact.cancel_beat()
	check(Engine.time_scale == 0.7, "An external time writer taking over the hold keeps its own value")
	Engine.time_scale = 1.0
	# 清波特写接管前必须先归还短顿基准。
	impact.advance(0.5)
	var f := watched(Vector3.RIGHT, 1.0)
	f.take_damage(10.0, {"source":&"basic_sword", "direction":Vector3.RIGHT})
	impact.advance(0.0)
	call_group(&"hit_impact_presentations", &"cancel_beat")
	check(Engine.time_scale == 1.0 and not camera.hit_stop_active, "Wave-finish handoff restores normal time before another cinematic claims it")
	impact.advance(0.5)
	check(not impact.debris.active and not impact.slashes.active, "Expired native effects hide and stop all instance work")
	player.action_visuals.kill_impact_enabled = false
	player.action_visuals.hit_debris_enabled = false
	var slash_count: int = impact.slashes.emitted
	var independent := watched(Vector3.RIGHT, 1.0)
	independent.take_damage(10.0, {"source":&"basic_sword", "direction":Vector3.RIGHT})
	impact.advance(0.0)
	check(impact.slashes.emitted == slash_count + 1 and Engine.time_scale == 1.0 and not impact.debris.active, "The native death slash remains independent of hit-stop and debris switches")
	player.action_visuals.kill_impact_enabled = true
	player.action_visuals.hit_debris_enabled = true
	impact.advance(0.5)
	var g := watched(Vector3.RIGHT, 1.0)
	g.take_damage(10.0, {"source":&"basic_sword", "direction":Vector3.RIGHT})
	impact.advance(0.0)
	impact.free()
	check(Engine.time_scale == 1.0 and not camera.hit_stop_active and not camera.hit_shot_active and camera.hit_shake_offset.is_zero_approx(), "Scene cleanup releases all camera and time ownership")
	first.cancel()
	session.enemies.erase(first)
	world.queue_free()
	await settle(5)
	await create_timer(0.35).timeout
	print("Hit impact: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
