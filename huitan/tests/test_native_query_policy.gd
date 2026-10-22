extends "res://tests/test_obstacle_certificates.gd"
## Pure ray/navigation query policy must not change the body movement policy.

func certificate_checks() -> void:
	var property := &"obstacle_query_backend"
	var available := terrain.get_property_list().any(func(info): return info.name == property)
	check(available, "Pure queries can select native physics independently of body movement")
	if not available: return
	check(terrain.get(property) == 0, "Existing maps retain the previous query policy by default")
	terrain.set(property, 2)
	terrain.query_diagnostics_enabled = true
	var actor := creature("leaf_charger", Vector3(-4,0.001,-4))
	var heading := Vector3.RIGHT
	var from := Vector3(-4,0.45,-4)
	var to := from + heading * 0.5
	var excluded: Array[RID] = [player.get_rid()]
	terrain.reset_query_metrics()
	check(terrain.ray_clear(from, to, 1, excluded), "Native ray retains an empty-space result")
	var counts := terrain.get_query_metrics()
	check(counts.ray_native == 1 and counts.ray_certified == 0, "Query switch actually bypasses script ray proofs")
	check(not path._query_certified_clear(from, to), "Navigation also bypasses script absence proofs")
	check(path._segment_clear(from - Vector3.UP * 0.45, to - Vector3.UP * 0.45), "Native navigation keeps the open route")
	motion(actor, heading)
	check(actor._flat_motion._certified_clear, "The same switch retains the established body movement proof")
	var barrier := wall(Vector3(-3,0,-4), Vector3(0.02,2,2))
	barrier.force_update_transform()
	check(not terrain.ray_clear(from, from + heading * 2, 1, excluded), "New live wall immediately blocks native rays")
	check(not path._segment_clear(Vector3(-4,0,-4), Vector3(-2,0,-4)), "New live wall immediately blocks native navigation")
	motion(actor, heading, 120)
	check(actor.position.x < -3.35 and not actor._flat_motion._certified_clear, "Body proof still falls back to a real sweep at the wall")
	barrier.free()
	await settle()
	terrain.set(property, 1)
	terrain.reset_query_metrics()
	check(terrain.ray_clear(from, to, 1, excluded) and terrain.get_query_metrics().ray_native == 1, "Ray-only policy actually uses native rays")
	check(path._query_certified_clear(Vector3(-4,0,-4), Vector3(-3.5,0,-4)), "Ray-only policy retains established navigation proofs")
	terrain.set(property, 0)
	terrain.obstacle_certificates_enabled = false
	reset_actor(actor, Vector3(-4,0.001,-4), true)
	terrain.reset_query_metrics()
	check(terrain.ray_clear(from, to, 1, excluded), "Master legacy switch still selects native rays")
	check(terrain.get_query_metrics().ray_native == 1, "Query opt-in cannot override the master disable switch")
	motion(actor, heading)
	check(not actor._flat_motion._certified_clear, "Master legacy switch still selects native body sweeps")
	terrain.obstacle_certificates_enabled = true
	clear_actors()
