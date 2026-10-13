@tool
extends Node3D

## 只用于正式地图视觉审阅的 3D 植物；没有种植、攻击或生命逻辑。
const SURFACE := preload("res://shaders/plant_surface.gdshader")

@export_group("地图与体量")
## 设置后按地形顶面贴地；移动摆放后可点击刷新按钮重新贴地。
@export var terrain: Terrain
## 整株的缩放比例；1 时最高约 1.35 米，地面叶片跨度约 1.2 米。
@export_range(0.4, 2.0, 0.05) var plant_scale := 1.0:
	set(value): plant_scale = value; _queue_build()
## 0 度朝本地 +Z，改变头部、喷口与叶片的整体水平朝向。
@export_range(-180.0, 180.0, 1.0) var facing_degrees := 30.0:
	set(value): facing_degrees = value; _queue_build()
## 头部相对默认尺寸；不改变茎高。
@export_range(0.6, 1.4, 0.05) var head_scale := 1.0:
	set(value): head_scale = value; _queue_build()
## 地面叶片的长度和宽度；不改变整株高度。
@export_range(0.6, 1.4, 0.05) var leaf_scale := 1.0:
	set(value): leaf_scale = value; _queue_build()
@export_tool_button("刷新植物并贴地", "Reload") var refresh = _build

@export_group("植物材质")
@export var head_color := Color("8aaa42"):
	set(value): head_color = value; _queue_build()
@export var leaf_color := Color("4f782e"):
	set(value): leaf_color = value; _queue_build()
@export var stem_color := Color("608536"):
	set(value): stem_color = value; _queue_build()
## 固定在模型表面的小块明暗变化，0 使用纯色。
@export_range(0.0, 0.3, 0.01) var mottling := 0.14:
	set(value): mottling = value; _queue_build()
## 表面色块的物理尺寸；默认沿用人物和地编的像素尺度。
@export_range(0.01, 0.08, 0.001) var pixel_meters := 0.0234375:
	set(value): pixel_meters = value; _queue_build()

@export_group("待机表现")
## 只摆动模型，根部保持原位，不跟随人物或自动寻找目标。
@export var idle_enabled := true
## 茎与头部左右摆动幅度，度；0 保持静止。
@export_range(0.0, 5.0, 0.1) var sway_degrees := 1.2
## 一次完整摇摆的秒数。
@export_range(1.0, 8.0, 0.1) var sway_period := 3.8

var _queued := false
var _sway: Node3D
var _time := 0.0

func _ready() -> void:
	if terrain and terrain.data and not terrain.data.changed.is_connected(_align_to_ground):
		terrain.data.changed.connect(_align_to_ground)
	_build()
	set_process(not Engine.is_editor_hint())

func _queue_build() -> void:
	if not is_inside_tree() or _queued:
		return
	_queued = true
	_build.call_deferred()

func _build() -> void:
	_queued = false
	if not is_inside_tree():
		return
	var old := get_node_or_null("Geometry")
	if old:
		remove_child(old)
		old.free()
	var body := Node3D.new()
	body.name = "Geometry"
	body.scale = Vector3.ONE * plant_scale
	body.rotation.y = deg_to_rad(facing_degrees)
	add_child(body)
	var head_material := _material(head_color)
	var leaves := _material(leaf_color, true)
	var stem := _material(stem_color)
	var vein := _material(leaf_color.lightened(0.15))
	var dark := _material(Color("20351d"))
	var eye_material := _material(Color("16261a"))
	var glint := _material(Color("d9dfaa"))
	for i in 4:
		var leaf := _leaf(0.62 * leaf_scale, 0.24 * leaf_scale, 0.12, leaves)
		leaf.name = "RootLeaf%d" % i
		leaf.rotation.y = deg_to_rad(45.0 + i * 90.0)
		leaf.position.y = 0.025
		body.add_child(leaf)
		_add_vein(leaf, 0.62 * leaf_scale, 0.12, vein)
	_sway = Node3D.new()
	_sway.name = "StemAndHead"
	body.add_child(_sway)
	var stem_points: Array[Vector3] = []
	for i in 19:
		var t := i / 18.0
		stem_points.append(_stem_point(t))
	_tube(_sway, "CurvedStem", stem_points, 0.059, 0.042, stem)
	for side in [-1, 1]:
		var leaf := _leaf(0.38, 0.14, 0.14, leaves)
		leaf.name = "StemLeaf%d" % side
		leaf.position = _stem_point(0.46)
		leaf.rotation.y = side * deg_to_rad(100.0)
		_sway.add_child(leaf)
		_add_vein(leaf, 0.38, 0.14, vein)
	var head := Node3D.new()
	head.name = "Head"
	head.position.y = 1.01
	head.scale = Vector3.ONE * head_scale
	_sway.add_child(head)
	_sphere(head, "Bulb", Vector3.ZERO, Vector3(0.35, 0.31, 0.34), head_material)
	_mesh(head, "Nozzle", _nozzle(), head_material)
	_sphere(head, "MouthDepth", Vector3(0, 0.025, 0.395), Vector3(0.118, 0.118, 0.025), dark)
	for side in [-1, 1]:
		var eye := _sphere(head, "Eye%d" % side, Vector3(side * 0.255, 0.09, 0.215), Vector3(0.038, 0.064, 0.025), eye_material)
		eye.rotation.y = side * deg_to_rad(42.0)
		_sphere(eye, "Glint", Vector3(-0.16, 0.28, 1.0), Vector3(0.2, 0.17, 0.12), glint)
	var crown := _leaf(0.24, 0.085, 0.08, leaves)
	crown.name = "CrownLeaf"
	crown.position = Vector3(0, 0.2, -0.23)
	crown.rotation.x = deg_to_rad(-35.0)
	crown.rotation.y = PI
	head.add_child(crown)
	_align_to_ground()

