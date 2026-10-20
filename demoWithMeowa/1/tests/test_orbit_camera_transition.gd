extends "res://tests/test_crowd_deflection.gd"

var camera: FollowCamera
var settings: RicochetCameraSettings

func path_checks() -> void:
	var path := "res://scripts/camera/ricochet_orbit_shot.gd"
	check(FileAccess.file_exists(path), "Frequent orbit transitions need an independent, bounded camera accent")
	if not FileAccess.file_exists(path): return
	settings = load("res://data/combat/scenes/world/player/ricochet_camera.tres").duplicate()
	check("orbit_closeup_exit_hold_seconds" in settings, "Orbit close-up waits briefly before returning so nearby re-entry does not pump the lens")
	if not "orbit_closeup_exit_hold_seconds" in settings: return
	check("orbit_enter_magnification" in settings and "orbit_hold_magnification" in settings, "Orbit close-ups expose an entry multiplier and a sustained multiplier")
	if not "orbit_hold_magnification" in settings: return
	check(settings.get("orbit_shot_enabled") and not RicochetCameraSettings.new().get("orbit_shot_enabled"), "Only World opts into orbit transition shots")
	check(not load("res://data/combat/scenes/city/player/ricochet_camera.tres").get("orbit_shot_enabled"), "City keeps its existing camera")
	var shot: RefCounted = load(path).new()
	shot.advance(0.0, true, settings)
	check(shot.distance_offset == 0.0, "Entering orbit starts at the current lens without a cut")
	shot.advance(settings.orbit_closeup_enter_seconds, true, settings)
	check(is_equal_approx(shot.magnification, 1.5), "Entry reaches the configured one-and-a-half screen magnification")
	for frame in 300: shot.advance(0.01, true, settings)
	check(is_equal_approx(shot.magnification, 1.4) and not shot.accent_active and shot.active, "The entire orbit holds 1.4 magnification without replaying its curve")
	var held: float = shot.distance_offset
	shot.advance(0.0, false, settings)
	check(shot.distance_offset == held, "Exit starts at the exact sustained close-up")
	shot.advance(settings.orbit_closeup_exit_hold_seconds, false, settings)
	check(shot.distance_offset == held, "The displayed close-up stays unchanged throughout exit grace")
	shot.advance(settings.orbit_closeup_exit_seconds * 0.5, false, settings)
	check(shot.distance_offset > held and shot.magnification > 1.0 and shot.magnification < 1.4, "Exit smoothly opens from the current close-up without an outward zoom punch")
	for frame in 100: shot.advance(0.01, false, settings)
	check(shot.distance_offset == 0.0 and not shot.active, "The shot returns completely instead of leaving a new base zoom")
	shot.clear()
	shot.advance(0.1, true, settings)
	shot.advance(0.01, false, settings)
	var reentry: float = shot.magnification
	shot.advance(0.0, true, settings)
	check(shot.magnification == reentry and shot.accent_active, "Rapid re-entry preserves the current lens and does not restart the short curve")
	shot.advance(settings.orbit_closeup_enter_seconds, true, settings)
	check(is_equal_approx(shot.magnification, 1.4), "Re-entering during the shared interval goes straight to the hold ratio without replaying the entry peak")
	for frame in 65: shot.advance(0.01, true, settings)
	shot.advance(0.0, false, settings)
	check(not shot.accent_active and shot.active, "The shared interval limits the curve but never blocks smooth close-up exit")
	for frame in 100: shot.advance(0.01, false, settings)
	check(not shot.active and shot.distance_offset == 0.0, "Suppressed transitions are discarded, never queued")
	shot.advance(0.05, true, settings)
	for frame in 100: shot.advance(0.01, false, settings)
	check(not shot.active and shot.distance_offset == 0.0, "A brief graze does not add a second exit shot")
	shot.clear()
	shot.advance(0.1, true, settings)
	shot.clear(true)
	shot.advance(0.1, true, settings)
	check(not shot.accent_active and shot.magnification > 1.0, "A new flight keeps the curve interval while still entering sustained close-up")
	for rate in [30, 120]:
		shot.clear()
		for frame in rate / 5: shot.advance(1.0 / rate, true, settings)
		var other: RefCounted = load(path).new()
		other.advance(0.2, true, settings)
		check(absf(shot.distance_offset - other.distance_offset) < 0.00001, "The shot depends on elapsed time, not frame count")
		shot.advance(20.0, true, settings)
		check(is_equal_approx(shot.magnification, 1.4), "Long orbits and long steps reach the exact hold ratio without cumulative zoom")
	shot.advance(0.0, true, settings, true)
	check(not shot.accent_active and is_equal_approx(shot.magnification, 1.4), "Group close-ups clear the small curve while preserving the orbit base close-up")
	for frame in 100: shot.advance(0.01, true, settings)
	check(not shot.accent_active, "Releasing camera ownership does not replay an old orbit entry")
	shot.advance(0.0, true, settings, true, Vector3.ZERO, Vector3.ZERO, true)
	check(is_equal_approx(shot.magnification, 1.4), "Full camera takeover starts from the actual close-up")
	shot.advance(0.5, true, settings, true, Vector3.ZERO, Vector3.ZERO, true)
	check(shot.magnification == 1.0, "Full camera takeover releases the held zoom smoothly")
	shot.advance(0.0, true, settings)
	check(shot.magnification == 1.0 and not shot.accent_active, "Returning camera ownership does not replay the entry peak")
	shot.advance(0.3, true, settings)
	check(is_equal_approx(shot.magnification, 1.4), "Still orbiting after takeover restores the sustained ratio")
	settings.orbit_hold_magnification = 1.6
	shot.advance(0.0, true, settings)
	check(is_equal_approx(shot.magnification, 1.4), "Live Inspector edits start from the displayed ratio")
	shot.advance(0.3, true, settings)
	check(is_equal_approx(shot.magnification, 1.6), "Live hold multiplier edits reach their new value")
	settings.orbit_hold_magnification = 1.4
	exit_hold_checks(path)
	arc_checks(path)
	await camera_checks()

