extends SceneTree
## 离线烘焙：保留模型位置、法线与碰撞，将所有表面接到同一图集。

const SCENE := "res://scenes/buildings/pocket_universe_nursery.tscn"
const ROOT := "res://assets/models/pocket_universe_nursery/"

func _initialize() -> void:
	var building: Node3D = load(ROOT + "source/whitebox.tscn").instantiate()
	bake_scene(building)
	var packed := PackedScene.new()
	assert(packed.pack(building) == OK)
	assert(ResourceSaver.save(packed, SCENE) == OK)
	building.free()
	print("Pocket universe atlas UVs saved; geometry and collision transforms preserved")
	quit()

static func bake_scene(building: Node3D) -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "pocket_universe_uv_layout.json"))
	var material: Material = load(ROOT + "pocket_universe_material.tres")
	assert(material != null)
	for node: MeshInstance3D in building.find_children("*", "MeshInstance3D", true, false):
		if node.get_meta("shared_orbit_atlas", false): continue
		if not node.has_meta("blockout_material"): node.set_meta("blockout_material", node.material_override)
		var stream := SurfaceTool.new()
		stream.begin(Mesh.PRIMITIVE_TRIANGLES)
		for surface in node.mesh.get_surface_count():
			var arrays := node.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for i in range(0, count, 3):
				var slots := [indices[i], indices[i+1], indices[i+2]] if not indices.is_empty() else [i, i+1, i+2]
				var points: Array[Vector3] = [vertices[slots[0]], vertices[slots[1]], vertices[slots[2]]]
				if (points[1]-points[0]).cross(points[2]-points[0]).length_squared() < 0.000000000001: continue
				var label := String(node.name)
				var curved := label == "LowerLaboratory" or label.begins_with("Observation") and not label.begins_with("ObservationEnd") or label in ["UpperPodGlazing", "UpperCrescent", "WestGroundGlazing", "EastGroundGlazing", "EastRearGlazing"]
				if curved and absf(normals[slots[0]].y) < 0.65:
					var radius := radii(label)
					# 裁切只增加共面顶点，不改真实体量；每刀 UV 只落在一个立面。
					for side in 4:
						var polygon := clip_quadrant(points, radius, side)
						for triangle in range(1, polygon.size()-1):
							if (polygon[triangle]-polygon[0]).cross(polygon[triangle+1]-polygon[0]).length_squared() < 0.000000000001: continue
							for p: Vector3 in [polygon[0], polygon[triangle], polygon[triangle+1]]:
								stream.set_normal(normals[slots[0]])
								stream.set_uv(curved_uv(layout, label, p, normals[slots[0]], radius, side))
								stream.add_vertex(p)
				else:
					for slot: int in slots:
						stream.set_normal(normals[slot])
						stream.set_uv(uv_for(layout, node, vertices[slot], normals[slot], uvs[slot]))
						stream.add_vertex(vertices[slot])
		stream.generate_tangents()
		var mesh := stream.commit()
		mesh.resource_name = String(node.name)
		node.mesh = mesh
		node.material_override = material
	building.set_meta("production_stage", "textured_preview")
	building.set_meta("uv_layout", ROOT + "pocket_universe_uv_layout.json")
	building.set_meta("texel_density_px_m", 80)

static func rect_uv(layout: Dictionary, key: String, uv: Vector2) -> Vector2:
	var r: Array = layout.regions[key].rect
	return (Vector2(r[0], r[1]) + Vector2(0.5, 0.5) + uv.clamp(Vector2.ZERO, Vector2.ONE) * Vector2(r[2]-1, r[3]-1)) / Vector2(1024, 1024)

static func radii(label: String) -> Vector2:
	if label in ["ObservationFloor", "ObservationSill", "ObservationCornice"]: return Vector2(1.8, 1.6)
	if label == "ObservationGlazing": return Vector2(1.73, 1.53)
	if label == "UpperPodGlazing": return Vector2(1.65, 1.43)
	if label.ends_with("GroundGlazing") or label == "EastRearGlazing": return Vector2(1.77, 1.57)
	return Vector2(1.76, 1.56)

static func clip_halfplane(input: Array[Vector3], radius: Vector2, plane: Vector2) -> Array[Vector3]:
	var output: Array[Vector3] = []
	if input.is_empty(): return output
	var previous := input.back() as Vector3
	var previous_distance := Vector2(previous.x/radius.x, previous.z/radius.y).dot(plane)
	for point in input:
		var distance := Vector2(point.x/radius.x, point.z/radius.y).dot(plane)
		if (distance >= 0) != (previous_distance >= 0):
			output.append(previous.lerp(point, previous_distance/(previous_distance-distance)))
		if distance >= 0: output.append(point)
		previous = point
		previous_distance = distance
	return output

static func clip_quadrant(points: Array[Vector3], radius: Vector2, side: int) -> Array[Vector3]:
	var angle := side*PI*0.5
	var forward := Vector2(sin(angle), cos(angle))
	var right := Vector2(cos(angle), -sin(angle))
	return clip_halfplane(clip_halfplane(points, radius, forward+right), radius, forward-right)

