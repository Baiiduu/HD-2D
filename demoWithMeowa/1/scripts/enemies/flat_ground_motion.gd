class_name FlatGroundMotion
extends RefCounted

## A terrain certificate replaces floor recovery/snap; the real body still
## sweeps live obstacles, including overlap recovery while standing still.
## All trial movement stays local until every segment has been certified.
var _parameters := PhysicsTestMotionParameters3D.new()
var _result := PhysicsTestMotionResult3D.new()
var _floor_rid := RID()
var _ordinary_target_rid := RID()
var _certified_clear := false

func try_move(body: CharacterBody3D, path: TerrainPath, delta: float, radius: float, ordinary_target: CollisionObject3D = null) -> bool:
	_certified_clear = false
	var start := body.global_transform
	var motion := Vector3(body.velocity.x, 0.0, body.velocity.z) * delta
	var width := radius + body.safe_margin
	var floor_y := path.flat_ground_height(start.origin, start.origin + motion, width)
	if is_nan(floor_y) or start.origin.y < floor_y - body.safe_margin or start.origin.y > floor_y + maxf(0.0025, body.safe_margin * 2.0): return false
	var support := path.terrain.ground_collision_body()
	if not is_instance_valid(support): return false
	if (body.collision_mask & support.collision_layer) == 0: return false
	var support_rid := support.get_rid()
	var target_rid := ordinary_target.get_rid() if is_instance_valid(ordinary_target) else RID()
	if support_rid != _floor_rid or target_rid != _ordinary_target_rid:
		_floor_rid = support_rid
		_ordinary_target_rid = target_rid
		var excluded: Array[RID] = [support_rid]
		if target_rid.is_valid(): excluded.append(target_rid)
		_parameters.exclude_bodies = excluded
	if path.terrain.obstacle_certificates_enabled and path.terrain.obstacle_field().clear_motion(body, support, motion):
		body.global_position = start.origin + motion
		body.velocity.y = 0.0
		_certified_clear = true
		return true
	_parameters.margin = body.safe_margin
	_parameters.recovery_as_collision = true
	var transform := start
	var speed := Vector3(body.velocity.x, 0.0, body.velocity.z)
	for slide in body.max_slides:
		_parameters.from = transform
		_parameters.motion = motion
		var hit := PhysicsServer3D.body_test_motion(body.get_rid(), _parameters, _result)
		var travel := _result.get_travel()
		# Steps, tilted surfaces and vertical overlap recovery need normal physics.
		if absf(travel.y) > 0.00001: return false
		var next := transform.origin + travel
		if travel != motion and path.flat_ground_height(transform.origin, next, width) != floor_y: return false
		transform.origin = next
		if not hit: break
		var normal := _result.get_collision_normal()
		if absf(normal.y) > 0.01: return false
		motion = _result.get_remainder().slide(normal)
		speed = speed.slide(normal)
		if motion.is_zero_approx(): break
		if path.flat_ground_height(transform.origin, transform.origin + motion, width) != floor_y: return false
	# No collision mask, exception, shape or native contact state is modified.
	body.global_transform = transform
	body.velocity = speed
	return true