func exit_hold_checks(path: String) -> void:
	check(is_equal_approx(settings.orbit_closeup_exit_hold_seconds, 0.6) and RicochetCameraSettings.new().orbit_closeup_exit_hold_seconds == 0.0, "Only World opts into a six-tenths exit grace")
	var shot: RefCounted = load(path).new()
	shot.advance(3.0, true, settings)
	shot.advance(0.45, false, settings)
	check(is_equal_approx(shot.magnification, 1.4) and shot.active, "Leaving a group keeps near framing ready for another group")
	shot.advance(0.0, true, settings)
	check(is_equal_approx(shot.magnification, 1.4), "Re-entry during grace never briefly widens the lens")
	shot.advance(0.3, true, settings)
	shot.advance(0.55, false, settings)
	check(is_equal_approx(shot.magnification, 1.4), "A later exit receives its own complete grace period")
	shot.advance(0.25, false, settings)
	check(shot.magnification > 1.0 and shot.magnification < 1.4, "Returning starts only after grace has elapsed")
	shot.advance(0.3, false, settings)
	check(shot.magnification == 1.0 and not shot.active, "Grace plus return ends completely without residual camera work")
	shot.clear()
	shot.advance(0.09, true, settings)
	var early: float = shot.magnification
	shot.advance(0.5, false, settings)
	check(shot.magnification == early, "A brief entry preserves its actual partial zoom rather than snapping to the hold ratio")
	shot.advance(0.0, false, settings, true, Vector3.ZERO, Vector3.ZERO, true)
	check(shot.magnification == early, "Takeover during grace does not cut the lens")
	shot.advance(0.4, false, settings, true, Vector3.ZERO, Vector3.ZERO, true)
	check(shot.magnification == 1.0, "Full camera takeover bypasses exit grace")
	shot.clear()
	shot.advance(3.0, true, settings)
	shot.advance(0.2, false, settings)
	settings.orbit_shot_enabled = false
	shot.advance(0.4, false, settings)
	check(shot.magnification == 1.0, "Disabling orbit close-up also bypasses pending grace")
	settings.orbit_shot_enabled = true
	for rate in [30, 120]:
		shot.clear()
		shot.advance(3.0, true, settings)
		for frame in rate * 4 / 5: shot.advance(1.0 / rate, false, settings)
		check(absf(shot.magnification - 1.2) < 0.00001, "Grace and returning use elapsed time consistently across frame rates")
	settings.orbit_closeup_exit_hold_seconds = 0.0
	shot.clear()
	shot.advance(3.0, true, settings)
	shot.advance(0.2, false, settings)
	check(shot.magnification > 1.0 and shot.magnification < 1.4, "Zero grace preserves immediate smooth returning")
	settings.orbit_closeup_exit_hold_seconds = 0.6

