extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failures.append(message); push_error(message)

func run() -> void:
	var camera := FollowCamera.new()
	check("follow_max_speed" in camera and "follow_max_lag" in camera, "Camera supports a comfort speed limit and a safe follow distance")
	if failures.is_empty(): await behavior_checks(camera)
	else: camera.free()
	print(JSON.stringify({"suite":"camera_follow_limit", "checks":checks, "failures":failures}))
	quit(0 if failures.is_empty() else 1)

func behavior_checks(camera: FollowCamera) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var target := Node3D.new()
	world.add_child(target)
	camera.target = target
	camera.dof_enabled = false
	camera.dead_zone = 0.0
	camera.distance = 30.0
	camera.fov = 28.0
	camera.pitch_degrees = 30.627
	world.add_child(camera)
	camera.set_process(false)
	camera.set_world_rect(Rect2(-200, -200, 400, 400))
	check(is_zero_approx(camera.get("follow_max_speed")), "Other scenes retain their existing unrestricted follow by default")
	camera.set("follow_max_speed", 2.0)
	camera.set("follow_max_lag", 3.0)
	var initial := camera.focus
	target.position.x = 1.0
	target.reset_physics_interpolation()
	camera._process(0.05)
	check(camera.focus.distance_to(initial) <= 0.1001, "Nearby ordinary following respects the configured metres-per-second limit")
	var still := camera.focus
	camera._process(0.0)
	check(camera.focus.is_equal_approx(still), "Zero elapsed time never moves the capped focus")
	for distance in [15.0, 30.0]:
		for angle in [0.0, 45.0, 135.0, 225.0]:
			camera.distance = distance
			camera.yaw_degrees = angle
			target.position = Vector3.ZERO
			target.reset_physics_interpolation()
			camera.snap_to_target()
			var safe := true
			var exceeded_comfort := false
			for index in 120:
				var previous := camera.focus
				target.position.x += (30.0 if index < 60 else -30.0) / 60.0
				target.reset_physics_interpolation()
				camera._process(1.0 / 60.0)
				exceeded_comfort = exceeded_comfort or camera.focus.distance_to(previous) > 2.01 / 60.0
				var screen := camera.unproject_position(camera._target_point()) / root.get_visible_rect().size
				safe = safe and camera.focus.distance_to(camera._target_point()) <= 3.001 and Rect2(0.12, 0.12, 0.76, 0.76).has_point(screen)
			check(safe and exceeded_comfort, "Fast motion and reversals stay visible under rotated and closer views, using safety catch-up when needed")
	camera.follow_enabled = false
	camera.focus = camera._target_point() + Vector3(20, 0, 0)
	camera.anchor = camera.focus
	var unlocked := camera.focus
	camera.follow_enabled = true
	camera._process(1.0 / 60.0)
	check(camera.focus.distance_to(unlocked) > 0.0 and camera.focus.distance_to(camera._target_point()) > 1.0, "Relocking from far away returns smoothly instead of snapping to the safety radius")
	for index in 180: camera._process(1.0 / 60.0)
	check(camera.focus.distance_to(camera._target_point()) < 0.05, "A distant relock finishes and resumes normal following")
	camera.set_process(true)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_Y
	key.pressed = true
	check(camera.has_method("_unhandled_key_input"), "Y can toggle camera following without opening settings")
	if camera.has_method("_unhandled_key_input"):
		camera.call("_unhandled_key_input", key)
		check(not camera.follow_enabled, "A Y press unlocks the gameplay camera")
		key.echo = true
		camera.call("_unhandled_key_input", key)
		check(not camera.follow_enabled, "Key auto-repeat does not toggle twice")
		key.echo = false
		key.ctrl_pressed = true
		camera.call("_unhandled_key_input", key)
		check(not camera.follow_enabled, "Control-Y remains available to text and editor-style controls")
		key.ctrl_pressed = false
		var blocker := Node.new()
		blocker.add_to_group(&"gameplay_input_blockers")
		world.add_child(blocker)
		camera.call("_unhandled_key_input", key)
		check(not camera.follow_enabled, "Management screens suppress Y toggling")
		blocker.free()
		camera.call("_unhandled_key_input", key)
		check(camera.follow_enabled, "A second fresh Y press relocks following")
		camera.set_process(false)
		camera.call("_unhandled_key_input", key)
		check(camera.follow_enabled, "Entry cinematics that own the camera suppress Y toggling")
	world.free()
	await process_frame
