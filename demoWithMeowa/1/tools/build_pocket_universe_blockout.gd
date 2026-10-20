extends SceneTree
## 模型源：生成静态白模与碰撞；已有图集时同步重建 UV，不在正式地图放置。
## +Z 正面 / -Z 背面 / +X 设备侧；全部尺寸直接使用最终世界米。

const OUTPUT := "res://scenes/buildings/pocket_universe_nursery.tscn"
const CYBER_ORBIT := "res://assets/models/cyber_armillary/"
var building: Node3D
var model: Node3D
var body: StaticBody3D
var shell: StandardMaterial3D
var glass: StandardMaterial3D
var trim: StandardMaterial3D
var instrument: StandardMaterial3D
var specimen: StandardMaterial3D

func _initialize() -> void:
	shell = material("BlockoutShell", Color(0.79, 0.8, 0.81))
	glass = material("BlockoutGlazing", Color(0.25, 0.29, 0.32))
	trim = material("BlockoutTrim", Color(0.51, 0.54, 0.56))
	instrument = material("BlockoutEquipment", Color(0.39, 0.41, 0.43))
	specimen = material("BlockoutSpecimen", Color(0.65, 0.71, 0.74))
	building = Node3D.new()
	building.name = "PocketUniverseNursery"
	building.add_to_group("occlusion_buildings", true)
	building.set_meta("production_stage", "whitebox")
	building.set_meta("footprint_m", Vector2(3.6, 3.2))
	building.set_meta("height_m", 3.8)
	model = Node3D.new()
	model.name = "Model"
	attach(model, building)
	body = StaticBody3D.new()
	body.name = "BuildingCollision"
	body.set_meta("collision_surface", &"metal")
	attach(body, building)
	build_ground_floor()
	build_observation_ring()
	build_upper_pod()
	build_instruments()
	build_cosmos()
	var entry := Marker3D.new()
	entry.name = "MainEntrance"
	entry.position = Vector3(0, 0, 1.27)
	entry.set_meta("clear_opening", Vector2(0.8, 1.3))
	attach(entry, building)
	var rear := Marker3D.new()
	rear.name = "ServiceEntrance"
	rear.position = Vector3(-0.52, 0, -1.49)
	attach(rear, building)
	var assets := "res://assets/models/pocket_universe_nursery/"
	if FileAccess.file_exists(assets + "pocket_universe_uv_layout.json"):
		var whitebox := PackedScene.new()
		assert(whitebox.pack(building) == OK)
		assert(ResourceSaver.save(whitebox, assets + "source/whitebox.tscn") == OK)
	if ResourceLoader.exists(assets + "pocket_universe_material.tres") and ResourceLoader.exists(assets + "textures/pocket_universe_albedo.png"):
		var baker := load("res://tools/apply_pocket_universe_uv.gd")
		baker.bake_scene(building)
	var packed := PackedScene.new()
	var result := packed.pack(building)
	if result == OK: result = ResourceSaver.save(packed, OUTPUT)
	print("Pocket universe whitebox: ", OUTPUT, " / ", error_string(result))
	building.free()
	quit(0 if result == OK else 1)

func material(label: String, color: Color) -> StandardMaterial3D:
	var value := StandardMaterial3D.new()
	value.resource_name = label
	value.albedo_color = color
	value.roughness = 0.85
	return value

func attach(node: Node, parent: Node) -> void:
	parent.add_child(node)
	node.owner = building

func mesh_part(label: String, mesh: Mesh, center: Vector3, surface: Material, solid := false) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.position = center
	part.material_override = surface
	attach(part, model)
	if solid:
		var collision := CollisionShape3D.new()
		collision.name = label
		collision.position = center
		if mesh is BoxMesh:
			var shape := BoxShape3D.new()
			shape.size = mesh.size
			collision.shape = shape
		else:
			collision.shape = mesh.create_trimesh_shape()
		collision.set_meta("collision_surface", &"metal")
		attach(collision, body)
	return part

