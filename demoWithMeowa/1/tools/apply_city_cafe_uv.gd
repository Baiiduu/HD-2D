extends SceneTree
## Bake atlas UVs into the existing editable mesh; no runtime builder is attached.

const SCENE := "res://scenes/buildings/city_cafe.tscn"
const LAYOUT := "res://assets/models/city_cafe/cafe_uv_layout.json"
const MATERIAL := "res://assets/models/city_cafe/cafe_material.tres"
var layout: Dictionary
var cafe: Node3D
var to_cafe := Transform3D.IDENTITY

func _initialize() -> void:
	run.call_deferred()

func rect_uv(key: String, u: float, v: float) -> Vector2:
	var r: Array = layout.regions[key].rect
	return Vector2(float(r[0]) + 0.5 + clampf(u, 0, 1) * (float(r[2]) - 1),
		float(r[1]) + 0.5 + clampf(v, 0, 1) * (float(r[3]) - 1)) / Vector2(layout.atlas_size[0], layout.atlas_size[1])

func projected_uv(key: String, point: Vector3, normal: Vector3, bounds: AABB) -> Vector2:
	var u: float
	var v: float
	var width: float
	var height: float
	if absf(normal.y) > 0.6:
		if bounds.size.z > bounds.size.x:
			u = point.z - bounds.position.z
			v = point.x - bounds.position.x
			width = bounds.size.z
			height = bounds.size.x
		else:
			u = point.x - bounds.position.x
			v = point.z - bounds.position.z
			width = bounds.size.x
			height = bounds.size.z
	elif absf(normal.x) > 0.6:
		u = bounds.end.z - point.z
		v = bounds.end.y - point.y
		width = bounds.size.z
		height = bounds.size.y
	else:
		u = point.x - bounds.position.x
		v = bounds.end.y - point.y
		width = bounds.size.x
		height = bounds.size.y
	# Solid-color swatches cover a whole face. Metric clamping could collapse an
	# inset edge of the mitered canopy when both ends fall beyond the small tile.
	if key in ["awning_plain", "plain_wall", "metal"]:
		return rect_uv(key, u / width, v / height)
	var r: Array = layout.regions[key].rect
	var density := float(layout.get("pixels_per_meter", 40.0))
	return rect_uv(key, u * density / (float(r[2]) - 1), v * density / (float(r[3]) - 1))

func uv_for(node: MeshInstance3D, point: Vector3, normal: Vector3, piece := "") -> Vector2:
	var p := to_cafe * point
	var n := (to_cafe.basis * normal).normalized()
	var bounds := node.mesh.get_aabb()
	var size := bounds.size
	var local := point - bounds.position
	var group := str(node.get_parent().name)
	if group == "Shell":
		if n.z > 0.9:
			if piece == "upper":
				return rect_uv("front_upper", (p.x + 1.5) / 3.0, (2.54 - p.y) / 0.84)
			if piece == "band":
				return rect_uv("front_band", (p.x + 1.5) / 3.0, (1.7 - p.y) / 0.38)
			var columns: Array = layout.front_lower_columns_px
			var width := float(layout.regions.front_lower.rect[2]) - 1.0
			var u: float
			if node.name == &"GroundCore":
				u = lerpf(float(columns[0]), float(columns[1]), (p.x + 0.42) / 0.84) / width
			elif node.name == &"FrontWestWing":
				u = lerpf(0, float(columns[0]), (p.x + 1.5) / 1.08) / width
			else:
				u = lerpf(float(columns[1]), width, (p.x - 0.42) / 1.08) / width
			return rect_uv("front_lower", u, (1.32 - p.y) / 1.32)
		if n.z < -0.9:
			return rect_uv("back", (1.5 - p.x) / 3.0, (2.54 - p.y) / 2.54)
		if n.x > 0.9 and p.x > 1.49:
			return rect_uv("right", (1.05 - p.z) / 2.1, (2.54 - p.y) / 2.54)
		if n.x < -0.9 and p.x < -1.49:
			return rect_uv("left", (p.z + 1.05) / 2.1, (2.54 - p.y) / 2.54)
		return projected_uv("plain_wall", point, normal, bounds)
	if group == "CornerAwning":
		if node.name == &"FrontSlope" and n.y > 0.5:
			return rect_uv("awning_front", (p.x + 1.55) / 3.45, (p.z - 1.065) / 0.375)
		if node.name == &"SideSlope" and n.y > 0.5:
			return rect_uv("awning_side", (p.z + 1.03) / 2.47, (p.x - 1.55) / 0.35)
		if node.name == &"FrontValance" and absf(n.z) > 0.9:
			return rect_uv("valance_front", (p.x + 1.55) / 3.45, (1.24 - p.y) / 0.08)
		if node.name == &"SideValance" and absf(n.x) > 0.9:
			return rect_uv("valance_side", (p.z + 1.03) / 2.455, (1.24 - p.y) / 0.08)
		return projected_uv("awning_plain", point, normal, bounds)
	if group == "Roof":
		if node.name == &"Deck" and n.y > 0.9:
			return rect_uv("roof", (p.x + 1.56) / 3.12, (p.z + 1.11) / 2.22)
		return projected_uv("coping", point, normal, bounds)
	if node.name == &"SignBlank":
		if absf(n.x) > 0.9:
			return rect_uv("sign", local.z / size.z, 1 - local.y / size.y)
		return projected_uv("awning_plain", point, normal, bounds)
	return projected_uv("metal", point, normal, bounds)

