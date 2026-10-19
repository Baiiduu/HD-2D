extends "res://tests/test_creature_flat_chase.gd"

var certified := 0
var fixed_wall: StaticBody3D

class BlockedPath extends TerrainPath:
	func _segment_clear(_from: Vector3, _to: Vector3) -> bool:
		return false

func rebuild() -> void:
	path.build(terrain, 0.32, [player.get_rid()])
	path.prefetch_enabled = false

func compare(from: Vector3, to: Vector3, label: String) -> void:
	path.chase_batch_enabled = false
	var expected := path.can_walk_direct(from, to)
	path.chase_batch_enabled = true
	var actual := path.can_walk_direct(from, to)
	check(actual == expected, label)
	if path._chase_batch.certifies(from, to):
		certified += 1
		var saved_transform := path._query.transform
		var saved_motion := path._query.motion
		path._query.transform = Transform3D(Basis.IDENTITY, from + Vector3.UP * path._clearance)
		path._query.motion = to - from
		var space := world.get_world_3d().direct_space_state
		check(space.cast_motion(path._query)[0] >= 0.999, "positive packet agrees with actual native sphere sweep")
		path._query.motion = Vector3.ZERO
		check(space.intersect_shape(path._query,1).is_empty(), "positive packet has no native origin overlap")
		path._query.transform = saved_transform
		path._query.motion = saved_motion

func query_checks() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 20261018
	for sample in 500:
		var from := Vector3(random.randf_range(-9.7,9.7), 0.02, random.randf_range(-9.7,9.7))
		var to := from + Vector3(random.randf_range(-2,2), 0, random.randf_range(-2,2))
		compare(from, to, "numeric packet matches original sweep/surface query")
	check(certified > 200, "real empty ground uses the numeric backend")
	var starts := PackedVector3Array([Vector3(-4,0.02,-4), Vector3(3,0.02,-4), Vector3(-9.5,0.02,-9.5)])
	for from in starts:
		var targets := PackedVector3Array([from + Vector3.LEFT * 2, from + Vector3.BACK])
		var expected := -1
		for index in targets.size():
			if path._legacy_can_walk_direct(from, path.ground_position(targets[index])):
				expected = index
				break
		check(path.first_walkable_ground(from, targets) == expected, "ordered candidate batch preserves selection and boundary fallback")
	for x in [-8.5, -0.5, 0.5, 8.5]:
		var center: float = x + path._query.shape.radius
		compare(Vector3(center,0.02,-3), Vector3(center,0,-2.8), "round-away-from-zero half-cell boundary")
	compare(Vector3.INF, Vector3.ZERO, "invalid origin stays rejected")
	check(path.first_walkable_ground(Vector3.INF,PackedVector3Array([Vector3.ZERO])) == -1, "invalid batch origin stays rejected")
	check(path.first_walkable_ground(Vector3.ZERO,PackedVector3Array([Vector3.INF])) == -1, "invalid batch candidate is not sampled or swept")

func invalidation_checks() -> void:
	var from := Vector3(-4,0.02,0)
	var to := Vector3(-2,0,0)
	check(path.can_walk_direct(from,to) and path._chase_batch.valid, "warm packet available")
	var barrier := wall(Vector3(-3,0,0), Vector3(0.04,2,2))
	barrier.force_update_transform()
	check(not path.can_walk_direct(from,to) and not path._chase_batch.valid, "same-step new live wall immediately uses real queries")
	barrier.free()
	check(path.can_walk_direct(from,to) and path._chase_batch.valid, "removal immediately permits a fresh packet")
	var field := terrain.obstacle_field()
	field.enabled = false
	check(path.can_walk_direct(from,to) and not path._prepare_chase_batch(), "disabled field cannot reuse a prior positive packet")
	field.enabled = true
	# Terrain signals must revoke even already-prepared packets in this step.
	terrain.data.set_overlay(Vector2i(-3,0), TerrainData.OVERLAY_WATER, true)
	check(not path._chase_batch.valid, "terrain edit revokes the packet synchronously")
	await settle()
	rebuild()
	compare(from,to,"water shortcut still rejected")
	check(not path.can_walk_direct(from,to), "batch cannot cross water")
	var dry_from := Vector3(-6,0.02,2)
	var dry_to := Vector3(-5.5,0,2)
	compare(dry_from,dry_to,"dry route beside pond retains the native result")
	check(is_nan(path._flat_chunk_height(Vector2i(-1,0))) and path._chase_batch.certifies(dry_from,dry_to), "cell support certifies dry ground inside an old mixed-water chunk")
	check(is_zero_approx(path.flat_ground_height(dry_from,dry_to,0.4)), "body ground qualification reuses the same per-cell data")
	check(is_nan(path.flat_ground_height(from,to,0.4)), "shared body support still rejects crossing the water cell")
	var dry_actor := creature("leaf_charger",Vector3(-6,0.001,2))
	motion(dry_actor,Vector3.RIGHT)
	check(dry_actor._ground_moved,"ordinary body uses its unchanged horizontal solver beside water")
	intact(dry_actor,"per-cell body support beside water")
	clear_actors()
	terrain.data.set_overlay(Vector2i(-3,0), TerrainData.OVERLAY_WATER, false)
	await settle()
	rebuild()
	check(path.can_walk_direct(from,to), "restored land is usable")
	path._query.shape.radius = 0.42
	path.invalidate_query_certificate()
	compare(from,to,"query-radius edit rebuilds packet configuration")
	terrain.position = Vector3(2,1,-2)
	terrain.force_update_transform()
	compare(from + terrain.position,to + terrain.position,"translated terrain preserves local indexing")
	terrain.position = Vector3.ZERO
	terrain.force_update_transform()
	var replacement: TerrainData = terrain.data.duplicate()
	terrain.data = replacement
	check(not path._prepare_chase_batch(), "same-step resource replacement cannot reuse the old terrain packet")
	await settle()
	rebuild()
	var custom := BlockedPath.new()
	custom.build(terrain,0.32,[player.get_rid()])
	check(not custom.can_walk_direct(from,to), "custom query overrides stay on their original implementation")

func fixed_wall_checks() -> void:
	var from := Vector3(-4,0.02,0)
	var to := Vector3(-2,0,0)
	check(path.can_walk_direct(from,to) and path._chase_batch.valid, "fixed layout packet available before a wall edit")
	fixed_wall.position = Vector3(-3,0.5,0)
	fixed_wall.force_update_transform()
	check(not path.can_walk_direct(from,to) and not path._chase_batch.valid, "moving a baked wall revokes the current-step packet and uses live collision")

func run() -> void:
	world = Node3D.new()
	terrain = Terrain.new()
	terrain.data = TerrainData.new()
	terrain.data.size = Vector2i.ZERO
	terrain.data.resize(Vector2i(-10,-10),Vector2i(21,21))
	world.add_child(terrain)
	root.add_child(world)
	current_scene = world
	player = Player.new()
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	player.add_child(sprite)
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	# Fixed walls exist before the obstacle field captures its initial layout.
	fixed_wall = wall(Vector3.ZERO,Vector3(0.1,2,3))
	await settle()
	rebuild()
	query_checks()
	await invalidation_checks()
	await wall_yield_checks()
	fixed_wall_checks()
	clear_actors()
	world.queue_free()
	await settle()
	print("PURSUIT_QUERY_BATCH ",JSON.stringify({"checks":checks,"certified":certified,"failures":failures}))
	quit(0 if failures.is_empty() else 1)