func arc_checks(path: String) -> void:
	var shot: RefCounted = load(path).new()
	check("focus_offset" in shot and "pitch_offset" in shot, "Orbit entry needs a directional arc and pitch, beyond changing distance")
	if not "focus_offset" in shot or not "pitch_offset" in shot: return
	shot.advance(0.08, true, settings, false, Vector3.FORWARD, Vector3.RIGHT)
	var early: Vector3 = shot.focus_offset
	check(early.dot(Vector3.FORWARD) > 0.001 and shot.pitch_offset < -0.1, "Entry initially carries forward and lowers the viewing angle")
	shot.advance(0.30, true, settings, false, Vector3.BACK, Vector3.LEFT)
	check(shot.focus_offset.x > early.x and shot.focus_offset.z > early.z, "The snapshot bends toward the captured group without chasing subsequent headings")
	check(shot.focus_offset.length() <= settings.orbit_shot_offset_ratio and absf(shot.pitch_offset) <= settings.orbit_shot_pitch_degrees, "Arc position and pitch have independent small limits")
	for frame in 250: shot.advance(0.01, true, settings)
	shot.observe(false, settings, Vector3.RIGHT)
	shot.advance(0.12, false, settings)
	check(shot.focus_offset.x > 0.001 and shot.pitch_offset > 0.1, "Exit carries along the real departure tangent and lifts the view slightly")
	for frame in 100: shot.advance(0.01, false, settings)
	check(shot.focus_offset == Vector3.ZERO and shot.pitch_offset == 0.0, "Arc position and angle finish exactly at the original framing")
	settings.orbit_enter_magnification = 1.0
	settings.orbit_hold_magnification = 1.0
	shot.clear()
	shot.advance(0.12, true, settings, false, Vector3.FORWARD, Vector3.RIGHT)
	check(shot.distance_offset == 0.0 and shot.focus_offset.length() > 0.001, "Turning zoom off still leaves a readable directional camera movement")
	settings.orbit_enter_magnification = 1.5
	settings.orbit_hold_magnification = 1.4