static func arc_length(radius: Vector2, start: float, end: float) -> float:
	var length := 0.0
	for i in 24:
		var a := lerpf(start, end, (float(i)+0.5)/24.0)
		length += Vector2(radius.x*cos(a), radius.y*sin(a)).length() * (end-start)/24.0
	return length

static func curved_uv(layout: Dictionary, label: String, p: Vector3, normal: Vector3, radius: Vector2, side: int) -> Vector2:
	var key: String = ["front", "right", "back", "left"][side]
	var center := side*PI*0.5
	var angle := center + wrapf(atan2(p.x/radius.x, p.z/radius.y)-center, -PI, PI)
	var start := center-PI*0.25
	var u := arc_length(radius, start, angle)/arc_length(radius, start, center+PI*0.25)
	var radial := Vector3(p.x/radius.x, 0, p.z/radius.y).normalized()
	if label == "LowerLaboratory" and absf(absf(p.x)-0.4) < 0.001 and absf(normal.x) > 0.9:
		return rect_uv(layout, "entry_jamb", Vector2((p.z-1.27)/0.3, 1.0-p.y/1.45))
	if normal.dot(radial) < -0.2:
		var progress := (wrapf(angle, 0, TAU)-deg_to_rad(37.0))/deg_to_rad(286.0)
		if label in ["ObservationGlazing", "UpperPodGlazing"]:
			var top := 1.96 if label == "ObservationGlazing" else 3.23
			return rect_uv(layout, "inner_gallery", Vector2(progress, (top-p.y)/0.5))
		return rect_uv(layout, "inner_upper", Vector2(progress, (3.56-p.y)/0.36 if label == "UpperCrescent" else (2.05-p.y)/0.5))
	return rect_uv(layout, key, Vector2(u, (3.6-p.y)/3.6))

static func plane_uv(node: MeshInstance3D, p: Vector3, n: Vector3) -> Vector2:
	var box := node.mesh.get_aabb()
	var local := (p-box.position)/box.size
	if absf(n.y) > 0.65: return Vector2(local.x, local.z)
	if absf(n.x) > 0.65: return Vector2(1.0-local.z if n.x > 0 else local.z, 1.0-local.y)
	return Vector2(local.x if n.z > 0 else 1.0-local.x, 1.0-local.y)

static func uv_for(layout: Dictionary, node: MeshInstance3D, p: Vector3, n: Vector3, native: Vector2) -> Vector2:
	var label := String(node.name)
	if label in ["PocketPlanet", "Moon", "Orbit"]:
		return rect_uv(layout, {"PocketPlanet": "planet", "Moon": "moon", "Orbit": "orbit"}[label], native)
	if label == "AntennaTip": return rect_uv(layout, "entry_light", native)
	if label == "LowerLaboratory" or label.begins_with("Observation") and not label.begins_with("ObservationEnd") or label in ["UpperPodGlazing", "UpperCrescent", "WestGroundGlazing", "EastGroundGlazing", "EastRearGlazing"]:
		var roof := "lower_roof" if label == "LowerLaboratory" else "upper_roof" if label in ["UpperPodGlazing", "UpperCrescent"] else "gallery_roof"
		return rect_uv(layout, roof if n.y > 0 else "underside", Vector2((p.x+1.8)/3.6, (p.z+1.6)/3.2))
	if node.mesh is CylinderMesh:
		var key := "pipe"
		if absf(n.y) > 0.65:
			key = "hub" if label in ["InstrumentHubFace", "EastFacingInstrumentHub"] else "cradle" if label in ["MagneticCradle", "CradleInset"] else "cap"
			var radius: float = node.mesh.top_radius
			return rect_uv(layout, key, Vector2(0.5+p.x/(2.0*radius), 0.5+p.z/(2.0*radius)))
		return rect_uv(layout, key, native)
	var keys := {"DoorGlass": "main_door", "ServiceDoor": "service_door", "EntryTerminal": "terminal",
		"EntryLightPlaceholder": "entry_light", "EastServicePanel": "service_panel", "RearVentPlaceholder": "rear_vent",
		"RearPlantCabinet": "cabinet", "NortheastInstrumentMast": "mast", "RoofVentWest": "vent", "RoofVentNorth": "vent",
		"WestRearSupport": "equipment", "RearRoofConnector": "equipment", "DoorMullion": "trim"}
	var key: String = keys.get(label, "plain_shell")
	if label.begins_with("RoofVent") and n.y > 0.65: key = "vent_top"
	var uv := plane_uv(node, p, n)
	if key in ["plain_shell", "equipment", "trim"]:
		var r: Array = layout.regions[key].rect
		var dimensions := node.mesh.get_aabb().size
		var face_size := Vector2(dimensions.x, dimensions.z) if absf(n.y) > 0.65 else Vector2(dimensions.z, dimensions.y) if absf(n.x) > 0.65 else Vector2(dimensions.x, dimensions.y)
		uv = Vector2(0.5, 0.5) + (uv-Vector2(0.5, 0.5))*face_size*80.0/Vector2(r[2], r[3])
	return rect_uv(layout, key, uv)
