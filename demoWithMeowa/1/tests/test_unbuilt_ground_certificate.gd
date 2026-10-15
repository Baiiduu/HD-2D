extends SceneTree

## Compare the independent legacy sampler against the current collision instance
## with its certificate enabled. No game loop or production-file mutation.
const Legacy = preload("res://tests/fixtures/legacy_ground_limit_oracle.gd")
var output := ""
class BareTerrain extends Terrain:
	func _ready() -> void: pass
	func _queue_rebuild() -> void: pass

class OffsetPath extends TerrainPath:
	func ground_position(point: Vector3) -> Vector3:
		return super.ground_position(point) + Vector3.UP
class SpyPath extends TerrainPath:
	var calls := 0
	func ground_position(point: Vector3) -> Vector3:
		calls += 1
		return super.ground_position(point)

var world := Node3D.new()
var terrain: BareTerrain
var path: TerrainPath
var old
var raw
var rounded
var scripts: Array[GDScript] = []
var checks := 0
var mismatches := {"raw": [], "rounded": []}
var total_mismatches := {"raw": 0, "rounded": 0}
var benchmark := false
var benchmark_rows: Array[Dictionary] = []
var warmed_xz_boundary_checks := 0
var warmed_xz_boundary_negative_controls := 0

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	run.call_deferred()

func bind_path() -> void:
	path.terrain = terrain
	path.data = terrain.data
	path._surface_changed()

func plain_data(size := Vector2i(32, 32)) -> TerrainData:
	var data := TerrainData.new()
	data.size = Vector2i.ZERO
	data.resize(Vector2i(-16, -16), size)
	return data

func compare(start: Vector3, direction: Vector3, distance: float, plane: float, tolerance: float, label: String) -> void:
	var expected: float = old.ground_limit(path, start, direction, distance, plane, tolerance)
	for pair in [["rounded", rounded]]:
		var actual: float = pair[1].ground_limit(path, start, direction, distance, plane, tolerance)
		checks += 1
		if var_to_bytes(actual) != var_to_bytes(expected):
			total_mismatches[pair[0]] += 1
			if mismatches[pair[0]].size() < 20:
				mismatches[pair[0]].append({"label": label, "start": str(start), "direction": str(direction), "distance": distance, "plane": plane, "tolerance": tolerance, "old": expected, "new": actual})

func matrix(label: String) -> void:
	for index in 8:
		var local_start := Vector3(-3.2 + float(index % 3) * 0.53, 0.0, -1.1 + float(index / 3) * 0.37)
		var start := terrain.to_global(local_start)
		var direction := (terrain.global_basis * Vector3.RIGHT.rotated(Vector3.UP, TAU * index / 8.0)).normalized()
		var ground := path.ground_position(start).y
		for distance in [0.0, 0.03, 0.149, 0.15, 0.151, 0.9, 3.2, 8.1, 30.0]:
			for tolerance in [0.0, 0.2, -0.01]:
				for offset in [-0.200001, 0.0, 0.200001]:
					compare(start, direction, distance, ground + offset, tolerance, label)
	# Exactly-on-boundary comparisons detect float64 certificate vs real_t Y.
	var start := terrain.to_global(Vector3(-4.1, 0, -3.7))
	var ground := path.ground_position(start).y
	for tolerance in [0.0, 0.00000001, 0.1, 0.2, 0.8]:
		for sign_value in [-1.0, 1.0]:
			for epsilon in [-0.000000001, 0.0, 0.000000001]:
				compare(start, Vector3.RIGHT, 0.73, ground + sign_value * tolerance + epsilon, tolerance, label + " tolerance edge")
	compare(start, Vector3.ZERO, 1.7, ground, 0.2, label + " zero direction")
	compare(start, Vector3(0.2, 0.5, 0.1), 1.7, ground, 0.2, label + " non-normalized 3D direction")
	compare(start, Vector3.RIGHT, -0.2, ground, 0.2, label + " negative distance preserves old path")

func warm_crossing() -> void:
	var start := terrain.to_global(Vector3(-4, 0, 0))
	rounded.ground_limit(path, start, terrain.global_basis.x, 8.0, path.ground_position(start).y, 0.2)

