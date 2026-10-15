extends RefCounted

## QA oracle for an actual, unscaled CapsuleShape3D. This is not a motor.
## K = segment + ball(r); exact isotropic erosion is segment + ball(r-eps).
## Keeping the original shape transform, r-=eps and h-=2eps preserve the
## capsule's center/axis segment. No obstacle, real body, or margin is edited.
## Raw manifold point-pair lengths remain diagnostics, never the MTD verdict.
const DEFAULT_EPSILON := 0.003
const TRANSFORM_TOLERANCE := 0.000001

static func _unsupported(reason: String) -> Dictionary:
	return {"supported": false, "passed": false, "intrudes": true, "reason": reason,
		"raw_pairs": [], "raw_max_pair_distance": 0.0, "outer_hits": [], "inner_hits": []}

static func inspect(space: PhysicsDirectSpaceState3D, collider: CollisionShape3D,
		excluded: Array[RID], epsilon := DEFAULT_EPSILON, mask := 1) -> Dictionary:
	if not space or not is_instance_valid(collider) or not collider.is_inside_tree():
		return _unsupported("missing live collision shape/space")
	if not collider.shape is CapsuleShape3D:
		return _unsupported("only actual capsule shapes have a proved erosion")
	if not is_finite(epsilon) or epsilon <= 0.0:
		return _unsupported("epsilon must be finite and positive")
	var capsule := collider.shape as CapsuleShape3D
	var transform := collider.global_transform
	if not transform.is_finite(): return _unsupported("nonfinite transform")
	var basis := transform.basis
	# Arbitrary rigid rotation is supported. Scale, reflection, and shear have
	# deliberately not been guessed from the scene or silently normalized.
	if absf(basis.x.length_squared() - 1.0) > TRANSFORM_TOLERANCE \
			or absf(basis.y.length_squared() - 1.0) > TRANSFORM_TOLERANCE \
			or absf(basis.z.length_squared() - 1.0) > TRANSFORM_TOLERANCE \
			or absf(basis.x.dot(basis.y)) > TRANSFORM_TOLERANCE \
			or absf(basis.y.dot(basis.z)) > TRANSFORM_TOLERANCE \
			or absf(basis.z.dot(basis.x)) > TRANSFORM_TOLERANCE \
			or basis.determinant() <= 0.0:
		return _unsupported("scaled/reflected/sheared capsule needs a separate proved oracle")
	if not is_finite(capsule.radius) or not is_finite(capsule.height) \
			or capsule.radius <= epsilon or capsule.height < capsule.radius * 2.0:
		return _unsupported("invalid/too-small capsule for exact erosion")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = transform
	query.collision_mask = mask
	query.collide_with_bodies = true
	query.collide_with_areas = false
	query.exclude = excluded
	query.margin = 0.0
	var outer_hits := space.intersect_shape(query, 16)
	var pairs: Array[Vector3] = []
	var raw_max := 0.0
	if not outer_hits.is_empty():
		pairs = space.collide_shape(query, 128)
		for pair in range(0, pairs.size(), 2):
			raw_max = maxf(raw_max, pairs[pair].distance_to(pairs[pair + 1]))
	var inner := CapsuleShape3D.new()
	inner.radius = capsule.radius - epsilon
	inner.height = capsule.height - epsilon * 2.0
	# Exact eps, with no tolerance added to the threshold. Native float error
	# remains bounded by the independent controls around the 3 mm boundary.
	query.shape = inner
	var inner_hits := space.intersect_shape(query, 1)
	return {"supported": true, "passed": inner_hits.is_empty(), "intrudes": not inner_hits.is_empty(),
		"epsilon": epsilon, "reason": "", "raw_pairs": pairs, "raw_max_pair_distance": raw_max,
		"outer_hits": outer_hits, "inner_hits": inner_hits, "inner_radius": inner.radius,
		"inner_height": inner.height, "original_transform": transform}
