extends SceneTree

var checks := 0
var failures: Array[String] = []
var world: Node3D
var terrain: Terrain
var path: CountingPath
var reduced_origins := 0
var reduced_contacts := 0

class CountingPath extends TerrainPath:
	var origin := Vector3.INF
	var sweeps := 0
	var overlaps := 0
	var origin_checks := 0
	var contacts := 0
	func reset(point: Vector3) -> void:
		origin = point
		sweeps = 0
		overlaps = 0
		origin_checks = 0
		contacts = 0
	func counts() -> Vector4i:
		return Vector4i(sweeps, overlaps, origin_checks, contacts)
	func _segment_clear(from: Vector3, to: Vector3) -> bool:
		sweeps += 1
		return super._segment_clear(from, to)
	func _point_blocked(point: Vector3) -> bool:
		overlaps += 1
		if point == origin: origin_checks += 1
		return super._point_blocked(point)
	func _start_contact_points(from: Vector3) -> PackedVector3Array:
		contacts += 1
		return super._start_contact_points(from)
	# The original candidate ordering/standalone checks are the exact oracle.
	func legacy_start_id(from: Vector3, closest: int) -> int:
		var cell := data.world_to_cell(terrain.to_local(from))
		if not data.has_cell(cell) or (data.has_overlay(cell, TerrainData.OVERLAY_WATER) and not data.has_overlay(cell, TerrainData.OVERLAY_BRIDGE)): return -1
		if _field_has(closest) and _pursuit_start_clear(from, graph.get_point_position(closest)): return closest
		for id in _nearby_endpoint_ids(from):
			if id == closest or not _field_has(id): continue
			var point := graph.get_point_position(id)
			if _endpoint_surface_clear(from, point) and _pursuit_start_clear(from, point): return id
		return -1
	func legacy_connected_id(from: Vector3, end: int) -> int:
		var cell := data.world_to_cell(terrain.to_local(from))
		if not data.has_cell(cell) or (data.has_overlay(cell, TerrainData.OVERLAY_WATER) and not data.has_overlay(cell, TerrainData.OVERLAY_BRIDGE)): return -1
		var closest := closest_point(from)
		if closest >= 0 and not graph.get_id_path(end, closest).is_empty() and _pursuit_start_clear(from, graph.get_point_position(closest)): return closest
		for id in _nearby_endpoint_ids(from):
			if id == closest: continue
			var point := graph.get_point_position(id)
			if _endpoint_surface_clear(from, point) and _pursuit_start_clear(from, point) and not graph.get_id_path(end, id).is_empty(): return id
		return -1

func _initialize() -> void:
	create_timer(20.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func settle() -> void:
	for frame in 3: await physics_frame

func compare(point: Vector3, goal: int, label: String) -> void:
	var closest := path.closest_point(point)
	for connected in [false, true]:
		path.reset(point)
		var expected := path.legacy_connected_id(point, goal) if connected else path.legacy_start_id(point, closest)
		var before := path.counts()
		path.reset(point)
		var actual := path._connected_start_id(point, goal) if connected else path._pursuit_start_id(point, closest)
		var after := path.counts()
		check(actual == expected, label + " preserves exact chosen start, connected=" + str(connected))
		check(after.x == before.x, label + " retains every direction sweep")
		check(after.y - after.z == before.y - before.z, label + " retains every endpoint overlap")
		check(after.z <= 1 and after.w <= 1, label + " origin overlap/contacts queried at most once")
		if after.z < before.z: reduced_origins += 1
		if after.w < before.w: reduced_contacts += 1

func box(point: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1, 2, 2)
	collision.shape = shape
	wall.add_child(collision)
	world.add_child(wall)
	wall.position = point
	return wall

func run() -> void:
	world = Node3D.new()
	terrain = Terrain.new()
	terrain.data = TerrainData.new()
	terrain.data.size = Vector2i.ZERO
	terrain.data.resize(Vector2i(-2, -2), Vector2i(6, 6))
	world.add_child(terrain)
	root.add_child(world)
	current_scene = world
	await settle()
	path = CountingPath.new()
	path.prefetch_enabled = false
	path.build(terrain, 0.28, [])
	var goal := path.closest_point(Vector3(-1.5, 0, 1.5))
	path._prepare_pursuit_field(path.graph.get_point_position(goal))
	compare(Vector3(-1.6, 0, 0.1), goal, "Open ground")
	var wall := box(Vector3(0, 1, 0))
	await settle()
	for x in [-0.77, -0.76, -0.74]:
		for z in [0.0, 0.12, 0.36]: compare(Vector3(x, 0, z), goal, "Wall padding")
	compare(Vector3(0.1, 0, 0.1), goal, "Fully covered origin")
	check(reduced_origins > 0 and reduced_contacts > 0, "Real wall candidates reduce repeated origin overlap and contacts")
	# A new call must observe current geometry, even within the same frame.
	var point := Vector3(-0.76, 0, 0.12)
	path.reset(point)
	path._pursuit_start_id(point, path.closest_point(point))
	var first := path.origin_checks
	path.reset(point)
	path._pursuit_start_id(point, path.closest_point(point))
	check(first == 1 and path.origin_checks == 1, "Separate solves in one frame each query their own origin")
	wall.position = Vector3(-0.76, 1, 0.12)
	await settle()
	compare(point, goal, "Moved dynamic wall")
	check(path._pursuit_start_id(point, path.closest_point(point)) == -1, "Moving wall over the origin is not hidden by earlier solves")
	wall.free()
	await settle()
	compare(point, goal, "Removed wall")
	check(path._pursuit_start_id(point, path.closest_point(point)) >= 0, "Removing wall restores a live start")
	path = null
	world.queue_free()
	await settle()
	print("Pursuit start query reuse: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
