extends SceneTree

## Compare actual generated collisions with the unchanged per-cell render geometry.
const LEFT := Vector3(-100.0, 0.0, 0.0)
const RIGHT := Vector3(100.0, 0.0, 0.0)
const EPSILON := 0.00015
var checks := 0
var failures := 0
var world: Node3D
var terrain: Terrain
var reference: StaticBody3D
var compact: StaticBody3D
var raw := PackedVector3Array()
var reduced := PackedVector3Array()
var bounds := Rect2()
var floor_y := 0.0
var bottom_y := 0.0

func _initialize() -> void:
	create_timer(60.0).timeout.connect(func(): quit(2))
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func settle(count := 3) -> void:
	for frame in count: await physics_frame

func original_faces(source: Terrain) -> PackedVector3Array:
	var result := PackedVector3Array()
	for name in ["Top", "Walls", "Bridges"]:
		var visual := source._generated.get_node_or_null(name) as MeshInstance3D
		if not visual: continue
		for surface in visual.mesh.get_surface_count():
			var arrays := visual.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			if indices == null or indices.is_empty():
				for vertex in vertices: result.append(visual.transform * vertex)
			else:
				for index in indices: result.append(visual.transform * vertices[index])
	return result

func actual_faces() -> PackedVector3Array:
	return (terrain._generated.get_node("Body").get_child(0).shape as ConcavePolygonShape3D).get_faces()

func body(faces: PackedVector3Array, offset: Vector3) -> StaticBody3D:
	var result := StaticBody3D.new()
	result.collision_layer = 1
	result.collision_mask = 0
	var collider := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	collider.shape = shape
	result.add_child(collider)
	result.position = offset
	world.add_child(result)
	return result

func area_by_normal(faces: PackedVector3Array) -> Dictionary:
	var result := {}
	for index in range(0, faces.size(), 3):
		var cross := (faces[index + 1] - faces[index]).cross(faces[index + 2] - faces[index])
		var normal := cross.normalized().snapped(Vector3.ONE * 0.01)
		result[normal] = float(result.get(normal, 0.0)) + cross.length() * 0.5
	return result

func structure_checks() -> void:
	check(terrain.data.size == Vector2i(31, 31), "fixture reads the current 31 by 31 formal terrain")
	check(raw.size() == 2170 * 3 and reduced.size() == 10 * 3, "formal collision reduces 2170 triangles to 10 without touching render vertices")
	var before := area_by_normal(raw)
	var after := area_by_normal(reduced)
	var same := before.size() == after.size()
	for normal: Vector3 in before:
		same = same and after.has(normal) and absf(before[normal] - after.get(normal, 0.0)) < 0.003
	check(same, "triangle winding and surface area agree on every outward plane")
	check(before.size() == 5, "the unchanged geometry has a top and four sides, with an open bottom")
	var source_body := terrain._generated.get_node("Body") as StaticBody3D
	check(source_body.get_child_count() == 1, "dry formal terrain keeps exactly one concave shape and no per-cell blockers")
	check(not (source_body.get_child(0).shape as ConcavePolygonShape3D).backface_collision, "compaction retains the original one-sided concave collision")

func ray(from: Vector3, to: Vector3, offset: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from + offset, to + offset, 1)
	query.hit_back_faces = false
	return world.get_world_3d().direct_space_state.intersect_ray(query)

func compare_ray(from: Vector3, to: Vector3, label: String) -> void:
	var expected := ray(from, to, LEFT)
	var actual := ray(from, to, RIGHT)
	var equal := expected.is_empty() == actual.is_empty()
	if not expected.is_empty() and not actual.is_empty():
		equal = equal and (expected.position - LEFT).distance_to(actual.position - RIGHT) <= EPSILON
		equal = equal and expected.normal.distance_to(actual.normal) <= EPSILON
	check(equal, label)

