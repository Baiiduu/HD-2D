extends SceneTree
## Bake the approved rooftop additions into the standalone building scenes.
## Existing facades and ground-level collision are retained; no runtime builder.

var building: Node3D
var details: Node3D
var body: StaticBody3D
var material: Material
var regions: Dictionary
var stream: SurfaceTool
var group_name: String
var collision_number := 0

func _initialize() -> void:
	run.call_deferred()

func attach(node: Node, parent: Node) -> void:
	parent.add_child(node)
	node.owner = building

func begin_group(label: String) -> void:
	group_name = label
	stream = SurfaceTool.new()
	stream.begin(Mesh.PRIMITIVE_TRIANGLES)

func finish_group(surface: Material = null, offset := Vector3.ZERO) -> void:
	stream.index()
	stream.generate_tangents()
	var mesh := stream.commit()
	mesh.resource_name = group_name
	var node := MeshInstance3D.new()
	node.name = group_name
	node.position = offset
	node.mesh = mesh
	node.material_override = surface if surface else material
	attach(node, details)

func uv(key: String, value: Vector2) -> Vector2:
	var r: Array = regions[key].rect
	return (Vector2(r[0], r[1]) + Vector2.ONE * 0.5 + value * Vector2(float(r[2]) - 1.0, float(r[3]) - 1.0)) / 1024.0

func triangle(a: Vector3, b: Vector3, c: Vector3, ta: Vector2, tb: Vector2, tc: Vector2, normal: Vector3, key: String) -> void:
	var points := [a, b, c]
	var texcoords := [ta, tb, tc]
	var order := [0, 2, 1] if (b - a).cross(c - a).dot(normal) > 0.0 else [0, 1, 2]
	for i in order:
		stream.set_normal(normal)
		stream.set_uv(uv(key, texcoords[i]) if key != "foliage" else texcoords[i])
		stream.add_vertex(points[i])

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, key: String, start_v := 0.0, end_v := 1.0) -> void:
	triangle(a, b, c, Vector2(0, start_v), Vector2(1, start_v), Vector2(1, end_v), normal, key)
	triangle(a, c, d, Vector2(0, start_v), Vector2(1, end_v), Vector2(0, end_v), normal, key)

func box(center: Vector3, size: Vector3, key: String, top_key := "") -> void:
	var low := center - size * 0.5
	var high := center + size * 0.5
	quad(Vector3(low.x, low.y, high.z), Vector3(high.x, low.y, high.z), Vector3(high.x, high.y, high.z), Vector3(low.x, high.y, high.z), Vector3.BACK, key)
	quad(Vector3(high.x, low.y, low.z), Vector3(low.x, low.y, low.z), Vector3(low.x, high.y, low.z), Vector3(high.x, high.y, low.z), Vector3.FORWARD, key)
	quad(Vector3(high.x, low.y, high.z), Vector3(high.x, low.y, low.z), Vector3(high.x, high.y, low.z), Vector3(high.x, high.y, high.z), Vector3.RIGHT, key)
	quad(Vector3(low.x, low.y, low.z), Vector3(low.x, low.y, high.z), Vector3(low.x, high.y, high.z), Vector3(low.x, high.y, low.z), Vector3.LEFT, key)
	quad(Vector3(low.x, high.y, low.z), Vector3(high.x, high.y, low.z), Vector3(high.x, high.y, high.z), Vector3(low.x, high.y, high.z), Vector3.UP, top_key if top_key != "" else key)
	quad(Vector3(low.x, low.y, high.z), Vector3(high.x, low.y, high.z), Vector3(high.x, low.y, low.z), Vector3(low.x, low.y, low.z), Vector3.DOWN, key)

func collide_box(center: Vector3, size: Vector3, surface: StringName) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	add_collision(shape, center, surface)

func add_collision(shape: Shape3D, center: Vector3, surface: StringName) -> void:
	var collision := CollisionShape3D.new()
	collision.name = "RoofDetail%02d" % collision_number
	collision_number += 1
	collision.shape = shape
	collision.position = center
	collision.set_meta("collision_surface", surface)
	attach(collision, body)

