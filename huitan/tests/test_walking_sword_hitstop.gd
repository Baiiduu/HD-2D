extends "res://tests/test_sword_hit_impact.gd"

class Timeline extends Node:
	var player: Player
	var camera: FollowCamera
	var samples: Array[Dictionary] = []
	func _process(_delta: float) -> void:
		samples.append({"held":player.hit_stop_active, "position":player.global_position,
			"focus":camera.focus, "speed":player._movement_speed, "attack_age":player.action_animator._attack_age,
			"physics_tick":Engine.get_physics_frames()})

func keyboard(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_D
	event.physical_keycode = KEY_D
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func ticks(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame

func run() -> void:
	await setup()
	var old_fps := Engine.max_fps
	Engine.max_fps = 120
	# 复用正式资源和实体胶囊尺寸；关闭怪物身体阻挡以隔离走路、攻击与短顿时序。
	var config: SceneCombatConfiguration = load("res://data/combat/scenes/world/configuration.tres")
	var collision := player.get_node("Collision") as CollisionShape3D
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = 1.06592
	collision.shape = capsule
	collision.position.y = capsule.height * 0.5
	player.position = Vector3(-2.0, 0.03, -2.0)
	player.reset_physics_interpolation()
	var previous := player.movement_camera
	camera = FollowCamera.new()
	camera.target = player
	camera.distance = 30.0
	camera.fov = 28.0
	camera.pitch_degrees = 30.627
	camera.yaw_degrees = 135.0
	camera.ricochet_camera_settings = config.ricochet_camera_settings.duplicate()
	world.add_child(camera)
	player.movement_camera = camera
	previous.free()
	player.sword_rules = config.sword_rules.duplicate()
	player.sword_rules.audio_enabled = false
	player.sword = PlayerSword.new()
	player.sword.name = "BasicSword"
	player.add_child(player.sword)
	impact = load("res://scripts/world/hit_impact_presentation.gd").new()
	impact.session = session
	world.add_child(impact)
	var numbers: DamageNumbers = load("res://scenes/combat/damage_numbers.tscn").instantiate()
	numbers.session = session
	numbers.number_styles = config.number_styles
	session.add_child(numbers)
	player.set_physics_process(true)
	await ticks(8)
	check(player.is_on_floor() and player.sword.get_stats(false).damage == 10.0, "The real World basic sword starts grounded with ten damage")
	check(not config.population_rules.simulation_mode and not session.combat_modifiers.damage_disabled, "Normal World combat does not enable simulation's damage immunity")
	var timeline := Timeline.new()
	timeline.player = player
	timeline.camera = camera
	timeline.process_priority = 100
	world.add_child(timeline)
	keyboard(true)
	await ticks(12)
	var held_frames := 0
	var resume_frames := 0
	var moving_hold_frames := 0
	var camera_hold_frames := 0
	var frozen_attack_frames := 0
	var maximum_step := 0.0
	var maximum_focus_step := 0.0
	var maximum_speed := 0.0
	var oversize_steps := 0
	for round_index in 2:
		var heading := camera.global_basis.x
		heading.y = 0.0
		heading = heading.normalized()
		var enemy := spawn("wave_slime", player.global_position + heading * 0.95, 100.0)
		enemy.collision_layer = 0
		enemy.collision_mask = 0
		enemy.commit_spatial_state()
		session.enemy_spawned.emit(enemy)
		var hits: Array[CombatDamageEvent] = []
		enemy.damaged.connect(func(event): hits.append(event))
		check(player.sword.request_manual(heading), "A moving player can request the real basic sword sweep")
		await ticks(39)
		check(enemy.health == 90.0 and hits.size() == 1 and hits[0].amount == 10.0 and hits[0].source == &"basic_sword", "Each real moving sweep removes exactly ten health once")
		var target_id := enemy.get_instance_id()
		check(numbers._active.any(func(number): return number.event.target_id == target_id and number._text == "10" and number.visible), "The actual moving sweep retains its ten-damage number through the hit stop")
		enemy.cancel()
		session.enemies.erase(enemy)
	keyboard(false)
	await ticks(6)
	timeline.set_process(false)
	for index in range(1, timeline.samples.size()):
		var before: Dictionary = timeline.samples[index - 1]
		var after: Dictionary = timeline.samples[index]
		var step: float = after.position.distance_to(before.position)
		var focus_step: float = after.focus.distance_to(before.focus)
		maximum_step = maxf(maximum_step, step)
		maximum_focus_step = maxf(maximum_focus_step, focus_step)
		maximum_speed = maxf(maximum_speed, after.speed)
		# 一次处理前可补跑多个正常物理步；按实际步数检查，不假定每次处理仅有一帧物理。
		var physics_steps := maxi(1, int(after.physics_tick) - int(before.physics_tick))
		var allowed_step := player.get_movement_speed() / Engine.physics_ticks_per_second * physics_steps * 1.25
		if step > allowed_step or focus_step > allowed_step: oversize_steps += 1
		if before.held and after.held:
			held_frames += 1
			if step > 0.000001: moving_hold_frames += 1
			if focus_step > 0.000001: camera_hold_frames += 1
			if not is_equal_approx(float(before.attack_age), float(after.attack_age)): frozen_attack_frames += 1
		if before.held and not after.held:
			resume_frames += 1
	check(held_frames >= 2 and resume_frames == 2, "Two real sword hits each hold and resume while the direction key stays pressed")
	check(moving_hold_frames == 0 and camera_hold_frames == 0 and frozen_attack_frames == 0, "Walking position, sword animation and base follow remain synchronized throughout actual held frames")
	check(oversize_steps == 0, "No processing update exceeds normal body or base-focus travel for its actual physics steps")
	check(maximum_speed <= player.get_movement_speed() * 1.01, "Restoring the clock cannot produce a spurious movement-animation speed spike")
	check(player.velocity.length() < 0.01 and not player.hit_stop_active and Engine.time_scale == 1.0, "Releasing movement after the final hit leaves the player stopped and time restored")
	print("Walking samples: %d, holds: %d, resumes: %d, maximum body step: %.6f, focus step: %.6f, movement speed: %.6f" % [timeline.samples.size(), held_frames, resume_frames, maximum_step, maximum_focus_step, maximum_speed])
	impact.clear()
	world.queue_free()
	await settle(4)
	Engine.max_fps = old_fps
	print("Walking sword hit-stop: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
