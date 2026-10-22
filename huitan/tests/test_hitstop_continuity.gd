extends "res://tests/test_sword_hit_impact.gd"

class CameraProbe extends FollowCamera:
	func _target_point() -> Vector3:
		return target.global_position + Vector3.UP * focus_height

func run() -> void:
	await setup()
	var previous := player.movement_camera
	camera = CameraProbe.new()
	camera.target = player
	world.add_child(camera)
	player.movement_camera = camera
	previous.free()
	camera.set_process(false)
	impact = load("res://scripts/world/hit_impact_presentation.gd").new()
	impact.session = session
	world.add_child(impact)
	impact.set_process(false)
	player.position.x = 1.0
	camera._process(1.0 / 60.0)
	var focus := camera.focus
	var anchor := camera.anchor
	player.sword_rules = PlayerSwordRules.new()
	player.sword_rules.audio_enabled = false
	player.sword = PlayerSword.new()
	player.add_child(player.sword)
	player.sword.set_physics_process(false)
	player.sword._begin(Vector3.RIGHT, false)
	player._animation = &"run"
	player._animation_elapsed = 0.0
	player._movement_speed = 6.0
	player.action_animator.play_attack(&"normal_attack", Vector3.RIGHT, 0.3)
	player.velocity = Vector3(2.0, -1.0, 0.0)
	var position := player.position
	var velocity := player.velocity
	var action_age := player.action_animator._attack_age
	var animation_age := player._animation_elapsed
	var cooldown := player.body_ricochet._cooldown
	hit_target()
	# 切入的同一帧可能仍传入变速前的 delta；不能再按新的 0.001 倍率放大。
	camera._process(1.0 / 60.0)
	player._process(1.0 / 60.0)
	player._physics_process(1.0 / 60.0)
	player.sword._physics_process(1.0 / 60.0)
	check(camera.focus == focus and camera.anchor == anchor, "Hit-stop entry preserves the existing follow lag instead of jumping toward the player")
	check(player.position == position and player.velocity == velocity and player.body_ricochet._cooldown == cooldown, "The actual player body and movement state remain fixed even with the old frame delta")
	check(player._animation_elapsed == animation_age and player.action_animator._attack_age == action_age, "Both movement and attack animation clocks pause with the player")
	check(player.sword._age == 0.0 and player.sword._since_strike == 0.0, "The real sword sweep and attack interval also preserve their current time")
	impact.advance(0.012)
	camera._process(1.0 / 60.0)
	check(camera.focus == focus and not camera.hit_shake_offset.is_zero_approx(), "The hit curve keeps playing while base follow and the player hold still")
	impact.advance(0.04)
	camera._process(1.0 / 60.0)
	var resumed_step := camera.focus.distance_to(focus)
	check(Engine.time_scale == 1.0 and resumed_step > 0.0 and resumed_step < 0.05, "Follow resumes with a normal small step and no accumulated catch-up jump")
	player._process(1.0 / 60.0)
	check(player.action_animator._attack_age > action_age and player.action_animator._attack_age < 0.02, "Attack animation continues from its held age without replay or catch-up")
	player.sword._physics_process(1.0 / 60.0)
	check(player.sword._age > 0.0 and player.sword._age < 0.02, "The real sword resumes from the saved sweep age without accumulated attack time")
	# 普攻后立即群杀、时间外部接管及清波都必须释放人物，慢放尾段也不锁死人物。
	impact.clear()
	hit_target()
	impact.advance(0.012)
	emit_kill()
	impact.advance(0.10)
	check(player.get("hit_stop_active") == false and camera.hit_stop_active and Engine.time_scale > 0.01, "The lethal slow tail releases the player even while the world remains in brief slow motion")
	impact.clear()
	hit_target()
	Engine.time_scale = 0.7
	impact.advance(0.0)
	check(player.get("hit_stop_active") == false and Engine.time_scale == 0.7, "External time ownership immediately releases the explicit player hold")
	impact.clear()
	Engine.time_scale = 1.0
	hit_target()
	session.set_combat_frozen(true)
	check(player.get("hit_stop_active") == false and Engine.time_scale == 1.0, "Upgrade handoff releases the player's hit-stop flag")
	session.set_combat_frozen(false)
	impact.clear()
	hit_target()
	call_group(&"hit_impact_presentations", &"cancel_beat")
	check(player.get("hit_stop_active") == false and Engine.time_scale == 1.0, "Wave cinematic handoff releases the player before taking over time")
	impact.clear()
	hit_target()
	impact.free()
	check(player.get("hit_stop_active") == false and Engine.time_scale == 1.0, "Removing the presentation cannot leave the player held")
	world.queue_free()
	await settle(4)
	print("Hit-stop continuity: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