func cylinder(center: Vector3, radius: float, height: float, side_key: String, top_key: String, surface: StringName) -> void:
	var low := center.y - height * 0.5
	var high := center.y + height * 0.5
	for i in 16:
		var a := TAU * float(i) / 16.0
		var b := TAU * float(i + 1) / 16.0
		var pa := Vector3(cos(a) * radius, 0, sin(a) * radius)
		var pb := Vector3(cos(b) * radius, 0, sin(b) * radius)
		var p := Vector3(center.x, high, center.z)
		triangle(p, p + pa, p + pb, Vector2.ONE * 0.5, Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5), Vector2(0.5 + cos(b) * 0.5, 0.5 + sin(b) * 0.5), Vector3.UP, top_key)
		p.y = low
		triangle(p, p + pb, p + pa, Vector2.ONE * 0.5, Vector2(0.5 + cos(b) * 0.5, 0.5 + sin(b) * 0.5), Vector2(0.5 + cos(a) * 0.5, 0.5 + sin(a) * 0.5), Vector3.DOWN, side_key)
		var normal := Vector3(cos((a + b) * 0.5), 0, sin((a + b) * 0.5))
		quad(p + pa, p + pb, Vector3(center.x, high, center.z) + pb, Vector3(center.x, high, center.z) + pa, normal, side_key)
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	add_collision(shape, center, surface)

func build_pergola() -> void:
	begin_group("BurgundyPergola")
	for x in [-0.58, 1.08]:
		for z in [-0.90, -0.20]:
			var p := Vector3(x, 3.16, z)
			var size := Vector3(0.055, 1.10, 0.055)
			box(p, size, "dark_metal")
			collide_box(p, size, &"metal")
	for z in [-0.94, -0.16]:
		var p := Vector3(0.25, 3.70, z)
		var size := Vector3(1.82, 0.055, 0.055)
		box(p, size, "dark_metal")
		collide_box(p, size, &"metal")
	for x in [-0.63, 1.13]:
		var p := Vector3(x, 3.70, -0.55)
		var size := Vector3(0.055, 0.055, 0.78)
		box(p, size, "dark_metal")
		collide_box(p, size, &"metal")
	for i in 7:
		var z0 := -0.94 + float(i) * 0.112
		var z1 := z0 + 0.094
		box(Vector3(0.25, 3.733, (z0 + z1) * 0.5), Vector3(1.76, 0.022, z1 - z0), "canvas")
		quad(Vector3(-0.63, 3.745, z0), Vector3(1.13, 3.745, z0), Vector3(1.13, 3.745, z1), Vector3(-0.63, 3.745, z1), Vector3.UP, "canvas", (z0 + 0.94) / 0.78, (z1 + 0.94) / 0.78)
		collide_box(Vector3(0.25, 3.733, (z0 + z1) * 0.5), Vector3(1.76, 0.022, z1 - z0), &"fabric")
	finish_group()

func build_table_set() -> void:
	begin_group("TerraceTableAndStools")
	var center := Vector3(0.25, 3.10, 0.30)
	cylinder(center, 0.23, 0.035, "wood_side", "wood_top", &"wood")
	cylinder(Vector3(center.x, 2.86, center.z), 0.025, 0.45, "dark_metal", "dark_metal", &"metal")
	for size in [Vector3(0.30, 0.024, 0.045), Vector3(0.045, 0.024, 0.30)]:
		var p := Vector3(center.x, 2.622, center.z)
		box(p, size, "dark_metal")
		collide_box(p, size, &"metal")
	for x in [-0.16, 0.66]:
		cylinder(Vector3(x, 2.90, 0.31), 0.115, 0.033, "wood_side", "wood_top", &"wood")
		for dx in [-0.062, 0.062]:
			for dz in [-0.062, 0.062]:
				var p := Vector3(x + dx, 2.749, 0.31 + dz)
				var size := Vector3(0.022, 0.278, 0.022)
				box(p, size, "dark_metal")
				collide_box(p, size, &"metal")
	finish_group()

func build_planter(center: Vector3, size: Vector3) -> void:
	var wall := 0.035
	for side in [-1.0, 1.0]:
		box(center + Vector3(side * (size.x - wall) * 0.5, 0, 0), Vector3(wall, size.y, size.z), "planter", "wood_side")
		box(center + Vector3(0, 0, side * (size.z - wall) * 0.5), Vector3(size.x - wall * 2.0, size.y, wall), "planter", "wood_side")
	box(center + Vector3(0, -size.y * 0.5 + 0.03, 0), Vector3(size.x - wall * 2.0, 0.06, size.z - wall * 2.0), "planter", "soil")
	quad(center + Vector3(-size.x * 0.5 + wall, size.y * 0.5 - 0.035, -size.z * 0.5 + wall), center + Vector3(size.x * 0.5 - wall, size.y * 0.5 - 0.035, -size.z * 0.5 + wall), center + Vector3(size.x * 0.5 - wall, size.y * 0.5 - 0.035, size.z * 0.5 - wall), center + Vector3(-size.x * 0.5 + wall, size.y * 0.5 - 0.035, size.z * 0.5 - wall), Vector3.UP, "soil")
	collide_box(center, size, &"wood")

