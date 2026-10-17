extends "res://tests/test_preview_query_view.gd"

const LoaderPath := "res://scripts/combat/native_swarm_loader.gd"

func compare_plan(kernel: RefCounted, reference: CrowdBatchPlanner, label: String) -> void:
	var source := session._spatial_index
	var expected := reference.plan(source._cells, source._positions, source._ids, source._active, source._spacing, source._bodies, source.CELL_SIZE, source._crowd_revision)
	var actual: PackedVector3Array = kernel.plan(source._cells, source._positions, source._ids, source._active, source._spacing, source._bodies, source.CELL_SIZE, source._crowd_revision)
	check(expected.size() == actual.size(), "Native force plan retains every stable slot: " + label)
	for slot in expected.size(): check(expected[slot].is_equal_approx(actual[slot]), "Pair forces retain the dense-crowd formula: " + label)

func run() -> void:
	check(ResourceLoader.exists(LoaderPath), "Optional native swarm adapter exists")
	if not ResourceLoader.exists(LoaderPath): quit(1); return
	var loader: GDScript = load(LoaderPath)
	var kernel: RefCounted = loader.create()
	check(kernel != null, "Built native CPU prototype loads without enabling a map")
	if not kernel: quit(1); return
	var rejected: PackedVector3Array = kernel.plan({Vector2i.ZERO:[-1]}, PackedVector3Array([Vector3.ZERO]), PackedInt64Array([1]), PackedByteArray([1]), PackedFloat64Array([1]), PackedFloat64Array([0.3]), 1.0, 0)
	check(rejected.is_empty(), "Invalid native slot is rejected before array access")
	rejected = kernel.plan({}, PackedVector3Array([Vector3(NAN,0,0)]), PackedInt64Array([1]), PackedByteArray([1]), PackedFloat64Array([1]), PackedFloat64Array([0.3]), 1.0, 0)
	check(rejected.is_empty(), "Nonfinite native packet is rejected")
	await fixture()
	await populate(128)
	var source := session._spatial_index
	var reference := CrowdBatchPlanner.new()
	for step in 12:
		compare_plan(kernel, reference, "moving snapshot")
		var actor := session.enemies[step]
		actor.global_position += Vector3(0.02, 0, 0.01)
		actor.commit_spatial_state()
	session.enemies[0].global_position = session.enemies[1].global_position
	session.enemies[0].commit_spatial_state()
	compare_plan(kernel, reference, "coincident actors use the same ID tie-break")
	session.enemies[1].spawn_delay = 0.2
	session.enemies[1].commit_spatial_state()
	compare_plan(kernel, reference, "activation change revokes neighbors")
	session.enemies[2].set("body_radius", 0.6)
	session.enemies[2].commit_spatial_state()
	compare_plan(kernel, reference, "body metadata change revokes neighbors")
	session.enemies[3].take_damage(session.enemies[3].health)
	compare_plan(kernel, reference, "same-step lethal removal cannot retain a force")
	session._native_kernel = kernel
	session.native_swarm_enabled = true
	check(session.enemies[4]._native_swarm == kernel and source.get("native_kernel") == kernel, "Enabling the prototype binds existing actors and the live index")
	var subject := session.enemies[4] as CreatureEnemy
	subject._move_chase(1.0 / 60.0, 0.5)
	var metrics: Dictionary = kernel.get_metrics()
	session.native_swarm_enabled = false
	check(subject._native_swarm == null and source.get("native_kernel") == null, "Disabling the prototype immediately restores both legacy paths")
	subject._move_chase(1.0 / 60.0, 0.5)
	check(kernel.get_metrics() == metrics, "Legacy movement makes no further calls to the optional native kernel")
	clear_enemies()
	world.queue_free()
	await settle()
	print("Native swarm kernel: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