func camera_checks() -> void:
	terrain.data.resize(Vector2i(-16, -16), Vector2i(32, 32))
	player.ricochet_rules = load("res://data/combat/scenes/world/player/body_ricochet.tres").duplicate()
	player.ricochet_rules.minimum_launch_speed = 12.0
	player.ricochet_rules.maximum_launch_speed = 12.0
	player.sword.rules.enabled = false
	camera = FollowCamera.new()
	camera.target = player
	camera.ricochet_camera_settings = settings
	camera.distance = 30.0
	camera.pitch_degrees = 30.627
	camera.yaw_degrees = 135.0
	camera.fov = 28.0
	camera.dof_enabled = false
	camera.follow_max_speed = 10.0
	world.add_child(camera)
	player.movement_camera = camera
	camera.set_process(false)
	var baseline := await route(false)
	await clear()
	var accented := await route(true)
	check(baseline == accented, "Orbit shots leave every real position, speed and energy clock unchanged")
	await framing_checks()
	await clear()
	await enter()
	for frame in 140: step(0.01)
	var feedback := camera._ricochet_camera
	await impact_priority_checks(feedback)
	await clear()
	await enter()
	for frame in 140: step(0.01)
	var before := camera.global_transform
	body.advance(0.0, Vector3.RIGHT, false, 1)
	camera._process(0.0)
	check(not body.flying and feedback._orbit_shot.active, "Movement cancellation immediately hands control back and still starts the small exit shot")
	check(before.is_equal_approx(camera.global_transform), "Finishing an orbit does not jump the camera on the event frame")
	camera._process(0.12)
	check(feedback.orbit_distance_scale < 0.0 and is_equal_approx(feedback._orbit_shot.magnification, 1.4), "Exit grace survives the end of the actual flight")
	var delay_age: float = feedback._orbit_shot._zoom_age
	session.set_combat_frozen(true)
	camera._process(0.8)
	check(feedback._orbit_shot._zoom_age == delay_age, "Upgrade freeze does not consume exit grace")
	session.set_combat_frozen(false)
	for frame in 120: camera._process(0.01)
	check(not feedback.active and feedback.orbit_distance_scale == 0.0, "Recovery finishes with no lingering camera work")
	await clear()
	await enter()
	step(0.08)
	var frozen := camera.global_transform
	var age: float = feedback._orbit_shot._age
	session.set_combat_frozen(true)
	camera._process(0.5)
	check(camera.global_transform.is_equal_approx(frozen) and feedback._orbit_shot._age == age, "Upgrade freeze preserves the exact shot and time")
	session.set_combat_frozen(false)
	step(0.01)
	check(feedback._orbit_shot._age > age, "Unfreezing resumes the shot instead of catching up")
	for owner in [&"wave_shot_active", &"hit_closeup_active"]:
		if not owner in camera: continue
		camera.set(owner, true)
		var ratio: float = feedback._orbit_shot.magnification
		camera._process(0.0)
		check(not feedback._orbit_shot.accent_active and is_equal_approx(feedback._orbit_shot.magnification, ratio), "Higher-priority shots cancel the short curve without a lens cut")
		camera._process(0.5)
		check(is_equal_approx(feedback._orbit_shot.magnification, 1.0 if owner == &"wave_shot_active" else 1.4), "Wave shot releases orbit zoom; group kill preserves stable orbit framing")
		camera.set(owner, false)
		camera._process(0.5)
	await clear()
	await enter()
	for frame in 110: step(0.01)
	# 耗尽与怪群清空都必须经过同一真实离场边沿。
	body.flight_speed = body._settings.minimum_bounce_speed + 0.001
	step(0.01)
	check(not body.flying and feedback._orbit_shot.active, "Natural energy depletion also gets an exit accent")
	for frame in 60: camera._process(0.01)
	await clear()
	await enter()
	for frame in 110: step(0.01)
	for actor in session.enemies: actor.dead = true
	for frame in 30:
		step(0.01)
		if not body.orbiting: break
	check(body.flying and not body.orbiting and feedback._orbit_shot.active, "Losing the captured group opens the view while flight continues")
	await clear()
	await enter()
	for frame in 110: step(0.01)
	var impact := RicochetImpact.new()
	impact.incoming_velocity = Vector3.RIGHT * 10.0
	impact.outgoing_velocity = Vector3.LEFT * 9.0
	impact.normal = Vector3.LEFT
	impact.point = player.global_position
	feedback._on_impact_recorded(impact)
	body.detach_from_crowd()
	camera._process(0.01)
	check(feedback._impact_shot.active and not feedback._orbit_shot.accent_active and feedback._orbit_shot.magnification > 1.0, "Real bounce takes over the curve while orbit zoom begins its smooth exit")
	var blocker := Node.new()
	world.add_child(blocker)
	blocker.add_to_group(&"gameplay_input_blockers")
	camera._process(0.0)
	camera._process(0.6)
	check(feedback.orbit_distance_scale == 0.0, "Management UI releases the close-up without replaying camera accents")
	blocker.free()
	camera.follow_enabled = false
	check(camera._ricochet_camera == null, "Free camera releases orbit accents with all other player framing")
	camera.follow_enabled = true
	camera._process(0.0)
	camera.snap_to_target()
	check(camera._ricochet_camera.orbit_distance_scale == 0.0, "Explicit reset removes the orbit accent")
	check(camera.distance == 30.0 and camera.fov == 28.0 and camera.pitch_degrees == 30.627 and camera.yaw_degrees == 135.0 and Engine.time_scale == 1.0, "Base framing, Q/E reference and world time stay unchanged")