func warmed_xz_boundaries() -> void:
	var before := checks
	for meters in [1.0, 0.5, 1.25, 1.35]:
		for translation in [Vector3.ZERO, Vector3(0.25, 0.375, -0.5)]:
			for axis in [0, 2]:
				for control in ["flat", "water", "height", "outside_map"]:
					terrain.transform = Transform3D(Basis.IDENTITY, translation)
					terrain.data = TerrainData.new()
					terrain.data.cell_size = meters
					terrain.data.size = Vector2i.ZERO
					terrain.data.resize(Vector2i(-16, -16) if control == "outside_map" else Vector2i(-24, -24), Vector2i(48, 48))
					var neighbor := Vector2i(-17, 0) if axis == 0 else Vector2i(0, -17)
					if control == "water": terrain.data.set_overlay(neighbor, TerrainData.OVERLAY_WATER, true)
					if control == "height": terrain.data.set_level(neighbor, -1)
					bind_path()
					var warm_from := Vector3.ZERO
					var warm_to := Vector3.ZERO
					warm_from[axis] = -16.0 * meters
					warm_to[axis] = -15.5 * meters
					var height := path.flat_center_ground_height(terrain.to_global(warm_from), terrain.to_global(warm_to))
					checks += 1
					if height != translation.y: total_mismatches.rounded += 1
					for epsilon in [-0.00001, 0.0, 0.00001]:
						var local_start := Vector3.ZERO
						local_start[axis] = -16.5 * meters + epsilon
						var start := terrain.to_global(local_start)
						var point := Vector2(start.x, start.z)
						var cell := terrain.data.world_to_cell(terrain.to_local(start))
						var starts_blocked := not terrain.data.has_cell(cell) or terrain.data.has_overlay(cell, TerrainData.OVERLAY_WATER) or absf(path.ground_position(start).y - translation.y) > 0.2
						# Prove these cases exercise the removed floating-Rect fast path.
						if starts_blocked and path._flat_rect.has_point(point):
							warmed_xz_boundary_negative_controls += 1
							checks += 1
							if old.ground_limit(path, start, Vector3.RIGHT if axis == 0 else Vector3.BACK, meters * 0.1, translation.y, 0.2) != 0.0: total_mismatches.rounded += 1
						for sign_value in [-1.0, 1.0]:
							var direction := Vector3.ZERO
							direction[axis] = sign_value
							compare(start, direction, meters * 0.1, translation.y, 0.2,
								"warmed XZ boundary %s axis=%s cell=%s offset=%s epsilon=%s" % [control, axis, meters, translation, epsilon])
	warmed_xz_boundary_checks = checks - before
	checks += 1
	if warmed_xz_boundary_negative_controls == 0: total_mismatches.rounded += 1

func measured_batch(module, test_path: TerrainPath, queries: Array, repeats: int) -> float:
	var started := Time.get_ticks_usec()
	var checksum := 0.0
	for repeat in repeats:
		for query in queries:
			checksum += module.ground_limit(test_path, query[0], query[1], query[2], query[3], query[4])
	var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
	if checksum < -1.0: push_error("unreachable checksum")
	return elapsed

func module_benchmark() -> void:
	terrain.transform = Transform3D.IDENTITY
	terrain.data = plain_data()
	var test_path := TerrainPath.new()
	test_path.terrain = terrain
	test_path.data = terrain.data
	var queries := []
	for index in 160:
		var start := Vector3(-5.0 + (index % 16) * 0.45, 0.0, -3.0 + (index / 16) * 0.45)
		var direction := Vector3.RIGHT.rotated(Vector3.UP, TAU * index / 17.0)
		var distance: float = [0.03, 0.17, 0.8, 2.4][index % 4]
		queries.append([start, direction, distance, 0.0, 0.2])
	for module in [old, rounded]: measured_batch(module, test_path, queries, 5)
	for round_index in 3:
		var row := {"round": round_index, "queries_per_batch": queries.size(), "repeats": 30, "samples": []}
		for pair in [["old", old], ["rounded", rounded], ["rounded", rounded], ["old", old]]:
			row.samples.append({"variant": pair[0], "total_ms": measured_batch(pair[1], test_path, queries, 30)})
		benchmark_rows.append(row)
	test_path = null

