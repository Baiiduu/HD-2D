extends SceneTree
## Rebuild the approved clean cyberpunk monument. All dimensions are local meters;
## World keeps its existing 0.5 instance scale and original position.

const ASSETS := "res://assets/models/cyber_armillary/"
const OUTPUT := "res://scenes/buildings/cyber_armillary_monument.tscn"
const CENTER := Vector3(0, 3.18, 0)
const GLOBE_RADIUS := 1.7
const BASE_RADIUS := 3.05
const SEGMENTS := 64

var building: Node3D
var model: Node3D
var collision: StaticBody3D
var material: ShaderMaterial
var streams: Dictionary = {}
var regions: Dictionary = {}
var meshes: Dictionary = {}

func _initialize() -> void:
	var file := FileAccess.open(ASSETS + "uv_layout.json", FileAccess.READ)
	regions = JSON.parse_string(file.get_as_text()).regions
	# Export only the new deck when preserving an editor-saved monument scene.
	if "--deck-only" in OS.get_cmdline_user_args():
		build_deck()
		var deck := (streams["DeckDetails"] as SurfaceTool).commit()
		deck.resource_name = "DeckDetails"
		var saved := ResourceSaver.save(deck, ASSETS + "deck_details.res", ResourceSaver.FLAG_COMPRESS)
		print("Deck details: ", deck.surface_get_array_len(0) / 3, " triangles; ", error_string(saved))
		# Preserve the edited base geometry, changing only the old top's UVs.
		if saved == OK:
			var existing := (load(OUTPUT) as PackedScene).instantiate()
			var base := (existing.get_node("Model/Base") as MeshInstance3D).mesh
			var arrays := base.surface_get_arrays(0)
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var coords: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			for i in points.size():
				if is_equal_approx(points[i].y, 0.48) and normals[i].y > 0.99:
					coords[i] = uv("dark", Vector2.ONE * 0.5)
			arrays[Mesh.ARRAY_TEX_UV] = coords
			var updated := ArrayMesh.new()
			updated.resource_name = "Base"
			updated.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			saved = ResourceSaver.save(updated, ASSETS + "base.res", ResourceSaver.FLAG_COMPRESS)
			existing.free()
		quit(0 if saved == OK else 1)
		return
	material = ShaderMaterial.new()
	material.resource_name = "CyberArmillaryShared"
	material.shader = load("res://shaders/environment/cyber_armillary.gdshader")
	material.set_shader_parameter("albedo_atlas", load(ASSETS + "albedo.png"))
	material.set_shader_parameter("orm_atlas", load(ASSETS + "orm.png"))
	material.set_shader_parameter("emission_energy", 1.7)
	if ResourceSaver.save(material, ASSETS + "material.tres") != OK:
		quit(1)
		return
	building = Node3D.new()
	building.name = "CyberArmillaryMonument"
	building.add_to_group(&"ricochet_obstacles", true)
	building.set_meta("production_stage", "textured")
	building.set_meta("orbit_count", 2)
	building.set_meta("local_base_radius", BASE_RADIUS)
	building.set_meta("world_instance_scale", 0.5)
	building.set_meta("source_builder", "res://tools/build_cyber_armillary.gd")
	model = Node3D.new()
	model.name = "Model"
	attach(model, building)
	collision = StaticBody3D.new()
	collision.name = "MonumentCollision"
	collision.collision_layer = 1
	collision.collision_mask = 0
	collision.set_meta("collision_surface", &"metal")
	collision.add_to_group(&"ricochet_surfaces", true)
	attach(collision, building)
	build_base()
	build_pedestal()
	build_deck()
	build_globe()
	build_orbit("OrbitA", 2.0, Vector3(0, 15, -20) * PI / 180.0)
	build_orbit("OrbitB", 2.21, Vector3(65, 30, 10) * PI / 180.0)
	build_panel()
	var triangles := 0
	for label: String in streams:
		var mesh: ArrayMesh = (streams[label] as SurfaceTool).commit()
		mesh.resource_name = label
		if label != "DeckDetails": mesh.surface_set_material(0, material)
		var path := ASSETS + label.to_snake_case() + ".res"
		if ResourceSaver.save(mesh, path, ResourceSaver.FLAG_COMPRESS) != OK:
			quit(1)
			return
		meshes[label] = mesh
		var instance := MeshInstance3D.new()
		instance.name = label
		instance.mesh = mesh
		if label == "DeckDetails": instance.material_override = material
		if label == "Globe": instance.material_override = load(ASSETS + "globe_material.tres")
		if label == "Inlays": instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		attach(instance, model)
		triangles += mesh.surface_get_array_len(0) / 3
	for label: String in ["OrbitA", "OrbitB"]:
		add_collision(label, meshes[label].create_trimesh_shape(), Vector3.ZERO, &"metal")
	var motion := AnimationPlayer.new()
	motion.name = "AuroraMotion"
	motion.set_script(load("res://scripts/buildings/aurora_globe_motion.gd"))
	motion.add_animation_library(&"", load(ASSETS + "globe_motion.tres"))
	motion.autoplay = "aurora"
	attach(motion, building)
	building.set_meta("triangles", triangles)
	var packed := PackedScene.new()
	var result := packed.pack(building)
	if result == OK: result = ResourceSaver.save(packed, OUTPUT)
	print("Cyber armillary: ", OUTPUT, "; ", triangles, " triangles; ", streams.size(), " meshes; ", error_string(result))
	building.free()
	quit(0 if result == OK else 1)