func plant(center: Vector3, yaw: float) -> void:
	var side := Vector3(cos(yaw), 0, sin(yaw)) * 0.20
	var normal := Vector3(-sin(yaw), 0, cos(yaw))
	quad(center - side + Vector3.UP * 0.40, center + side + Vector3.UP * 0.40, center + side, center - side, normal, "foliage")

func build_planters() -> void:
	begin_group("WoodenHerbPlanters")
	build_planter(Vector3(-1.10, 2.75, -0.64), Vector3(0.42, 0.28, 0.55))
	build_planter(Vector3(1.18, 2.745, 0.30), Vector3(0.30, 0.27, 1.12))
	finish_group()
	begin_group("HerbFoliage")
	for p in [Vector3(-1.10, 2.815, -0.77), Vector3(-1.10, 2.815, -0.50), Vector3(1.18, 2.805, -0.08), Vector3(1.18, 2.805, 0.18), Vector3(1.18, 2.805, 0.44), Vector3(1.18, 2.805, 0.70)]:
		plant(p, 0.0)
		plant(p, PI * 0.5)
	finish_group(load("res://assets/models/city_cafe/cafe_roof_foliage.tres"))

func skylight_height(z: float) -> float:
	return lerpf(2.62, 2.29, (z + 0.54) / 1.08)

func skylight_point(x: float, z: float, offset := 0.0) -> Vector3:
	return Vector3(x, skylight_height(z) + offset, z)

func build_skylight() -> void:
	begin_group("GarageSkylight")
	var left := -1.57
	var right := 0.07
	var back := -0.54
	var front := 0.54
	var normal := Vector3(0, 1.08, 0.33).normalized()
	box(Vector3(-0.75, 2.112, 0), Vector3(1.74, 0.065, 1.18), "repair_metal")
	quad(Vector3(left, 2.14, back), Vector3(right, 2.14, back), skylight_point(right, back), skylight_point(left, back), Vector3.FORWARD, "repair_metal")
	quad(Vector3(right, 2.14, front), Vector3(left, 2.14, front), skylight_point(left, front), skylight_point(right, front), Vector3.BACK, "repair_metal")
	quad(Vector3(left, 2.14, front), Vector3(left, 2.14, back), skylight_point(left, back), skylight_point(left, front), Vector3.LEFT, "repair_metal")
	quad(Vector3(right, 2.14, back), Vector3(right, 2.14, front), skylight_point(right, front), skylight_point(right, back), Vector3.RIGHT, "repair_metal")
	for i in 3:
		var x0 := left + 0.05 + float(i) * 0.53
		var x1 := x0 + 0.48
		quad(skylight_point(x0, back + 0.04), skylight_point(x1, back + 0.04), skylight_point(x1, front - 0.04), skylight_point(x0, front - 0.04), normal, "glass")
	for i in 4:
		var x := left + 0.022 + float(i) * 0.53
		quad(skylight_point(x - 0.022, back, 0.008), skylight_point(x + 0.022, back, 0.008), skylight_point(x + 0.022, front, 0.008), skylight_point(x - 0.022, front, 0.008), normal, "repair_trim")
		if i > 0 and i < 3:
			quad(skylight_point(x + 0.012, back + 0.02, 0.010), skylight_point(x + 0.024, back + 0.02, 0.010), skylight_point(x + 0.024, front - 0.02, 0.010), skylight_point(x + 0.012, front - 0.02, 0.010), normal, "hazard", 0.04, 0.06)
	for z in [back, front]:
		quad(skylight_point(left, z - 0.022, 0.012), skylight_point(right, z - 0.022, 0.012), skylight_point(right, z + 0.022, 0.012), skylight_point(left, z + 0.022, 0.012), normal, "repair_trim")
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array([Vector3(left, 2.08, back), Vector3(right, 2.08, back), Vector3(left, 2.08, front), Vector3(right, 2.08, front), skylight_point(left, back), skylight_point(right, back), skylight_point(left, front), skylight_point(right, front)])
	# Keep the skylight readable from the saved game yaw beside the taller tower.
	var offset := Vector3(-0.12, 0, 0.34)
	add_collision(shape, offset, &"metal")
	finish_group(null, offset)