func framing_checks() -> void:
	await clear()
	await enter()
	for frame in 10: step(0.01)
	var feedback := camera._ricochet_camera
	var lens: float = feedback.orbit_distance_scale
	feedback.orbit_distance_scale = 0.0
	camera._apply_transform()
	var accented := camera.global_transform
	var pitch: float = feedback.orbit_pitch_offset
	var offset: Vector3 = feedback.orbit_focus_offset
	feedback.orbit_pitch_offset = 0.0
	feedback.orbit_focus_offset = Vector3.ZERO
	camera._apply_transform()
	check(accented.origin.distance_to(camera.global_position) > 0.1 and accented.basis.y.distance_to(camera.global_basis.y) > 0.005, "The actual camera receives translation and pitch even with zoom removed")
	feedback.orbit_pitch_offset = pitch
	feedback.orbit_focus_offset = offset
	feedback.orbit_distance_scale = lens
	camera._yaw_offset_degrees = 45.0
	camera._process(0.0)
	check(feedback.orbit_focus_offset.normalized().is_equal_approx(offset.normalized()), "Q/E rotates around the world-space shot without rebuilding or flipping its path")
	camera._yaw_offset_degrees = 0.0
	camera.bounds_min = Vector2.ZERO
	camera.bounds_max = Vector2.ZERO
	camera.snap_to_target()
	camera._process(0.0)
	camera.bounds_min = Vector2(-INF, -INF)
	camera.bounds_max = Vector2(INF, INF)
	check(feedback.orbit_focus_offset == Vector3.ZERO and feedback.orbit_pitch_offset == 0.0, "Reset clears the added framing and angle alongside zoom")

func impact_priority_checks(feedback: RicochetCameraFeedback) -> void:
	await clear()
	await enter()
	var impact: Node3D = load("res://scripts/world/hit_impact_presentation.gd").new()
	player.action_visuals.sword_hit_impact_enabled = true
	player.action_visuals.hit_debris_enabled = false
	player.action_visuals.kill_slash_enabled = false
	impact.session = session
	world.add_child(impact)
	session.enemies[0].take_damage(1.0, {"source":&"basic_sword", "direction":Vector3.RIGHT})
	impact.set_process(false)
	impact.advance(0.05)
	check(camera.hit_shot_active and not camera.hit_stop_active, "The real ordinary-hit system keeps its small impact after releasing hit-stop")
	camera._process(0.02)
	check(feedback._orbit_shot.active and feedback.orbit_distance_scale < 0.0, "An ordinary impact must not silently cancel the real orbit-entry camera")
	impact.clear()
	impact.free()
	player.action_visuals.sword_hit_impact_enabled = false

func enter() -> void:
	group(Vector3(3, 0, 0), 5, 5)
	await reset()
	camera.snap_to_target()
	body.begin_charge(Vector3.RIGHT)
	body.advance(0.8, Vector3.ZERO, false)
	body.release_charge()
	for frame in 240:
		if body.orbiting or not body.flying: break
		step(1.0 / 120.0)
	check(body.orbiting, "A real group contour triggers orbit entry")

func step(seconds: float) -> void:
	body.advance(seconds, Vector3.ZERO, false)
	player.reset_physics_interpolation()
	camera._process(seconds)

func route(enabled: bool) -> Array[Vector3]:
	settings.orbit_shot_enabled = enabled
	await enter()
	var result: Array[Vector3] = []
	var entered := false
	var exited := false
	var exact_hold := false
	var entry_peak := 1.0
	for frame in 270:
		if frame == 150: body.detach_from_crowd()
		step(0.01)
		result.append(player.global_position)
		result.append(Vector3(body.flight_speed, body.movement_speed, body.flight_elapsed))
		entered = entered or camera._ricochet_camera.orbit_distance_scale < -0.001
		var feedback := camera._ricochet_camera
		entry_peak = maxf(entry_peak, feedback._orbit_shot.magnification)
		if frame > 70 and frame < 150 and enabled:
			var ratio := feedback.distance_scale / (feedback.distance_scale + feedback.orbit_distance_scale)
			exact_hold = exact_hold or absf(ratio - 1.4) < 0.00001
		exited = exited or (entered and frame > 170 and feedback._orbit_shot.magnification == 1.0)
	check((entered and exited) if enabled else (not entered and not exited), "Only enabled shots respond to real entry and tangential departure")
	if enabled: check(exact_hold and absf(entry_peak - 1.5) < 0.002, "The actual camera reaches 1.5 on entry and holds 1.4 relative to its underlying flight lens")
	return result