func attach(node: Node, parent: Node) -> void:
	parent.add_child(node)
	node.owner = building

func stream(label: String) -> SurfaceTool:
	if not streams.has(label):
		var value := SurfaceTool.new()
		value.begin(Mesh.PRIMITIVE_TRIANGLES)
		streams[label] = value
	return streams[label]

func uv(key: String, point: Vector2) -> Vector2:
	var rect: Array = regions[key]
	var margin := 2.0
	return (Vector2(rect[0], rect[1]) + Vector2.ONE * margin + point * (Vector2(rect[2], rect[3]) - Vector2.ONE * margin * 2.0)) / 512.0

func triangle(label: String, key: String, vertices: Array[Vector3], normals: Array[Vector3], coords: Array[Vector2], tint := Color.WHITE) -> void:
	var order := [0, 1, 2]
	# Godot front faces use clockwise winding.
	if (vertices[1] - vertices[0]).cross(vertices[2] - vertices[0]).dot(normals[0] + normals[1] + normals[2]) > 0.0:
		order = [0, 2, 1]
	var target := stream(label)
	for index: int in order:
		target.set_color(tint)
		target.set_normal(normals[index])
		target.set_uv(uv(key, coords[index]))
		target.add_vertex(vertices[index])

func quad(label: String, key: String, points: Array[Vector3], normal: Vector3, coords: Array[Vector2] = [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN], tint := Color.WHITE) -> void:
	for indices: Array in [[0, 1, 2], [0, 2, 3]]:
		triangle(label, key, [points[indices[0]], points[indices[1]], points[indices[2]]], [normal, normal, normal], [coords[indices[0]], coords[indices[1]], coords[indices[2]]], tint)

func add_collision(label: String, shape: Shape3D, center: Vector3, surface: StringName, basis := Basis.IDENTITY) -> void:
	var part := CollisionShape3D.new()
	part.name = label
	part.shape = shape
	part.transform = Transform3D(basis, center)
	part.set_meta("collision_surface", surface)
	attach(part, collision)

func prism_shape(bottom: float, top: float, y0: float, y1: float, count: int) -> ConvexPolygonShape3D:
	var points := PackedVector3Array()
	for i in count:
		var angle := TAU * i / count + PI / count
		points.append(Vector3(sin(angle) * bottom, y0, cos(angle) * bottom))
		points.append(Vector3(sin(angle) * top, y1, cos(angle) * top))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape

func frustum(label: String, bottom: float, top: float, y0: float, y1: float, count: int, side_key: String, top_key: String) -> void:
	for i in count:
		var a := TAU * i / count + PI / count
		var b := TAU * (i + 1) / count + PI / count
		var da := Vector3(sin(a), 0, cos(a))
		var db := Vector3(sin(b), 0, cos(b))
		var normal := ((da + db) * 0.5 + Vector3.UP * (bottom - top) / (y1 - y0)).normalized()
		quad(label, side_key, [da * bottom + Vector3.UP * y0, db * bottom + Vector3.UP * y0, db * top + Vector3.UP * y1, da * top + Vector3.UP * y1], normal)
		var va := da * top + Vector3.UP * y1
		var vb := db * top + Vector3.UP * y1
		var denom := BASE_RADIUS * 2.0 if top_key == "base_top" else top * 2.0
		triangle(label, top_key, [Vector3.UP * y1, va, vb], [Vector3.UP, Vector3.UP, Vector3.UP], [Vector2.ONE * 0.5, Vector2(va.x, va.z) / denom + Vector2.ONE * 0.5, Vector2(vb.x, vb.z) / denom + Vector2.ONE * 0.5])
		triangle(label, side_key, [Vector3.UP * y0, da * bottom + Vector3.UP * y0, db * bottom + Vector3.UP * y0], [Vector3.DOWN, Vector3.DOWN, Vector3.DOWN], [Vector2.ONE * 0.5, Vector2.ZERO, Vector2.ONE])

