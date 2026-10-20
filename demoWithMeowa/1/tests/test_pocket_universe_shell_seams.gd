extends SceneTree
## 纯网格数据回归：同向共面三角形不能占用同一片可见表面。

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func projected(points: Array, axis: int) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point: Vector3 in points: result.append(Vector2(point[(axis+1)%3], point[(axis+2)%3]))
	return result

func covered_by_rim(point: Vector3, rim: MeshInstance3D, height: float) -> bool:
	var faces := rim.mesh.get_faces()
	for i in range(0, faces.size(), 3):
		var polygon := PackedVector2Array()
		for j in 3:
			var p := rim.transform * faces[i+j]
			if absf(p.y-height) > 0.00001: break
			polygon.append(Vector2(p.x,p.z))
		if polygon.size() != 3: continue
		for expanded in Geometry2D.offset_polygon(polygon,0.00002):
			if Geometry2D.is_point_in_polygon(Vector2(point.x,point.z),expanded): return true
	return false

func audit(path: String) -> void:
	var building: Node3D = load(path).instantiate()
	var sill: MeshInstance3D = building.get_node("Model/ObservationSill")
	var cornice: MeshInstance3D = building.get_node("Model/ObservationCornice")
	var sill_top := (sill.transform * sill.mesh.get_aabb()).end.y
	var cornice_bottom := (cornice.transform * cornice.mesh.get_aabb()).position.y
	for name in ["ObservationEndWest", "ObservationEndEast"]:
		var post: MeshInstance3D = building.get_node("Model/" + name)
		var bounds := post.transform * post.mesh.get_aabb()
		var fits_rims := true
		for vertex in post.mesh.get_faces():
			var p := post.transform * vertex
			fits_rims = fits_rims and covered_by_rim(p,sill,sill_top) and covered_by_rim(p,cornice,cornice_bottom)
		check(fits_rims,"%s：%s 的整个平面轮廓必须位于上下扇形边框内，不能横向凸出方块" % [path,name])
		check(bounds.position.y >= sill_top - 0.00001 and bounds.end.y <= cornice_bottom + 0.00001,
			"%s：%s 柱身不能穿进下沿或压顶" % [path, name])
		check(is_equal_approx(bounds.position.y, sill_top) and is_equal_approx(bounds.end.y, cornice_bottom),
			"%s：%s 与上下边框直接接合，不能悬空" % [path, name])
		var shapes: Array[CollisionShape3D] = []
		for child: CollisionShape3D in building.get_node("BuildingCollision").get_children():
			if String(child.name).begins_with(name): shapes.append(child)
		var collision_bounds := AABB()
		var collision_fits_rims := true
		for i in shapes.size():
			var part_bounds := shapes[i].transform * shapes[i].shape.get_debug_mesh().get_aabb()
			collision_bounds = part_bounds if i == 0 else collision_bounds.merge(part_bounds)
			for vertex in shapes[i].shape.get_debug_mesh().get_faces():
				var p := shapes[i].transform * vertex
				collision_fits_rims = collision_fits_rims and covered_by_rim(p,sill,sill_top) and covered_by_rim(p,cornice,cornice_bottom)
		check(not shapes.is_empty() and collision_bounds.is_equal_approx(bounds),
			"%s：%s 碰撞跟随修正后的短柱，不保留外露的不可见碰撞" % [path, name])
		check(collision_fits_rims,"%s：%s 碰撞也不能凸出扇形轮廓" % [path,name])
	var faces: Array[Dictionary] = []
	for part: MeshInstance3D in building.get_node("Model").get_children():
		if not String(part.name).begins_with("Observation") and part.name not in [&"UpperCrescent", &"UpperPodGlazing", &"LowerLaboratory"]: continue
		var points := part.mesh.get_faces()
		for i in range(0, points.size(), 3):
			var a := part.transform * points[i]
			var b := part.transform * points[i+1]
			var c := part.transform * points[i+2]
			var cross := (b-a).cross(c-a)
			if cross.length_squared() < 0.000000000001: continue
			var normal := cross.normalized()
			faces.append({"part":part.name, "points":[a,b,c], "normal":normal, "d":normal.dot(a), "box":AABB(a,Vector3.ZERO).expand(b).expand(c)})
	var overlaps := {}
	for i in faces.size():
		var a: Dictionary = faces[i]
		for j in range(i+1, faces.size()):
			var b: Dictionary = faces[j]
			# 内部贴合面的朝向相反，只有同向重复覆盖才会争抢显示。
			if a.normal.dot(b.normal) < 0.99999 or absf(a.d-b.d) > 0.00005: continue
			if not a.box.grow(0.0001).intersects(b.box.grow(0.0001)): continue
			var axis: int = a.normal.abs().max_axis_index()
			var area := 0.0
			for polygon: PackedVector2Array in Geometry2D.intersect_polygons(projected(a.points, axis), projected(b.points, axis)):
				var sum := 0.0
				for k in polygon.size(): sum += polygon[k].cross(polygon[(k+1)%polygon.size()])
				area += absf(sum)*0.5
			if area <= 0.0000001: continue
			var key := "%s / %s" % [a.part,b.part]
			overlaps[key] = overlaps.get(key,0.0) + area
	check(overlaps.is_empty(), "%s：白色扇形与边缘不应存在同向共面覆盖：%s" % [path, str(overlaps)])
	building.free()

func run() -> void:
	audit("res://assets/models/pocket_universe_nursery/source/whitebox.tscn")
	audit("res://scenes/buildings/pocket_universe_nursery.tscn")
	print("Pocket universe shell seams: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