func vertex(stream: SurfaceTool, node: MeshInstance3D, point: Vector3, normal: Vector3, piece := "") -> void:
	stream.set_normal(normal)
	stream.set_uv(uv_for(node, point, normal, piece))
	stream.add_vertex(point)

func front_quad(stream: SurfaceTool, node: MeshInstance3D, x0: float, x1: float, y0: float, y1: float, z: float, piece: String) -> void:
	var points := [Vector3(x0, y0, z), Vector3(x1, y0, z), Vector3(x1, y1, z), Vector3(x0, y1, z)]
	for index in [0, 2, 1, 0, 3, 2]: vertex(stream, node, points[index], Vector3.BACK, piece)

func bake(node: MeshInstance3D, material: Material) -> void:
	to_cafe = cafe.global_transform.affine_inverse() * node.global_transform
	var stream := SurfaceTool.new()
	stream.begin(Mesh.PRIMITIVE_TRIANGLES)
	var front_rebuild := str(node.get_parent().name) == "Shell" and node.name in [&"GroundCore", &"UpperFloor"]
	for surface in node.mesh.get_surface_count():
		var arrays := node.mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := indices.size() if not indices.is_empty() else points.size()
		for offset in range(0, count, 3):
			var first := indices[offset] if not indices.is_empty() else offset
			if front_rebuild and normals[first].z > 0.9: continue
			for index in 3:
				var slot := indices[offset + index] if not indices.is_empty() else offset + index
				vertex(stream, node, points[slot], normals[slot])
	if front_rebuild:
		var b := node.mesh.get_aabb()
		if node.name == &"GroundCore":
			# Hidden parts of this face are covered by the two front wings.
			front_quad(stream, node, -0.42, 0.42, b.position.y, b.end.y, b.end.z, "door")
		else:
			var cut := 1.7 - node.position.y
			front_quad(stream, node, b.position.x, b.end.x, b.position.y, cut, b.end.z, "band")
			front_quad(stream, node, b.position.x, b.end.x, cut, b.end.y, b.end.z, "upper")
	stream.index()
	stream.generate_tangents()
	var mesh := stream.commit()
	mesh.resource_name = node.mesh.resource_name
	node.mesh = mesh
	node.material_override = material

func run() -> void:
	layout = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	cafe = load(SCENE).instantiate()
	root.add_child(cafe)
	var material: Material = load(MATERIAL)
	assert(material != null)
	var count := 0
	for node: MeshInstance3D in cafe.find_children("*", "MeshInstance3D", true, false):
		# These UVs belong to the dedicated rooftop builder and its named regions.
		if str(cafe.get_path_to(node)).begins_with("Model/RooftopDetails/"):
			continue
		bake(node, material)
		count += 1
	cafe.set_meta(&"asset_stage", "textured")
	cafe.set_meta(&"reference", "docs/references/city-buildings/cafe-orthographic.png")
	cafe.set_meta(&"texture_stage", "Meowa native 80px/m; shared 1024x1024 albedo, OpenGL normal and ORM")
	cafe.set_meta(&"texture_plan", "One shared material; front, side and roof at the original hospital/store reference density")
	cafe.set_meta(&"texel_density_px_m", int(layout.get("pixels_per_meter", 40)))
	cafe.set_meta(&"uv_layout", LAYOUT)
	var packed := PackedScene.new()
	assert(packed.pack(cafe) == OK)
	assert(ResourceSaver.save(packed, SCENE) == OK)
	print("CAFE_UV_BAKED meshes=%d material=1 textures=3" % count)
	cafe.free()
	quit()