func box(label: String, size: Vector3, center: Vector3, surface: Material, solid := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh_part(label, mesh, center, surface, solid)

func cylinder(label: String, radius: float, height: float, center: Vector3, surface: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	return mesh_part(label, mesh, center, surface)

func sphere(label: String, radius: float, center: Vector3) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 32
	mesh.rings = 16
	mesh_part(label, mesh, center, specimen)

func triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	# Godot 正面顺时针；显式法线避免弧形内壁和顶盖受光翻转。
	var points := [a, c, b] if (b - a).cross(c - a).dot(normal) > 0.0 else [a, b, c]
	for vertex: Vector3 in points:
		st.set_normal(normal)
		st.set_uv(Vector2(vertex.x, vertex.y))
		st.add_vertex(vertex)

func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	triangle(st, a, b, c, normal)
	triangle(st, a, c, d, normal)

func extrusion(label: String, outline: PackedVector2Array, low: float, high: float, surface: Material, cap_top := true) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var triangles := Geometry2D.triangulate_polygon(outline)
	for i in range(0, triangles.size(), 3):
		var p: Vector2 = outline[triangles[i]]
		var q: Vector2 = outline[triangles[i + 1]]
		var r: Vector2 = outline[triangles[i + 2]]
		if cap_top: triangle(st, Vector3(p.x, high, p.y), Vector3(q.x, high, q.y), Vector3(r.x, high, r.y), Vector3.UP)
		triangle(st, Vector3(p.x, low, p.y), Vector3(q.x, low, q.y), Vector3(r.x, low, r.y), Vector3.DOWN)
	for i in outline.size():
		var p := outline[i]
		var q := outline[(i + 1) % outline.size()]
		var normal := Vector3(-(q.y - p.y), 0, q.x - p.x).normalized()
		quad(st, Vector3(p.x, low, p.y), Vector3(q.x, low, q.y), Vector3(q.x, high, q.y), Vector3(p.x, high, p.y), normal)
	mesh_part(label, st.commit(), Vector3.ZERO, surface)
	# 凸分解保留实体轮廓和凹门洞；被其它部件封住的顶面不重复绘制。
	var polygons := Geometry2D.decompose_polygon_in_convex(outline)
	assert(not polygons.is_empty(), "Lower floor collision decomposition failed")
	for i in polygons.size():
		var points := PackedVector3Array()
		for point: Vector2 in polygons[i]:
			points.append(Vector3(point.x, low, point.y))
			points.append(Vector3(point.x, high, point.y))
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		var collision := CollisionShape3D.new()
		collision.name = label + "Part%d" % i
		collision.shape = shape
		collision.set_meta("collision_surface", &"metal")
		attach(collision, body)

func arc(label: String, radius: Vector2, inner: float, low: float, high: float, start: float, end: float, surface: Material, solid := false, bevel := false) -> void:
	var profile := [Vector2(inner, low), Vector2(1, low), Vector2(1, high), Vector2(inner, high)]
	if bevel:
		profile = [Vector2(inner, low), Vector2(0.98, low), Vector2(1, low + 0.08), Vector2(0.94, high), Vector2(inner, high)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := maxi(4, ceili((end - start) / 8.0))
	for i in count:
		var a := deg_to_rad(lerpf(start, end, float(i) / count))
		var b := deg_to_rad(lerpf(start, end, float(i + 1) / count))
		for edge in profile.size():
			var p: Vector2 = profile[edge]
			var q: Vector2 = profile[(edge + 1) % profile.size()]
			var pa := arc_point(radius, p, a)
			var pb := arc_point(radius, p, b)
			var qb := arc_point(radius, q, b)
			var qa := arc_point(radius, q, a)
			var radial := Vector3(sin((a + b) * 0.5), 0, cos((a + b) * 0.5))
			var normal := (radial * (q.y - p.y) + Vector3.UP * (p.x - q.x)).normalized()
			quad(st, pa, pb, qb, qa, normal)
	for angle in [deg_to_rad(start), deg_to_rad(end)]:
		var normal := Vector3(-cos(angle), 0, sin(angle)) * (1.0 if is_equal_approx(angle, deg_to_rad(start)) else -1.0)
		for i in range(1, profile.size() - 1):
			triangle(st, arc_point(radius, profile[0], angle), arc_point(radius, profile[i], angle), arc_point(radius, profile[i + 1], angle), normal)
	mesh_part(label, st.commit(), Vector3.ZERO, surface, solid)

func arc_point(radius: Vector2, profile: Vector2, angle: float) -> Vector3:
	return Vector3(radius.x * profile.x * sin(angle), profile.y, radius.y * profile.x * cos(angle))

func build_ground_floor() -> void:
	var outline := PackedVector2Array()
	var start := asin(0.4 / 1.76)
	for i in 49:
		var angle := lerpf(start, TAU - start, float(i) / 48)
		outline.append(Vector2(1.76 * sin(angle), 1.56 * cos(angle)))
	outline.append(Vector2(-0.4, 1.27))
	outline.append(Vector2(0.4, 1.27))
	extrusion("LowerLaboratory", outline, 0.0, 1.45, shell)
	box("DoorGlass", Vector3(0.79, 1.29, 0.025), Vector3(0, 0.645, 1.287), glass)
	box("DoorMullion", Vector3(0.025, 1.29, 0.035), Vector3(0, 0.645, 1.308), trim)
	box("EntryLintel", Vector3(0.8, 0.15, 0.29), Vector3(0, 1.375, 1.415), shell, true)
	box("EntryCanopy", Vector3(1.05, 0.08, 0.27), Vector3(0, 1.44, 1.465), trim, true)
	box("EntryLightPlaceholder", Vector3(0.72, 0.035, 0.018), Vector3(0, 1.416, 1.604 - 0.018), specimen)
	box("EntryTerminal", Vector3(0.1, 0.17, 0.025), Vector3(0.54, 0.88, 1.49), instrument)
	arc("WestGroundGlazing", Vector2(1.77, 1.57), 0.99, 0.32, 1.19, 224, 320, glass)
	arc("EastGroundGlazing", Vector2(1.77, 1.57), 0.99, 0.32, 1.19, 39, 66, glass)
	arc("EastRearGlazing", Vector2(1.77, 1.57), 0.99, 0.66, 1.17, 127, 150, glass)
	box("ServiceDoor", Vector3(0.59, 1.18, 0.025), Vector3(-0.48, 0.59, -1.49), glass)
	box("RearVentPlaceholder", Vector3(0.5, 0.44, 0.04), Vector3(0.38, 0.81, -1.52), instrument)
	box("EastServicePanel", Vector3(0.045, 0.65, 0.49), Vector3(1.75, 0.63, -0.02), instrument)
	box("RearPlantCabinet", Vector3(0.3, 0.46, 0.11), Vector3(0.98, 0.23, -1.22), trim, true)

func build_observation_ring() -> void:
	arc("ObservationFloor", Vector2(1.8, 1.6), 0.66, 1.45, 1.56, 37, 323, trim, true)
	arc("ObservationGlazing", Vector2(1.73, 1.53), 0.91, 1.58, 1.96, 39, 321, glass, true)
	# 压边从底板顶面开始，避免相同半径的外壁重叠 1 厘米。
	arc("ObservationSill", Vector2(1.8, 1.6), 0.78, 1.56, 1.64, 37, 323, shell, true)
	arc("ObservationCornice", Vector2(1.8, 1.6), 0.78, 1.96, 2.05, 37, 323, shell, true)
	# 端柱直接取上下边框首段的半截轮廓，避免轴对齐方柱横向穿出扇形。
	var start := deg_to_rad(37.0)
	var next := start + deg_to_rad(286.0 / ceili(286.0 / 8.0))
	var outer_start := Vector2(1.8 * sin(start), 1.6 * cos(start))
	var outer_end := outer_start.lerp(Vector2(1.8 * sin(next), 1.6 * cos(next)), 0.5)
	for side in [-1.0, 1.0]:
		var outline := PackedVector2Array([outer_start * 0.78, outer_start, outer_end, outer_end * 0.78])
		if side < 0:
			for i in outline.size(): outline[i].x *= -1.0
			outline.reverse()
		# 顶面由压顶完整覆盖，保留一份封面；玻璃端面藏在端柱内部。
		extrusion("ObservationEnd" + ("West" if side < 0 else "East"), outline, 1.64, 1.96, shell, false)

func build_upper_pod() -> void:
	arc("UpperPodGlazing", Vector2(1.65, 1.43), 0.87, 3.08, 3.23, 40, 320, glass, true)
	arc("UpperCrescent", Vector2(1.76, 1.56), 0.62, 3.2, 3.56, 37, 323, shell, true, true)
	box("RoofVentWest", Vector3(0.34, 0.06, 0.23), Vector3(-0.72, 3.56, -1.03), trim)
	box("RoofVentNorth", Vector3(0.27, 0.06, 0.25), Vector3(-0.07, 3.56, -1.29), instrument)
	cylinder("RoofInspectionCap", 0.17, 0.035, Vector3(0.72, 3.56, -1.05), instrument)
	# 真实承托保留中央开口；不把星球包进透明圆筒。
	box("WestRearSupport", Vector3(0.13, 1.05, 0.13), Vector3(-1.07, 2.565, -0.86), trim, true)
	box("RearRoofConnector", Vector3(0.91, 0.14, 0.25), Vector3(0.85, 3.33, -1.09), instrument, true)

func build_instruments() -> void:
	box("NortheastInstrumentMast", Vector3(0.29, 3.5, 0.32), Vector3(1.29, 1.75, -0.98), instrument, true)
	for i in 2:
		cylinder("MastPipe%d" % i, 0.035, 3.26, Vector3(1.48 + 0.08 * i, 1.72, -0.99), trim)
	var gauge := cylinder("EastFacingInstrumentHub", 0.2, 0.10, Vector3(1.53, 2.53, -0.98), trim)
	gauge.rotation.z = -PI * 0.5
	var face := cylinder("InstrumentHubFace", 0.14, 0.012, Vector3(1.59, 2.53, -0.98), glass)
	face.rotation.z = -PI * 0.5
	cylinder("Antenna", 0.025, 0.27, Vector3(1.29, 3.595, -0.98), instrument)
	cylinder("AntennaTip", 0.035, 0.07, Vector3(1.29, 3.765, -0.98), specimen)

func build_cosmos() -> void:
	cylinder("MagneticCradle", 0.60, 0.13, Vector3(0, 1.63, 0), trim)
	cylinder("CradleInset", 0.48, 0.022, Vector3(0, 1.708, 0), glass)
	sphere("PocketPlanet", 0.55, Vector3(0, 2.52, 0))
	sphere("Moon", 0.12, Vector3(0.82, 2.49, 0.13))
	build_cyber_orbit()

func build_cyber_orbit() -> void:
	var center := Vector3(0, 2.52, 0)
	var size_ratio := 0.71 / 2.0
	var target := Basis.from_euler(Vector3(57, 0, -24) * PI / 180.0) * Basis(Vector3.RIGHT, PI * 0.5)
	var original := Basis.from_euler(Vector3(0, 15, -20) * PI / 180.0)
	var placement := (target * original.inverse()).scaled(Vector3.ONE * size_ratio)
	var shared: ShaderMaterial = load(CYBER_ORBIT + "material.tres")
	var orbit := mesh_part("Orbit", load(CYBER_ORBIT + "orbit_a.res"), center - placement * Vector3(0, 3.18, 0), shared)
	orbit.basis = placement
	mark_cyber_orbit(orbit, shared)
	var regions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CYBER_ORBIT + "uv_layout.json")).regions
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 原轨道上的三段青蓝嵌条；小球保留可读的线宽，不新增灯或粒子。
	for phase in [0.3, 2.35, 4.4]:
		for side in [-1.0, 1.0]:
			for i in 12:
				var a: float = phase + 0.52 * float(i) / 12.0
				var b: float = phase + 0.52 * float(i + 1) / 12.0
				var points: Array[Vector3] = []
				for item: Vector2 in [Vector2(a, -1), Vector2(b, -1), Vector2(b, 1), Vector2(a, 1)]:
					var radius := 0.71 - 0.018 * size_ratio + item.y * 0.008
					points.append(target * Vector3(cos(item.x) * radius, sin(item.x) * radius, side * (0.06 * size_ratio + 0.002)))
				cyber_quad(st, regions.cyan, points, target * Vector3(0, 0, side))
	for i in 2:
		var angle := PI * i + 0.45
		var joint := target * Vector3(cos(angle) * 0.71, sin(angle) * 0.71, 0)
		var local := target * Basis(Vector3.BACK, angle)
		cyber_box(st, regions.silver, joint, Vector3(0.3, 0.24, 0.18) * size_ratio, local)
		for side in [-1.0, 1.0]:
			cyber_box(st, regions.amber, joint + local * Vector3(0, 0, side * 0.094 * size_ratio), Vector3(0.075, 0.12, 0.008) * size_ratio, local)
	var details := mesh_part("OrbitDetails", st.commit(), center, shared)
	mark_cyber_orbit(details, shared)
	building.set_meta("orbit_style", "shared_cyber_armillary")

func mark_cyber_orbit(node: MeshInstance3D, shared: Material) -> void:
	node.set_meta("shared_orbit_atlas", true)
	node.set_meta("production_material", shared)
	node.set_meta("blockout_material", trim)

func cyber_quad(st: SurfaceTool, rect: Array, points: Array[Vector3], normal: Vector3) -> void:
	var coords := [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]
	for indices: Array in [[0, 1, 2], [0, 2, 3]]:
		if (points[indices[1]] - points[indices[0]]).cross(points[indices[2]] - points[indices[0]]).dot(normal) > 0:
			indices = [indices[0], indices[2], indices[1]]
		for index: int in indices:
			st.set_normal(normal)
			st.set_uv((Vector2(rect[0], rect[1]) + Vector2(2, 2) + coords[index] * Vector2(rect[2] - 4, rect[3] - 4)) / 512.0)
			st.add_vertex(points[index])

func cyber_box(st: SurfaceTool, rect: Array, center: Vector3, size: Vector3, basis: Basis) -> void:
	for axis in 3:
		for side in [-1.0, 1.0]:
			var normal := Vector3.ZERO
			normal[axis] = side
			var points: Array[Vector3] = []
			for coord: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var point := normal * 0.5
				point[(axis + 1) % 3] = coord.x * 0.5
				point[(axis + 2) % 3] = coord.y * 0.5
				points.append(center + basis * (point * size))
			cyber_quad(st, rect, points, basis * normal)