func build_base() -> void:
	frustum("Base", 3.0, 3.0, 0.0, 0.08, 8, "dark", "dark")
	frustum("Base", 3.0, 3.0, 0.08, 0.4, 8, "base_side", "dark")
	frustum("Base", 3.05, 3.05, 0.4, 0.48, 8, "stone_edge", "dark")
	add_collision("MetalBase", prism_shape(3.0, 3.0, 0.0, 0.4, 8), Vector3.ZERO, &"metal")
	add_collision("StoneCap", prism_shape(3.05, 3.05, 0.4, 0.48, 8), Vector3.ZERO, &"metal")

func build_pedestal() -> void:
	frustum("Pedestal", 1.06, 1.06, 0.48, 0.62, 8, "dark", "silver")
	frustum("Pedestal", 0.58, 0.34, 0.62, 1.38, 12, "pedestal", "silver")
	frustum("Pedestal", 0.44, 0.44, 1.38, 1.5, 16, "silver", "dark")
	add_collision("PedestalFoot", prism_shape(1.06, 1.06, 0.48, 0.62, 8), Vector3.ZERO, &"metal")
	add_collision("PedestalStem", prism_shape(0.58, 0.34, 0.62, 1.38, 12), Vector3.ZERO, &"metal")
	add_collision("PedestalCollar", prism_shape(0.44, 0.44, 1.38, 1.5, 16), Vector3.ZERO, &"metal")
	# A shallow opaque inlay, not a light, billboard halo or transparent layer.
	flat_ring("Inlays", "cyan", Vector3(0, 0.625, 0), Basis(Vector3.RIGHT, PI * 0.5), 0.6, 0.035, 0.0, TAU, 64)

func build_deck() -> void:
	# Eight broad inset plates follow the approved top-surface reference.
	flat_ring("DeckDetails", "silver", Vector3(0, 0.486, 0), Basis(Vector3.RIGHT, PI * 0.5), 3.005, 0.09, PI / 8.0, TAU + PI / 8.0, 8)
	for sector in 8:
		var a := PI / 8.0 + TAU * sector / 8.0
		var b := a + TAU / 8.0
		var da := Vector2(cos(a), sin(a))
		var db := Vector2(cos(b), sin(b))
		var outline: Array[Vector2] = [da * 1.095, da * 2.94, db * 2.94, db * 1.095]
		var bottom := clipped_corners(inset_polygon(outline, 0.02))
		var upper := clipped_corners(inset_polygon(outline, 0.05))
		var frame := clipped_corners(inset_polygon(outline, 0.14))
		var face := clipped_corners(inset_polygon(outline, 0.16))
		deck_band(bottom, upper, 0.483, 0.52, "stone_edge")
		deck_band(upper, frame, 0.52, 0.52, "silver")
		deck_band(frame, face, 0.52, 0.507, "dark")
		var center := Vector2.ZERO
		for point: Vector2 in face: center += point / face.size()
		var tint := Color(0.68, 0.70, 0.72) * (1.0 if sector % 2 == 0 else 1.035)
		tint.a = 1.0
		for i in face.size():
			var p := face[i]
			var q := face[(i + 1) % face.size()]
			triangle("DeckDetails", "deck_face", [Vector3(center.x, 0.507, center.y), Vector3(p.x, 0.507, p.y), Vector3(q.x, 0.507, q.y)], [Vector3.UP, Vector3.UP, Vector3.UP], [Vector2.ONE * 0.5, Vector2.ONE * 0.5, Vector2.ONE * 0.5], tint)
		# Two small, flush fasteners per plate, aligned to its outer edge.
		var fastener_line := inset_polygon(outline, 0.095)
		var radial := (da + db).normalized()
		var tangent := Vector2(-radial.y, radial.x)
		for fraction: float in [0.09, 0.91]:
			var position := fastener_line[1].lerp(fastener_line[2], fraction)
			var points: Array[Vector3] = []
			for coord: Vector2 in [Vector2(-1,-1), Vector2(1,-1), Vector2(1,1), Vector2(-1,1)]:
				var p := position + tangent * coord.x * 0.055 + radial * coord.y * 0.0175
				points.append(Vector3(p.x, 0.522, p.y))
			quad("DeckDetails", "dark", points, Vector3.UP)