func _align_to_ground() -> void:
	if not is_inside_tree() or not terrain or not terrain.data:
		return
	var cell := terrain.data.world_to_cell(terrain.to_local(global_position))
	if terrain.data.has_cell(cell):
		global_position.y = terrain.global_position.y + terrain.data.get_level(cell) * terrain.data.layer_height

func _process(delta: float) -> void:
	if not is_instance_valid(_sway):
		return
	_time += delta
	var angle := deg_to_rad(sway_degrees) if idle_enabled else 0.0
	_sway.rotation.z = sin(_time * TAU / sway_period) * angle
	_sway.rotation.x = sin(_time * TAU / sway_period + 0.8) * angle * 0.35

func _material(color: Color, is_leaf := false) -> ShaderMaterial:
	var result := ShaderMaterial.new()
	result.shader = SURFACE
	result.set_shader_parameter("plant_color", color)
	result.set_shader_parameter("mottling", mottling)
	result.set_shader_parameter("pixel_meters", pixel_meters)
	result.set_shader_parameter("leaf_surface", is_leaf)
	return result

func _mesh(parent: Node3D, node_name: String, shape: Mesh, material: Material) -> MeshInstance3D:
	var result := MeshInstance3D.new()
	result.name = node_name
	result.mesh = shape
	result.material_override = material
	parent.add_child(result)
	return result

func _sphere(parent: Node3D, node_name: String, at: Vector3, radii: Vector3, material: Material) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = 1.0
	shape.height = 2.0
	shape.radial_segments = 32 if node_name == "Bulb" else 16
	shape.rings = 16 if node_name == "Bulb" else 8
	var result := _mesh(parent, node_name, shape, material)
	result.position = at
	result.scale = radii
	return result

func _leaf(length: float, width: float, arch: float, material: Material) -> MeshInstance3D:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for step in 16:
		for column in 8:
			var uv := PackedVector2Array([Vector2(column / 8.0, step / 16.0), Vector2((column + 1) / 8.0, step / 16.0), Vector2(column / 8.0, (step + 1) / 16.0), Vector2((column + 1) / 8.0, (step + 1) / 16.0)])
			var points := PackedVector3Array()
			var normals := PackedVector3Array()
			for coordinate in uv:
				points.append(_leaf_point(coordinate, length, width, arch))
				var across := _leaf_point(coordinate + Vector2(0.002, 0), length, width, arch) - _leaf_point(coordinate - Vector2(0.002, 0), length, width, arch)
				var along := _leaf_point(coordinate + Vector2(0, 0.002), length, width, arch) - _leaf_point(coordinate - Vector2(0, 0.002), length, width, arch)
				var normal := along.cross(across).normalized()
				normals.append(normal if normal.length_squared() > 0.0 else Vector3.UP)
			for face in [PackedInt32Array([0, 1, 2]), PackedInt32Array([1, 3, 2])]:
				for bottom in [false, true]:
					var triangle := PackedVector3Array()
					var triangle_normals := PackedVector3Array()
					var triangle_uv := PackedVector2Array()
					for index in face:
						triangle.append(points[index] + (Vector3.DOWN * 0.025 if bottom else Vector3.ZERO))
						triangle_normals.append(normals[index] * (-1.0 if bottom else 1.0))
						triangle_uv.append(uv[index])
					_smooth_triangle(surface, triangle, triangle_normals, triangle_uv)
		for edge in [0, 2]:
			var a := _leaf_point(Vector2(edge / 2.0, step / 16.0), length, width, arch)
			var b := _leaf_point(Vector2(edge / 2.0, (step + 1) / 16.0), length, width, arch)
			var thickness := Vector3.DOWN * 0.025
			var outward := Vector3.LEFT if edge == 0 else Vector3.RIGHT
			surface.set_uv(Vector2(edge / 2.0, step / 16.0))
			_triangle(surface, a, b, a + thickness, outward)
			_triangle(surface, b, b + thickness, a + thickness, outward)
	var result := MeshInstance3D.new()
	result.mesh = surface.commit()
	result.material_override = material
	return result