func ray_checks() -> void:
	var middle := Vector3(bounds.get_center().x, floor_y, bounds.get_center().y)
	var visible_floor := ray(middle + Vector3.UP * 2, middle - Vector3.UP * 2, RIGHT)
	check(not visible_floor.is_empty() and visible_floor.normal.dot(Vector3.UP) > 0.999, "the comparison actually hits the floor with its upward normal")
	var side_hit := ray(Vector3(bounds.position.x - 1, floor_y - 0.8, middle.z), Vector3(bounds.position.x + 1, floor_y - 0.8, middle.z), RIGHT)
	check(not side_hit.is_empty() and side_hit.normal.dot(Vector3.LEFT) > 0.999, "the comparison actually hits the exterior skirt wall")
	# Every cell centre and the old internal seams, including their diagonals.
	for z in terrain.data.size.y:
		for x in terrain.data.size.x:
			var point := Vector3((terrain.data.origin.x + x) * terrain.data.cell_size, floor_y, (terrain.data.origin.y + z) * terrain.data.cell_size)
			compare_ray(point + Vector3.UP * 2.0, point - Vector3.UP * 2.0, "cell-centre position and normal %d,%d" % [x, z])
	for fraction in [0.0, 0.001, 0.25, 0.5, 0.75, 0.999, 1.0]:
		var z := lerpf(bounds.position.y, bounds.end.y, fraction)
		var x := lerpf(bounds.position.x, bounds.end.x, fraction)
		var y := lerpf(bottom_y, floor_y, 0.5)
		compare_ray(Vector3(bounds.position.x - 1, y, z), Vector3(bounds.position.x + 1, y, z), "west edge %.3f" % fraction)
		compare_ray(Vector3(bounds.end.x + 1, y, z), Vector3(bounds.end.x - 1, y, z), "east edge %.3f" % fraction)
		compare_ray(Vector3(x, y, bounds.position.y - 1), Vector3(x, y, bounds.position.y + 1), "north edge %.3f" % fraction)
		compare_ray(Vector3(x, y, bounds.end.y + 1), Vector3(x, y, bounds.end.y - 1), "south edge %.3f" % fraction)
		var point := Vector3(x, floor_y, z)
		compare_ray(point + Vector3.UP * 2, point - Vector3.UP * 2, "old tile seams and diagonal %.3f" % fraction)
	var centre := Vector3(bounds.get_center().x, floor_y, bounds.get_center().y)
	compare_ray(centre - Vector3.UP * 3, centre - Vector3.UP * 0.2, "bottom remains open below the floor")
	check(ray(centre - Vector3.UP * 3, centre - Vector3.UP * 0.2, RIGHT).is_empty(), "no new bottom face is introduced")
	compare_ray(centre - Vector3.UP * 3, centre + Vector3.UP * 2, "floor backface ray preserves one-sided behaviour")
	check(ray(centre - Vector3.UP * 3, centre + Vector3.UP * 2, RIGHT).is_empty(), "a ray from underneath does not hit the floor backface")

func actor(point: Vector3, offset: Vector3, radius := 0.28) -> CharacterBody3D:
	var result := CharacterBody3D.new()
	result.collision_layer = 2
	result.collision_mask = 1
	result.floor_snap_length = 0.25
	var collider := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(0.7, radius * 2.0)
	collider.shape = shape
	collider.position.y = shape.height * 0.5
	result.add_child(collider)
	result.position = point + offset
	world.add_child(result)
	return result

func compare_motion(point: Vector3, direction: Vector3, gravity: float, label: String, radius := 0.28) -> void:
	var expected := actor(point, LEFT, radius)
	var actual := actor(point, RIGHT, radius)
	await settle(2)
	var max_position := 0.0
	var max_velocity := 0.0
	var same_flags := true
	# Both native bodies advance with the same physics-frame delta and full collision.
	for step in 90:
		for current in [expected, actual]:
			current.velocity.y = 0.0 if current.is_on_floor() else current.velocity.y - gravity / 60.0
			current.velocity.x = direction.x
			current.velocity.z = direction.z
			current.move_and_slide()
		max_position = maxf(max_position, (expected.position - LEFT).distance_to(actual.position - RIGHT))
		max_velocity = maxf(max_velocity, expected.velocity.distance_to(actual.velocity))
		same_flags = same_flags and expected.is_on_floor() == actual.is_on_floor() and expected.is_on_wall() == actual.is_on_wall()
	check(max_position <= 0.0005 and max_velocity <= 0.001 and same_flags, "%s: matching position, velocity, floor and wall; max errors %.7f / %.7f" % [label, max_position, max_velocity])
	if gravity > 0.0 and point.x < bounds.end.x - 3.0:
		check(expected.is_on_floor() and actual.is_on_floor(), label + ": both capsules really settle on the floor")
	if gravity == 0.0:
		check(expected.is_on_wall() and actual.is_on_wall(), label + ": both capsules really contact the exterior wall")
	if direction.length_squared() > 0.0:
		check((actual.position - RIGHT).distance_to(point) > 0.1, label + ": the trajectory contains actual native body motion")
	expected.free()
	actual.free()
	await settle(2)

func obstacle(offset: Vector3) -> StaticBody3D:
	var result := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.15, 2.0, 4.0)
	collider.shape = shape
	result.add_child(collider)
	result.position = offset + Vector3(0, floor_y + 1, bounds.get_center().y)
	world.add_child(result)
	return result