func run() -> void:
	old = Legacy.new()
	raw = null
	rounded = ProjectileCollision.new()
	rounded.center_certificate_enabled = true
	if not old or not rounded: return
	terrain = BareTerrain.new()
	terrain.data = plain_data()
	world.add_child(terrain)
	root.add_child(world)
	path = TerrainPath.new()
	bind_path()
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_WATER, true)
	var initially_blocked := is_nan(path.flat_center_ground_height(Vector3.ZERO, Vector3.RIGHT))
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_WATER, false)
	var unpoisoned := not is_nan(path.flat_center_ground_height(Vector3.ZERO, Vector3.RIGHT))
	checks += 1
	if not initially_blocked or not unpoisoned: total_mismatches.rounded += 1
	checks += 1
	if path._query.shape != null or path.graph.get_point_count() != 0: total_mismatches.rounded += 1
	for custom in [OffsetPath.new(), SpyPath.new()]:
		custom.terrain = terrain
		custom.data = terrain.data
		var expected: float = old.ground_limit(custom, Vector3.ZERO, Vector3.RIGHT, 1.7, 0.0, 0.2)
		var actual: float = rounded.ground_limit(custom, Vector3.ZERO, Vector3.RIGHT, 1.7, 0.0, 0.2)
		checks += 1
		if not is_nan(custom.flat_center_ground_height(Vector3.ZERO, Vector3.RIGHT)) or var_to_bytes(actual) != var_to_bytes(expected): total_mismatches.rounded += 1
	matrix("plain")
	warm_crossing()
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_WATER, true)
	matrix("same-frame water edit")
	terrain.data.set_level(Vector2i.ZERO, -1)
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_BRIDGE, true)
	matrix("same-frame bridge edit")
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_WATER, false)
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_BRIDGE, false)
	terrain.data.set_level(Vector2i.ZERO, 0)
	warm_crossing()
	terrain.data.set_level(Vector2i(1, 0), 1)
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_RAMP, true)
	matrix("same-frame ramp edit")
	terrain.data.set_overlay(Vector2i.ZERO, TerrainData.OVERLAY_RAMP, false)
	terrain.data.set_level(Vector2i(1, 0), 0)
	warm_crossing()
	terrain.data.set_level(Vector2i.ZERO, 1)
	matrix("same-frame height edit")
	terrain.data.set_level(Vector2i.ZERO, 0)
	warm_crossing()
	var previous := terrain.data
	terrain.data = plain_data()
	terrain.data.set_level(Vector2i.ZERO, 2)
	matrix("data replaced before path rebinding")
	bind_path()
	matrix("data replaced after path rebinding")
	terrain.data = previous
	bind_path()
	terrain.rotation.y = 0.43
	matrix("rotated terrain fallback")
	terrain.rotation = Vector3(0.13, 0.27, 0.0)
	matrix("tilted terrain fallback")
	terrain.transform = Transform3D(Basis.from_scale(Vector3(1.2, 0.9, 0.8)), Vector3(0.3, 0.17, -0.2))
	matrix("scaled terrain fallback")
	terrain.transform = Transform3D(Basis.IDENTITY, Vector3(0.3, 0.17, -0.2))
	for cell in terrain.data.size.x:
		for row in terrain.data.size.y: terrain.data.set_level(terrain.data.origin + Vector2i(cell, row), 1)
	matrix("translated elevated flat float boundary")
	terrain.data.layer_height = 0.13
	matrix("same-frame layer height metadata edit")
	terrain.data.cell_size = 1.35
	matrix("same-frame cell size metadata edit")
	warm_crossing()
	terrain.data.resize(Vector2i(-4, -4), Vector2i(8, 8))
	matrix("same-frame origin and size edit")
	warmed_xz_boundaries()
	# One isolated query proves the accepted fast path skips the old sampler.
	terrain.transform = Transform3D.IDENTITY
	terrain.data = plain_data()
	bind_path()
	rounded.ground_limit(path, Vector3.ZERO, Vector3.RIGHT, 1.7, 0.0, 0.2)
	# A warm accepted rectangle does not touch the old ground-position cache.
	path._height_frame = -1
	path._surface_cache.clear()
	var accepted: float = rounded.ground_limit(path, Vector3.ZERO, Vector3.RIGHT, 1.7, 0.0, 0.2)
	checks += 1
	var skipped := accepted == 1.7 and path._height_frame == -1
	if benchmark and total_mismatches.rounded == 0 and skipped: module_benchmark()
	var report := {"checks": checks, "mismatch_counts": total_mismatches, "mismatch_examples": mismatches,
		"warm_flat_skips_sampler": skipped, "benchmarks": benchmark_rows,
		"warmed_xz_boundary_checks": warmed_xz_boundary_checks,
		"warmed_xz_boundary_negative_controls": warmed_xz_boundary_negative_controls,
		"notes": "Module comparison only; no FPS or collision-query reduction is claimed. Raw is an exploratory float-boundary control."}
	if not output.is_empty(): FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("Ground limit certificate: ", JSON.stringify(report))
	path = null
	world.free()
	old = null
	raw = null
	rounded = null
	scripts.clear()
	quit(0 if total_mismatches.rounded == 0 and skipped else 1)
