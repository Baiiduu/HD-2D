extends "res://tests/test_enemy_hit_reaction.gd"

var impact: Node3D
var camera: FollowCamera
var serial := 0

func emit_kill(source: StringName = &"flight_sword") -> void:
	serial += 1
	var enemy := spawn("wave_slime", Vector3(1.0 + (serial % 5) * 0.15, 0.0, 0.0), 1.0)
	session.enemy_spawned.emit(enemy)
	enemy.take_damage(10.0, {"source":source, "direction":Vector3.RIGHT})
	impact.set_process(false)

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
	emit_kill()
	impact.advance(0.04)
	check(Engine.time_scale < 0.01 and camera.hit_stop_active and not camera.hit_shake_offset.is_zero_approx(), "Single kills preserve the immediate hold and impact shake")
	check(is_equal_approx(camera.hit_shot_distance_scale, 1.0) and camera.hit_shot_weight == 0.0, "A single kill does not push or redirect the camera")
	check(camera.get("hit_closeup_active") == false, "A single impact does not claim ownership of close-up framing")
	impact.advance(1.2)
	emit_kill()
	impact.advance(0.04)
	check(is_equal_approx(camera.hit_shot_distance_scale, 1.0), "Repeated isolated kills also leave camera distance stable")
	impact.advance(0.30)
	var beats: int = impact.beats
	emit_kill()
	emit_kill(&"basic_sword")
	impact.advance(0.0)
	check(camera.hit_shot_distance_scale == 1.0, "A pair does not prematurely spend the group camera")
	emit_kill(&"ricochet_storm")
	check(camera.get("hit_closeup_active") == true, "An earned group close-up claims framing immediately, including its zero-weight first frame")
	check(impact.beats == beats and Engine.time_scale == 1.0, "A group can earn camera motion during single-hit cooldown without another hold")
	impact.advance(0.02)
	check(camera.hit_shot_distance_scale > 0.995 and camera.hit_shot_distance_scale < 1.0, "Group camera begins gradually instead of snapping into a close-up")
	impact.advance(0.18)
	check(camera.hit_shot_distance_scale < 0.98 and camera.hit_shot_distance_scale >= visuals.kill_shot_zoom_scale, "The group smoothly reaches a small bounded push")
	check(camera.hit_shot_weight < 0.3 and Engine.time_scale == 1.0, "Group framing retains the player and does not prolong slow motion")
	var age: float = impact.get("_shot_age")
	var scale_before := camera.hit_shot_distance_scale
	emit_kill()
	emit_kill()
	emit_kill()
	check(is_equal_approx(float(impact.get("_shot_age")), age) and is_equal_approx(camera.hit_shot_distance_scale, scale_before), "More kills do not restart, stack or redirect the active camera move")
	impact.advance(0.8)
	check(camera.hit_shot_distance_scale == 1.0 and camera.hit_shot_weight == 0.0 and not camera.hit_shot_active, "Camera restores its exact follow composition after the group move")
	check(camera.get("hit_closeup_active") == false, "Finishing the group close-up releases its separate framing ownership")
	for index in 3: emit_kill()
	impact.advance(0.3)
	check(camera.hit_shot_distance_scale == 1.0, "Kills during the independent camera cooldown are discarded rather than replayed later")
	for index in 3: emit_kill()
	impact.advance(0.1)
	check(camera.hit_shot_distance_scale < 1.0, "A fresh group can trigger again after the independent interval")
	# 群杀推进有自己的间隔；单杀短顿不能消耗这份预算。
	impact.clear()
	for index in 3:
		emit_kill()
		impact.advance(0.16)
	check(camera.hit_shot_distance_scale == 1.0 and camera.hit_shot_weight == 0.0, "Separated kills never accumulate into a group")
	impact.clear()
	for index in 3: emit_kill()
	impact.advance(0.1)
	session.set_combat_frozen(true)
	check(Engine.time_scale == 1.0 and camera.hit_shot_distance_scale == 1.0 and not camera.hit_shot_active, "Freeze immediately releases both hold and group framing")
	impact.advance(0.6)
	session.set_combat_frozen(false)
	impact.advance(0.1)
	check(camera.hit_shot_distance_scale == 1.0, "Unfreezing does not replay an old group")
	impact.clear()
	visuals.kill_shot_enabled = false
	for index in 3: emit_kill()
	impact.advance(0.04)
	check(Engine.time_scale < 0.01 and camera.hit_shot_distance_scale == 1.0, "Turning off group framing preserves independent impact holds")
	impact.clear()
	visuals.kill_shot_enabled = true
	camera.wave_shot_active = true
	for index in 3: emit_kill()
	impact.advance(0.1)
	check(Engine.time_scale == 1.0 and not camera.hit_shot_active and camera.hit_shot_distance_scale == 1.0, "Wave-final cinematics retain priority over normal group camera requests")
	camera.wave_shot_active = false
	impact.clear()
	for index in 3: emit_kill()
	impact.advance(0.1)
	var blocker := Node.new()
	world.add_child(blocker)
	blocker.add_to_group(&"gameplay_input_blockers")
	impact.advance(0.0)
	check(Engine.time_scale == 1.0 and not camera.hit_shot_active, "Management UI releases all active group camera ownership")
	blocker.free()
	impact.clear()
	for index in 3: emit_kill()
	impact.advance(0.1)
	impact.free()
	check(Engine.time_scale == 1.0 and not camera.hit_shot_active and camera.hit_shot_distance_scale == 1.0, "Scene cleanup restores time, focus and distance")
	world.queue_free()
	await settle(4)
	print("Kill camera balance: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