func build_service_walkway() -> void:
	begin_group("TowerServiceWalkway")
	box(Vector3(1.48, 3.505, 0), Vector3(0.24, 0.045, 1.62), "repair_trim", "walkway")
	collide_box(Vector3(1.48, 3.505, 0), Vector3(0.24, 0.045, 1.62), &"metal")
	box(Vector3(1.69, 3.515, 0), Vector3(0.10, 0.065, 1.70), "repair_trim", "cable")
	collide_box(Vector3(1.69, 3.515, 0), Vector3(0.10, 0.065, 1.70), &"metal")
	box(Vector3(0.84, 3.501, 0.22), Vector3(0.50, 0.028, 0.50), "repair_trim", "hatch")
	collide_box(Vector3(0.84, 3.501, 0.22), Vector3(0.50, 0.028, 0.50), &"metal")
	for z in [-0.64, 0.0, 0.64]:
		box(Vector3(1.69, 3.555, z), Vector3(0.13, 0.018, 0.045), "repair_trim")
	quad(Vector3(1.30, 3.484, -0.83), Vector3(1.35, 3.484, -0.83), Vector3(1.35, 3.484, 0.83), Vector3(1.30, 3.484, 0.83), Vector3.UP, "hazard")
	finish_group()

func sync_shared_undersides(layout: Dictionary) -> void:
	for path in ["Model/Roofs/GarageRoof/Deck", "Model/Roofs/TowerRoof/Deck"]:
		var node: MeshInstance3D = building.get_node(path)
		var arrays: Array = node.mesh.surface_get_arrays(0)
		var coords: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for face: Dictionary in layout.faces:
			if face.node != path or face.face != "y-": continue
			var r: Array = face.packed
			for corner: Dictionary in face.vertices:
				var u := (float(corner.u) - float(face.min[0])) / (float(face.max[0]) - float(face.min[0]))
				var v := (float(corner.v) - float(face.min[1])) / (float(face.max[1]) - float(face.min[1]))
				coords[int(corner.index)] = (Vector2(r[0], r[1]) + Vector2.ONE * 0.5 + Vector2(u, v) * Vector2(float(r[2]) - 1.0, float(r[3]) - 1.0)) / 1024.0
		arrays[Mesh.ARRAY_TEX_UV] = coords
		var mesh := ArrayMesh.new()
		mesh.resource_name = node.mesh.resource_name
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		node.mesh = mesh

func run() -> void:
	for name: String in ["city_cafe", "city_repair_shop"]:
		var path := "res://scenes/buildings/" + name + ".tscn"
		var uid := ResourceLoader.get_resource_uid(path)
		building = load(path).instantiate()
		root.add_child(building)
		body = building.get_node("BuildingCollision")
		if building.has_node("Model/RooftopDetails"):
			building.get_node("Model/RooftopDetails").free()
		for child in body.get_children():
			if str(child.name).begins_with("RoofDetail"): child.free()
		details = Node3D.new()
		details.name = "RooftopDetails"
		attach(details, building.get_node("Model"))
		collision_number = 0
		var folder := "res://assets/models/" + name + "/"
		var layout_file := "cafe_uv_layout.json" if name == "city_cafe" else "repair_shop_uv_layout.json"
		var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder + layout_file))
		regions = layout.roof_regions
		material = load(folder + ("cafe_material.tres" if name == "city_cafe" else "repair_shop_material.tres"))
		if name == "city_cafe":
			build_pergola()
			build_table_set()
			build_planters()
			building.set_meta("roof_design", "Approved burgundy pergola, cafe table, two stools and herb planters; no rooftop HVAC")
		else:
			sync_shared_undersides(layout)
			build_skylight()
			build_service_walkway()
			building.set_meta("roof_design", "Approved low garage skylight and tower inspection walkway; no rooftop HVAC")
		building.set_meta("roof_design_reference", "docs/references/city-buildings/cafe-repair-rooftops-approved.png")
		var packed := PackedScene.new()
		assert(packed.pack(building) == OK)
		assert(ResourceSaver.save(packed, path) == OK)
		if uid > 0: ResourceSaver.set_uid(path, uid)
		print("ROOF_BAKED: %s; %d static groups, %d added collision parts; original ground-level structure retained." % [name, details.get_child_count(), collision_number])
		building.free()
	quit()