func inset_polygon(points: Array[Vector2], distance: float) -> Array[Vector2]:
	# Input polygons are convex and counterclockwise; preserve matching vertices.
	var result: Array[Vector2] = []
	for i in points.size():
		var before := (points[i] - points[posmod(i - 1, points.size())]).normalized()
		var after := (points[(i + 1) % points.size()] - points[i]).normalized()
		var inward := Vector2(-before.y, before.x)
		var bisector := (inward + Vector2(-after.y, after.x)).normalized()
		result.append(points[i] + bisector * distance / bisector.dot(inward))
	return result

func clipped_corners(points: Array[Vector2]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for i in points.size():
		result.append(points[i].move_toward(points[posmod(i - 1, points.size())], 0.065))
		result.append(points[i].move_toward(points[(i + 1) % points.size()], 0.065))
	return result

func deck_band(outer: Array[Vector2], inner: Array[Vector2], y0: float, y1: float, key: String) -> void:
	for i in outer.size():
		var next := (i + 1) % outer.size()
		var a := Vector3(outer[i].x, y0, outer[i].y)
		var b := Vector3(outer[next].x, y0, outer[next].y)
		var c := Vector3(inner[next].x, y1, inner[next].y)
		var d := Vector3(inner[i].x, y1, inner[i].y)
		quad("DeckDetails", key, [a, b, c, d], (d - a).cross(b - a).normalized())

func sphere_point(latitude: float, longitude: float) -> Vector3:
	return Vector3(sin(latitude) * sin(longitude), cos(latitude), sin(latitude) * cos(longitude))

func build_globe() -> void:
	for row in 24:
		for column in 48:
			var coords: Array[Vector2] = [Vector2(column / 48.0, row / 24.0), Vector2((column + 1) / 48.0, row / 24.0), Vector2((column + 1) / 48.0, (row + 1) / 24.0), Vector2(column / 48.0, (row + 1) / 24.0)]
			var points: Array[Vector3] = []
			var normals: Array[Vector3] = []
			for coord: Vector2 in coords:
				var normal := sphere_point(coord.y * PI, coord.x * TAU)
				normals.append(normal)
				points.append(CENTER + normal * GLOBE_RADIUS)
			for ids: Array in [[0, 1, 2], [0, 2, 3]]:
				if (points[ids[0]] - points[ids[1]]).cross(points[ids[2]] - points[ids[1]]).length_squared() < 0.000000001: continue
				triangle("Globe", "globe", [points[ids[0]], points[ids[1]], points[ids[2]]], [normals[ids[0]], normals[ids[1]], normals[ids[2]]], [coords[ids[0]], coords[ids[1]], coords[ids[2]]])
	var shape := SphereShape3D.new()
	shape.radius = GLOBE_RADIUS
	add_collision("Globe", shape, CENTER, &"metal")
	for longitude: float in [-35.0, 145.0]:
		meridian("Details", "dark", deg_to_rad(longitude), 0.055, GLOBE_RADIUS + 0.002)
		meridian("Inlays", "cyan", deg_to_rad(longitude), 0.023, GLOBE_RADIUS + 0.004)

func meridian(label: String, key: String, longitude: float, width: float, radius: float) -> void:
	for i in 48:
		var a := PI * i / 48.0
		var b := PI * (i + 1) / 48.0
		var points: Array[Vector3] = []
		for coord: Vector2 in [Vector2(a, -1), Vector2(a, 1), Vector2(b, 1), Vector2(b, -1)]:
			points.append(CENTER + sphere_point(coord.x, longitude + coord.y * width) * radius)
		quad(label, key, points, sphere_point((a + b) * 0.5, longitude))

func ring_point(radius: float, angle: float, depth: float) -> Vector3:
	return Vector3(cos(angle) * radius, sin(angle) * radius, depth)

func flat_ring(label: String, key: String, center: Vector3, basis: Basis, radius: float, width: float, start: float, end: float, count: int, depth := 0.0, back := false) -> void:
	for i in count:
		var a := lerpf(start, end, i / float(count))
		var b := lerpf(start, end, (i + 1) / float(count))
		var points: Array[Vector3] = []
		for item: Vector2 in [Vector2(a, -1), Vector2(b, -1), Vector2(b, 1), Vector2(a, 1)]:
			points.append(center + basis * ring_point(radius + item.y * width * 0.5, item.x, depth))
		quad(label, key, points, basis * (Vector3.BACK if back else Vector3.FORWARD))

func build_orbit(label: String, radius: float, rotation: Vector3) -> void:
	var basis := Basis.from_euler(rotation)
	var width := 0.22
	var depth := 0.12
	for i in SEGMENTS:
		var a := TAU * i / SEGMENTS
		var b := TAU * (i + 1) / SEGMENTS
		for front: float in [-1.0, 1.0]:
			var points: Array[Vector3] = []
			for item: Vector2 in [Vector2(a, -1), Vector2(b, -1), Vector2(b, 1), Vector2(a, 1)]:
				points.append(CENTER + basis * ring_point(radius + item.y * width * 0.5, item.x, front * depth * 0.5))
			quad(label, "rail", points, basis * Vector3(0, 0, front))
		for outer: float in [-1.0, 1.0]:
			var points: Array[Vector3] = []
			for item: Vector2 in [Vector2(a, -1), Vector2(b, -1), Vector2(b, 1), Vector2(a, 1)]:
				points.append(CENTER + basis * ring_point(radius + outer * width * 0.5, item.x, item.y * depth * 0.5))
			quad(label, "dark", points, basis * Vector3(cos((a+b)*0.5), sin((a+b)*0.5), 0) * outer)
	for phase: float in [0.3, 2.35, 4.4]:
		for side: float in [-1.0, 1.0]:
			flat_ring("Inlays", "cyan", CENTER, basis, radius - 0.018, 0.026, phase, phase + 0.52, 12, side * (depth * 0.5 + 0.003), side > 0)
	for index in 2:
		var angle := PI * index + (0.45 if label == "OrbitA" else 1.5)
		var center := CENTER + basis * ring_point(radius, angle, 0)
		var local := basis * Basis(Vector3.BACK, angle)
		var size := Vector3(0.3, 0.24, 0.18)
		box("Details", "silver", center, size, local)
		var shape := BoxShape3D.new()
		shape.size = size
		add_collision(label + "Joint" + str(index), shape, center, &"metal", local)
		for side: float in [-1.0, 1.0]:
			box("Inlays", "amber", center + local * Vector3(0, 0, side * 0.094), Vector3(0.075, 0.12, 0.008), local)

func box(label: String, key: String, center: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	for axis in 3:
		for sign_value: float in [-1.0, 1.0]:
			var normal := Vector3.ZERO
			normal[axis] = sign_value
			var points: Array[Vector3] = []
			for coord: Vector2 in [Vector2(-1,-1), Vector2(1,-1), Vector2(1,1), Vector2(-1,1)]:
				var p := normal * 0.5
				p[(axis + 1) % 3] = coord.x * 0.5
				p[(axis + 2) % 3] = coord.y * 0.5
				points.append(center + basis * (p * size))
			quad(label, key, points, basis * normal)

func build_panel() -> void:
	var front := 3.0 * cos(PI / 8.0)
	# A flush panel stays within the existing base footprint; only its front is drawn.
	var z := front + 0.006
	quad("Details", "dark", [Vector3(-0.68,0.085,z), Vector3(0.68,0.085,z), Vector3(0.68,0.395,z), Vector3(-0.68,0.395,z)], Vector3.BACK)
	quad("Details", "panel", [Vector3(-0.5,0.135,z+0.003), Vector3(0.35,0.135,z+0.003), Vector3(0.35,0.345,z+0.003), Vector3(-0.5,0.345,z+0.003)], Vector3.BACK)
	for y in [0.18, 0.31]:
		quad("Inlays", "amber", [Vector3(0.46,y-0.035,z+0.005),Vector3(0.53,y-0.035,z+0.005),Vector3(0.53,y+0.035,z+0.005),Vector3(0.46,y+0.035,z+0.005)], Vector3.BACK)