func _leaf_point(uv: Vector2, length: float, width: float, arch: float) -> Vector3:
	var t := clampf(uv.y, 0.0, 1.0)
	var side := (uv.x - 0.5) * 2.0
	var curve := sin(t * PI)
	var span := pow(maxf(curve, 0.0), 0.8) * width * (1.0 + 0.06 * sin(t * TAU * 2.0))
	var x := side * span + 0.04 * curve * curve
	var y := curve * arch * (1.0 - absf(side) * 0.55) + side * sin(t * TAU) * 0.025
	return Vector3(x, y, length * t)

func _stem_point(t: float) -> Vector3:
	var u := 1.0 - t
	return Vector3(0, 0.04, 0) * u * u * u + Vector3(-0.18, 0.32, -0.05) * 3.0 * u * u * t + Vector3(0.06, 0.78, 0.015) * 3.0 * u * t * t + Vector3(0, 1.01, 0) * t * t * t

func _tube(parent: Node3D, node_name: String, points: Array[Vector3], start_radius: float, end_radius: float, material: Material) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	for i in points.size():
		var tangent := (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var reference := Vector3.UP if absf(tangent.dot(Vector3.FORWARD)) > 0.9 else Vector3.FORWARD
		var right := tangent.cross(reference).normalized()
		var forward := right.cross(tangent).normalized()
		var radius := lerpf(start_radius, end_radius, i / float(points.size() - 1))
		var row := PackedVector3Array()
		var normal_row := PackedVector3Array()
		for j in 13:
			var normal := right * cos(j * TAU / 12.0) + forward * sin(j * TAU / 12.0)
			row.append(points[i] + normal * radius)
			normal_row.append(normal)
		rows.append(row)
		normals.append(normal_row)
	for i in points.size() - 1:
		for j in 12:
			_smooth_triangle(surface, PackedVector3Array([rows[i][j], rows[i + 1][j], rows[i][j + 1]]), PackedVector3Array([normals[i][j], normals[i + 1][j], normals[i][j + 1]]), PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]))
			_smooth_triangle(surface, PackedVector3Array([rows[i][j + 1], rows[i + 1][j], rows[i + 1][j + 1]]), PackedVector3Array([normals[i][j + 1], normals[i + 1][j], normals[i + 1][j + 1]]), PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]))
	_mesh(parent, node_name, surface.commit(), material)

func _add_vein(leaf: MeshInstance3D, length: float, arch: float, material: Material) -> void:
	var points: Array[Vector3] = []
	for i in 13:
		var t := (i + 0.3) / 13.6
		points.append(Vector3(0.04 * pow(sin(t * PI), 2.0), sin(t * PI) * arch + 0.004, length * t))
	_tube(leaf, "Midrib", points, 0.008, 0.003, material)

func _nozzle() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# 喷口是有内壁和口沿的真实空心网格；深处另放暗色口腔。
	var rings := [Vector2(0.20, 0.145), Vector2(0.29, 0.127), Vector2(0.38, 0.126), Vector2(0.46, 0.165), Vector2(0.49, 0.177), Vector2(0.515, 0.17), Vector2(0.515, 0.137), Vector2(0.49, 0.13), Vector2(0.39, 0.09)]
	for ring in rings.size() - 1:
		surface.set_color(Color(0.65, 0.72, 0.58) if ring >= 6 else Color.WHITE)
		for i in 32:
			var points := PackedVector3Array()
			for section in [rings[ring], rings[ring + 1]]:
				for angle in [i * TAU / 32.0, (i + 1) * TAU / 32.0]:
					points.append(Vector3(cos(angle) * section.y, sin(angle) * section.y + 0.025, section.x))
			var direction := Vector3(points[0].x, points[0].y - 0.025, 0)
			if ring == 5:
				direction = Vector3.BACK
			elif ring >= 6:
				direction *= -1.0
			_triangle(surface, points[0], points[1], points[2], direction)
			_triangle(surface, points[1], points[3], points[2], direction)
	return surface.commit()

func _smooth_triangle(surface: SurfaceTool, points: PackedVector3Array, normals: PackedVector3Array, uv: PackedVector2Array) -> void:
	var normal := (points[1] - points[0]).cross(points[2] - points[0])
	if normal.length_squared() < 0.00000001:
		return
	var order := [0, 2, 1] if normal.dot(normals[0] + normals[1] + normals[2]) > 0.0 else [0, 1, 2]
	for index in order:
		surface.set_normal(normals[index])
		surface.set_uv(uv[index])
		surface.add_vertex(points[index])

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, outward: Vector3) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.00000001:
		return
	if normal.dot(outward) < 0.0:
		var swap := b
		b = c
		c = swap
		normal *= -1.0
	# Godot 的正面使用顺时针顶点；法线保持朝模型外侧。
	for point in [a, c, b]:
		surface.set_normal(normal.normalized())
		surface.add_vertex(point)
