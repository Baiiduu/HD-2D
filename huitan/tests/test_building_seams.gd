extends SceneTree

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("FAIL: ",message)

func vertices(mesh: Mesh) -> Array[Vector3]:
	var arrays := mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var result: Array[Vector3] = []
	var indices: Variant = arrays[Mesh.ARRAY_INDEX]
	if indices != null:
		for index: int in indices:
			result.append(points[index])
	else:
		result.assign(points)
	return result

func boundary_edges(mesh: Mesh) -> int:
	var points := vertices(mesh)
	var edges: Dictionary = {}
	for triangle in range(0,points.size(),3):
		for edge in 3:
			var a := points[triangle+edge]
			var b := points[triangle+(edge+1)%3]
			var ka := str(Vector3i(roundi(a.x*100000),roundi(a.y*100000),roundi(a.z*100000)))
			var kb := str(Vector3i(roundi(b.x*100000),roundi(b.y*100000),roundi(b.z*100000)))
			var key := ka+"/"+kb if ka < kb else kb+"/"+ka
			edges[key] = int(edges.get(key,0))+1
	var count := 0
	for occurrences: int in edges.values():
		if occurrences == 1:
			count += 1
	return count

func wall_covers(home: Node3D, axis: int, plane: float, point: Vector2) -> bool:
	for child in home.get_node("Geometry").get_children():
		if not child is MeshInstance3D:
			continue
		var points := vertices(child.mesh)
		for triangle in range(0,points.size(),3):
			var p: Array[Vector2] = []
			for i in 3:
				var v := points[triangle+i]
				if absf(v[axis]-plane) > 0.0001:
					break
				p.append(Vector2(v.z,v.y) if axis == 0 else Vector2(v.x,v.y))
			if p.size() == 3:
				var a := (p[1]-p[0]).cross(point-p[0])
				var b := (p[2]-p[1]).cross(point-p[1])
				var c := (p[0]-p[2]).cross(point-p[2])
				if (a >= -0.00001 and b >= -0.00001 and c >= -0.00001) or (a <= 0.00001 and b <= 0.00001 and c <= 0.00001):
					return true
	return false

func tile_rows_follow_ridge(mesh: Mesh) -> bool:
	var arrays := mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var faces := 0
	for triangle in range(0,indices.size(),3):
		var normal := normals[indices[triangle]]
		if normal.y < 0.5 or (absf(normal.x) < 0.05 and absf(normal.z) < 0.05):
			continue
		faces += 1
		for edge in 3:
			var a := indices[triangle+edge]
			var b := indices[triangle+(edge+1)%3]
			if absf(uv[a].y-uv[b].y) < 0.0001 and absf(uv[a].x-uv[b].x) > 0.0001:
				var delta := points[b]-points[a]
				if absf(normal.x) > 0.05 and absf(delta.x) > 0.0001:
					return false
				if absf(normal.z) > 0.05 and absf(delta.z) > 0.0001:
					return false
	return faces >= 4

func _run() -> void:
	var scene: Node3D = load("res://scenes/world/world.tscn").instantiate()
	scene.get_node("LoadoutUI").save_enabled = false
	root.add_child(scene)
	current_scene = scene
	for frame in 5:
		await physics_frame
	var home: Node3D = scene.get_node("HouseSite/Home")
	var hut: Node3D = scene.get_node("TrainingHut")
	for building: Node3D in [home,hut]:
		var open := boundary_edges(building.get_node("Geometry/Roof").mesh)
		print(building.name," roof open edges=",open)
		check(open == 0,"Roof has no open mesh edges: "+building.name)
		var roof_mesh: Mesh = building.get_node("Geometry/Roof").mesh
		check(tile_rows_follow_ridge(roof_mesh),"Tile rows follow ridge instead of running up the slope: "+building.name)
		check(roof_mesh.surface_get_material(0).texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC,"Slanted roof retains pixels with mipmaps and anisotropy: "+building.name)
	var offset: float = home.depth*0.5*0.85
	var roof_y: float = home.eave_height+home.roof_rise*(1.0-offset/(home.depth*0.5+0.3))
	check(wall_covers(home,0,home.width*0.5,Vector2(offset,roof_y-0.025)),"House gable reaches the actual roof slope")
	offset = hut.width*0.5*0.85
	roof_y = hut.eave_height+hut.roof_rise*(1.0-offset/(hut.width*0.5+0.3))
	check(wall_covers(hut,2,hut.depth*0.5,Vector2(offset,roof_y-0.025)),"Training gable reaches the actual roof slope")
	var floor := hut.get_node("Geometry/Stone") as MeshInstance3D
	# Stone includes column footings, so use the actual horizontal canopy-floor faces.
	var floor_top := -INF
	var floor_points := vertices(floor.mesh)
	for triangle in range(0,floor_points.size(),3):
		var a := floor_points[triangle]
		var b := floor_points[triangle+1]
		var c := floor_points[triangle+2]
		if minf(a.z,minf(b.z,c.z)) >= hut.depth*0.5-0.1 and absf(a.y-b.y) < 0.0001 and absf(a.y-c.y) < 0.0001 and minf(a.x,minf(b.x,c.x)) < -1.0 and maxf(a.x,maxf(b.x,c.x)) > 1.0:
			floor_top = maxf(floor_top,a.y)
	var collision: CollisionShape3D = hut.get_node("Geometry/Collision/CanopyFloor")
	var collision_top: float = collision.position.y+collision.shape.size.y*0.5
	check(floor_top >= 0.015,"Canopy floor is separated from terrain instead of coplanar")
	check(is_equal_approx(floor_top,collision_top),"Canopy visual floor and collision stay aligned")
	for building: Node3D in [home,hut]:
		var old_width: float = building.width
		var old_rise: float = building.roof_rise
		building.width = 4.0
		building.roof_rise = 2.5
		await process_frame
		check(boundary_edges(building.get_node("Geometry/Roof").mesh) == 0,"Narrow steep roof stays closed after dimension edits: "+building.name)
		building.width = 12.0
		building.roof_rise = 0.7
		await process_frame
		check(boundary_edges(building.get_node("Geometry/Roof").mesh) == 0,"Wide shallow roof stays closed after dimension edits: "+building.name)
		building.width = old_width
		building.roof_rise = old_rise
		await process_frame
	print("Building seams: %d checks, %d failures" % [checks,failures.size()])
	scene.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