func movement_checks() -> void:
	var z := bounds.get_center().y
	await compare_motion(Vector3(-5, floor_y + 0.02, z), Vector3(1.7, 0, 0), 20, "straight over old tile seams")
	await compare_motion(Vector3(-5, floor_y + 0.02, z), Vector3(1.2, 0, 1.2), 20, "diagonal over old triangles")
	await compare_motion(Vector3(0, floor_y + 2, z), Vector3.ZERO, 20, "vertical landing")
	await compare_motion(Vector3(0, floor_y - 0.0005, z), Vector3(0.7, 0, 0.4), 20, "initial shallow recovery")
	await compare_motion(Vector3(bounds.end.x - 0.6, floor_y + 0.02, z), Vector3(1.7, 0, 0), 20, "step off the outer edge")
	await compare_motion(Vector3(bounds.position.x - 0.281, floor_y - 1, z), Vector3(0.7, 0, 1.2), 0, "slide along the outside wall")
	await compare_motion(Vector3(bounds.position.x - 0.281, floor_y - 1, bounds.position.y - 0.281), Vector3(1.2, 0, 1.2), 0, "outside wall corner")
	for radius in [0.16, 0.24, 0.3, 0.35]:
		await compare_motion(Vector3(-4, floor_y + 0.02, z), Vector3(1.1, 0, 0.6), 20, "registered creature radius %.2f" % radius, radius)
	var left_wall := obstacle(LEFT)
	var right_wall := obstacle(RIGHT)
	await settle()
	await compare_motion(Vector3(-1, floor_y + 0.02, z), Vector3(1.7, 0, 0.5), 20, "new dynamic obstacle blocks and slides")
	left_wall.free()
	right_wall.free()
	await settle()
	await compare_motion(Vector3(-1, floor_y + 0.02, z), Vector3(1.7, 0, 0.5), 20, "removing the obstacle restores the original trajectory")

func fallback_checks() -> void:
	# Dry paint changes preserve the body/RID and the compact geometry.
	var initial_body := terrain._generated.get_node("Body") as StaticBody3D
	var initial_rid := initial_body.get_rid()
	var painted := PackedInt32Array([terrain.data._index(terrain.data.origin)])
	terrain.data.set_paint_at_index(painted[0], 11)
	terrain.data.notify_surface_changed(painted)
	await settle()
	check(terrain._generated.get_node("Body").get_rid() == initial_rid and actual_faces() == reduced, "painting keeps the same compact collision body and precision")
	var saved_data := terrain.data
	var cases: Array[TerrainData] = []
	var raised := saved_data.duplicate(true) as TerrainData
	raised.set_level(raised.origin + Vector2i.ONE, 1)
	cases.append(raised)
	for overlay in [TerrainData.OVERLAY_WATER, TerrainData.OVERLAY_BRIDGE, TerrainData.OVERLAY_RAMP]:
		var marked := saved_data.duplicate(true) as TerrainData
		marked.set_overlay(marked.origin + Vector2i.ONE, overlay, true)
		cases.append(marked)
	for index in cases.size():
		terrain.data = cases[index]
		await settle()
		var full := original_faces(terrain)
		check(actual_faces().to_byte_array() == full.to_byte_array(), "height or water/bridge/ramp edit %d keeps every original collision triangle" % index)
		check(terrain._generated.get_node("Body").get_child_count() == (2 if index == 1 else 1), "edit %d preserves the expected separate water-blocker shapes" % index)
	terrain.data = saved_data
	await settle()
	check(actual_faces() == reduced, "replacing the data with a flat rectangle compacts its freshly rebuilt collision")
	var old_skirt := terrain.skirt_level
	terrain.skirt_level = 1
	var flat_only := terrain._compact_collision_faces(raw)
	check(flat_only.size() == 6, "a skirt above the floor introduces no side faces")
	terrain.skirt_level = old_skirt
	var small := saved_data.duplicate(true) as TerrainData
	small.resize(Vector2i(-3, 2), Vector2i(1, 1))
	terrain.data = small
	await settle()
	check(actual_faces().size() == 30 and actual_faces() == original_faces(terrain), "a single-cell translated rectangle keeps exact original corners and winding")

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	terrain = Terrain.new()
	terrain.data = load("res://data/world/world_terrain.tres").duplicate(true)
	world.add_child(terrain)
	await settle()
	raw = original_faces(terrain)
	reduced = actual_faces()
	bounds = terrain.data.get_world_rect()
	floor_y = terrain._corner_heights(terrain.data.origin)[0]
	bottom_y = terrain.skirt_level * terrain.data.layer_height
	structure_checks()
	(terrain._generated.get_node("Body") as StaticBody3D).collision_layer = 0
	reference = body(raw, LEFT)
	compact = body(reduced, RIGHT)
	await settle()
	ray_checks()
	await movement_checks()
	reference.free()
	compact.free()
	await fallback_checks()
	world.queue_free()
	await settle()
	print("Terrain collision compaction: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
